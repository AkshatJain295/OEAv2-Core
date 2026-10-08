# CI/CD demo kit

Rehearse the whole OEAv2-Core process (branch rules, PR checks, release tags, deploy approvals, cleanup) in a **personal GitHub repo**, with no Fabric and no company data. Use it to demo to the team before anything is applied to the real repo.

## What's in the box

| Path | Purpose |
|---|---|
| `setup_demo_repo.sh` | One command that creates and fully wires up the demo repo |
| `repo/` | The stand-in repo: tiny `oea-v2` package, sample `cloud/`, `dags/`, `docs/`, fake-GUID configs, and the **real** workflows and scripts |
| `scripts/configure_branch_protection.sh` | The exact script the client will run |
| `scripts/require_pr_checks.sh` | Optional: turns the PR checks from advisory into blocking |
| `DEMO_SCRIPT.md` | The run-of-show: every scenario, what to do, what you should see |

## Before you start

You need:

- **A GitHub account**, plus **a second account** that will act as reviewer (a teammate who agrees to be a collaborator, or a second personal account). Without it you can't approve your own PRs, so you can show the blocked state but not a completed merge.
- **`gh`, `git` and `jq`** installed. Then:
  ```bash
  gh auth login
  gh auth refresh -s workflow      # needed to push workflow files
  ```
- **A public repo, or a paid GitHub plan.** Branch rulesets and environment reviewers don't work on private repos on the free plan. The kit contains only stand-in content, so public is fine.

## Set it up

```bash
OWNER=your-username REPO=oeav2-core-demo REVIEWER=second-account bash setup_demo_repo.sh
```

It pushes everything to `main`, creates `qa`, invites the reviewer (and waits for them to accept), creates the GitHub Environments, and applies the branch rulesets last. If the reviewer hasn't accepted the invitation yet, the script pauses and tells you where they accept it.

Then open `DEMO_SCRIPT.md`.

## What this does and doesn't prove

**Proves, for real, on GitHub:** branch protection, CODEOWNERS review (with a username instead of a team), PR title/branch/flow checks, config validation, release publishing and tag rules, "Latest" and pre-release handling, deploy validation, the Prod approval gate, and cleanup.

**Doesn't touch:** Fabric, the Entra token request, the notebook, or Key Vault. Deploy workflows run in **dry-run mode**: every check and approval happens, and the exact request body is built and printed, but nothing is sent. That leg is first exercised in the real repo with a `.dev` release.

**Org-only things you can't rehearse here:** the `core-team` team handle, and the real service-principal secrets.

## Rules for the demo repo

- Never add the real service-principal secrets, the real Key Vault PAT, or real company code to it.
- Always run deploys with **dry run** ticked.
- When you're finished: `gh repo delete OWNER/REPO --yes` (needs `gh auth refresh -s delete_repo`).
