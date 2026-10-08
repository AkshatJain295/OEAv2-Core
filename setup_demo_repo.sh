#!/usr/bin/env bash
# Creates a PERSONAL demo repository from ./repo and wires it up like the real one:
#   1. creates the repo and pushes the stand-in code, workflows, scripts and configs to main
#   2. creates the qa branch
#   3. invites a reviewer (optional) and creates the GitHub Environments
#   4. applies the branch rulesets LAST, using the exact script the client will run
#
# Usage:
#   OWNER=your-username REPO=oeav2-core-demo REVIEWER=teammate-username ./setup_demo_repo.sh
#
#   OWNER       your GitHub username (required)
#   REPO        name for the demo repo (default: oeav2-core-demo)
#   REVIEWER    a SECOND account that approves PRs / deployments (strongly recommended;
#               without one you cannot approve your own PRs, so merges stay blocked)
#   VISIBILITY  public | private (default: public). Rulesets and environment reviewers
#               need a public repo, or a paid GitHub plan for private ones.
#
# Needs: gh (authenticated, with the `workflow` scope), git, jq.
# Never put real credentials or real company code into this repo.

set -euo pipefail

OWNER="${OWNER:?Set OWNER=<your GitHub username>}"
REPO="${REPO:-oeav2-core-demo}"
REVIEWER="${REVIEWER:-}"
VISIBILITY="${VISIBILITY:-public}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ pre-flight
for tool in gh git jq; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' is not installed."
done
gh auth status >/dev/null 2>&1 || die "Not logged in. Run: gh auth login"

SCOPES=$(gh api -i /user 2>/dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2}' || true)
if [ -n "$SCOPES" ] && [[ "$SCOPES" != *workflow* ]]; then
  die "Your gh token lacks the 'workflow' scope, which is needed to push workflow files. Run: gh auth refresh -s workflow"
fi

[ "$VISIBILITY" = "public" ] || [ "$VISIBILITY" = "private" ] || die "VISIBILITY must be public or private."

if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  die "$OWNER/$REPO already exists. Pick another REPO name, or delete it first: gh repo delete $OWNER/$REPO"
fi

CODEOWNER="${REVIEWER:-$OWNER}"
if [ -z "$REVIEWER" ]; then
  warn "No REVIEWER given: CODEOWNERS will point at you, and you cannot approve your own PRs."
  warn "You can still demo the checks and the blocked-merge state, but not a completed merge."
fi

# ------------------------------------------------------------------ 1. repo + push
say "Creating $VISIBILITY repository $OWNER/$REPO"
gh repo create "$OWNER/$REPO" "--$VISIBILITY" --description "CI/CD process demo (stand-in code, no real data)" >/dev/null

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$HERE/repo/." "$WORK/"

# portable in-place replace (BSD and GNU sed differ on -i)
sed "s/__CODEOWNER__/${CODEOWNER}/g" "$WORK/.github/CODEOWNERS" > "$WORK/.github/CODEOWNERS.tmp"
mv "$WORK/.github/CODEOWNERS.tmp" "$WORK/.github/CODEOWNERS"

say "Pushing stand-in code, workflows and configs to main"
git -C "$WORK" init -q -b main
git -C "$WORK" config user.name "$OWNER"
git -C "$WORK" config user.email "${OWNER}@users.noreply.github.com"
git -C "$WORK" add -A
git -C "$WORK" commit -q -m "Initial demo content"
git -C "$WORK" remote add origin "https://github.com/${OWNER}/${REPO}.git"
GIT_PUSH=(git -C "$WORK" -c credential.helper= -c "credential.helper=!gh auth git-credential")
"${GIT_PUSH[@]}" push -q -u origin main

# ------------------------------------------------------------------ 2. qa branch
say "Creating the qa branch from main"
git -C "$WORK" branch qa main
"${GIT_PUSH[@]}" push -q origin qa

# ------------------------------------------------------------------ 3. reviewer + environments
REVIEWER_ID=""
if [ -n "$REVIEWER" ]; then
  say "Inviting $REVIEWER as a collaborator"
  gh api -X PUT "repos/${OWNER}/${REPO}/collaborators/${REVIEWER}" -f permission=push >/dev/null

  has_access() {
    local perm
    perm=$(gh api "repos/${OWNER}/${REPO}/collaborators/${REVIEWER}/permission" --jq .permission 2>/dev/null || true)
    [ "$perm" = "write" ] || [ "$perm" = "admin" ] || [ "$perm" = "maintain" ]
  }
  until has_access; do
    echo "   $REVIEWER has not accepted yet. They need to accept at:"
    echo "   https://github.com/${OWNER}/${REPO}/invitations"
    if [ ! -t 0 ]; then
      warn "Not an interactive terminal, so not waiting. CODEOWNERS and the environment reviewer may not work until $REVIEWER accepts."
      break
    fi
    read -r -p "   Press Enter to re-check (Ctrl+C to stop)... " _
  done
  REVIEWER_ID=$(gh api "users/${REVIEWER}" --jq .id)
fi

say "Creating GitHub Environments"
put_env() { # name [json-body]
  local name="$1" body="${2:-{\}}"
  printf '%s' "$body" | gh api -X PUT "repos/${OWNER}/${REPO}/environments/${name}" --input - >/dev/null
}

put_env dev
put_env qa
# an environment that exists but has NO reviewers: demonstrates the Prod safety check
put_env demo-noreviewers
# demo-missing-env is deliberately NOT created: demonstrates the "environment doesn't exist" check

PROTECTED_REVIEWER_ID="${REVIEWER_ID:-$(gh api "users/${OWNER}" --jq .id)}"
PROTECTED_BODY=$(jq -n --argjson id "$PROTECTED_REVIEWER_ID" '{reviewers:[{type:"User",id:$id}]}')
if ! put_env demo-tenant "$PROTECTED_BODY"; then
  warn "Could not set required reviewers on 'demo-tenant' (private repos on a free plan can't). Creating it without; the Prod approval demo will not pause."
  put_env demo-tenant
fi

# ------------------------------------------------------------------ 4. rulesets, LAST
say "Applying branch rulesets (the exact script the client will run)"
if ! OWNER="$OWNER" REPO="$REPO" bash "$HERE/scripts/configure_branch_protection.sh"; then
  warn "Rulesets could not be applied. Private repos need a paid plan; make the repo public or upgrade."
  warn "The workflow checks and release/deploy demos still work without them."
fi

cat << EOF

Done. Demo repository: https://github.com/${OWNER}/${REPO}

Next steps
  1. Open https://github.com/${OWNER}/${REPO}/actions and check the workflows are listed.
  2. Follow DEMO_SCRIPT.md (same folder as this script).
  3. To remove it afterwards:  gh repo delete ${OWNER}/${REPO} --yes   (needs: gh auth refresh -s delete_repo)
EOF
