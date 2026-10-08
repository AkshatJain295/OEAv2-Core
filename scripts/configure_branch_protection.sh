#!/usr/bin/env bash
set -euo pipefail

OWNER="${OWNER:?Set OWNER=EdGraph-OSS}"
REPO="${REPO:?Set REPO=OEAv2-Core}"

delete_if_exists() {
  local name="$1"
  local id
  id=$(gh api "repos/${OWNER}/${REPO}/rulesets" --jq ".[] | select(.name==\"${name}\") | .id" || true)
  if [ -n "${id}" ]; then
    echo "Deleting existing ruleset '${name}' (id ${id}) before recreating..."
    gh api -X DELETE "repos/${OWNER}/${REPO}/rulesets/${id}"
  fi
}

create_ruleset() {
  local name="$1"
  local pattern="$2"
  echo "Creating ruleset '${name}' for pattern '${pattern}'..."
  gh api -X POST "repos/${OWNER}/${REPO}/rulesets" --input - <<JSON
{
  "name": "${name}",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/${pattern}"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    }
  ]
}
JSON
}

delete_if_exists "protect-main"
create_ruleset "protect-main" "main"

delete_if_exists "protect-qa"
create_ruleset "protect-qa" "qa"

delete_if_exists "protect-release-branches"
create_ruleset "protect-release-branches" "release/*"

echo "Done. main, qa and release/* now require: a CODEOWNERS-approved PR,"
echo "no force pushes, and no deletions."
