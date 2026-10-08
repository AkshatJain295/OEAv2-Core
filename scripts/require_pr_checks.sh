#!/usr/bin/env bash
# OPTIONAL. Makes the PR Checks workflow BLOCKING: adds "conventions" and
# "tenant-configs" as required status checks to the three rulesets created by
# configure_branch_protection.sh. Until you run this, a failing check shows a red
# X but the merge button still works.
#
# Run it AFTER the PR Checks workflow has run at least once (so GitHub knows the
# check names), and after configure_branch_protection.sh.
#
# Usage:  OWNER=your-username REPO=oeav2-core-demo ./require_pr_checks.sh
#
# Safe to re-run: it removes any existing required-checks rule before adding it.

set -euo pipefail

OWNER="${OWNER:?Set OWNER=your-username}"
REPO="${REPO:?Set REPO=your-repo}"

for NAME in protect-main protect-qa protect-release-branches; do
  ID=$(gh api "repos/${OWNER}/${REPO}/rulesets" --jq ".[] | select(.name==\"${NAME}\") | .id")
  if [ -z "$ID" ]; then
    echo "Ruleset '${NAME}' not found. Run configure_branch_protection.sh first." >&2
    exit 1
  fi

  echo "Adding required checks to '${NAME}' (id ${ID})..."
  gh api "repos/${OWNER}/${REPO}/rulesets/${ID}" \
    | jq '{
        name, target, enforcement, conditions,
        bypass_actors: (.bypass_actors // []),
        rules: ((.rules | map(select(.type != "required_status_checks"))) + [{
          type: "required_status_checks",
          parameters: {
            strict_required_status_checks_policy: false,
            required_status_checks: [
              { context: "conventions" },
              { context: "tenant-configs" }
            ]
          }
        }])
      }' \
    | gh api -X PUT "repos/${OWNER}/${REPO}/rulesets/${ID}" --input - >/dev/null
done

echo "Done. PRs into main, qa and release/* now also need 'conventions' and 'tenant-configs' to pass."
