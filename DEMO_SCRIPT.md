# Demo run-of-show

Every scenario lists what to do and what you should see. Scenarios marked ★ make a good **10-minute version**; the full run is about 30 minutes.

The state builds up as you go (merged PRs, releases), so run the acts in order. To start over: delete the repo and re-run `setup_demo_repo.sh`.

## Before the demo

- [ ] Reviewer accepted the invitation (`https://github.com/OWNER/REPO/invitations`)
- [ ] `setup_demo_repo.sh` finished without warnings you don't understand
- [ ] Actions tab lists: PR Checks, OEA Release Publisher, Deploy to Dev / QA / Prod (per tenant), Cleanup dev releases
- [ ] Reviewer is logged in on a second browser/profile, ready to approve
- [ ] Terminal ready:
  ```bash
  export OWNER=your-username REPO=oeav2-core-demo
  gh auth setup-git                      # lets git push using your gh login
  git clone https://github.com/$OWNER/$REPO && cd $REPO
  ```
- [ ] **Do a full rehearsal first.** It takes 30 minutes and it's the only way to find surprises before the team does.

**Running a workflow:** Actions → pick the workflow → *Run workflow* → choose the branch under **Use workflow from** → fill the inputs. CLI equivalent: `gh workflow run <file> --ref <branch> -f key=value`.

---

## Act 1: Guardrails on branches and PRs

| # | Do | You should see |
|---|---|---|
| 1.1 ★ | Push straight to `main`:<br>`echo "# oops" >> README.md && git commit -qam "direct push" && git push origin main` | **Rejected**: "Repository rule violations found... Changes must be made through a pull request." |
| 1.2 ★ | A PR that skips QA (feature straight to `main`):<br>`git checkout -b feature/demo/skip-qa main && echo x >> docs/index.md && git commit -qam "skip" && git push -u origin HEAD`<br>`gh pr create --base main --title "[feature] Skip QA" --body demo` | **PR Checks / conventions fails**: "PRs into 'main' must come from 'qa' (promotion) or a hotfix/ branch..." |
| 1.3 | A PR with no title prefix:<br>`git checkout -b feature/demo/no-prefix main && echo x >> docs/index.md && git commit -qam x && git push -u origin HEAD`<br>`gh pr create --base qa --title "Add a metric" --body demo` | **Fails**: "PR title must start with [feature], [bugfix], [hotfix], [doc] or [chore]..." |
| 1.4 | `gh pr edit --title "[bugfix] Add a metric"` (the branch is `feature/...`) | **Fails**: "Branch '...' is a feature branch but the title says [bugfix]." |
| 1.5 ★ | The good path: `gh pr edit --title "[feature] Add a metric"` | **conventions** and **tenant-configs** go green. Reviewer is auto-requested as code owner. Merge button is **blocked**: approval + code owner review required. |
| 1.6 ★ | Reviewer approves, then merge (squash is fine): `gh pr merge --squash` | Merges into `qa`. |
| 1.7 ★ | Promote `qa` into `main`:<br>`gh pr create --base main --head qa --title "[feature] Promote add-a-metric" --body demo`<br>Reviewer approves. Merge with a **merge commit**, not squash: `gh pr merge --merge` | Checks green. Merges into `main`. |

> Checks show red but the merge button may still work until you run Act 6. That is the difference between *advisory* and *blocking*; Act 6 shows how to switch it.

## Act 2: Config safety

Do **each row on its own branch**: `git checkout -b chore/demo/cfg-N main`, make the edit, `git commit -qam test && git push -u origin HEAD`, then `gh pr create --base qa --title "[chore] Config test N" --body demo`. Close each PR without merging.

| # | Do | You should see (**tenant-configs** fails) |
|---|---|---|
| 2.1 ★ | Typo a module key:<br>`jq '.modules \|= with_entries(if .key=="deploy_notebooks" then .key="deploy_notebook" else . end)' configs/demo-tenant.json > t && mv t configs/demo-tenant.json` | "unknown module key(s): ['deploy_notebook']" |
| 2.2 ★ | Leave a placeholder:<br>`jq '.workspace="REPLACE-WITH-REAL-GUID"' configs/demo-tenant.json > t && mv t configs/demo-tenant.json` | "'workspace' is not a valid GUID... (placeholder left in?)" |
| 2.3 | Point two tenants at one workspace:<br>`jq --arg w "$(jq -r .workspace configs/qa.json)" '.workspace=$w' configs/demo-tenant.json > t && mv t configs/demo-tenant.json` | "Workspace ... is used by more than one config" |
| 2.4 | Paste a secret into the config:<br>`jq '.credentials={"vault_name":"kv","tenant_id_secret":"a","client_id_secret":"b","client_secret_secret":"c","client_secret":"hunter2"}' configs/demo-tenant.json > t && mv t configs/demo-tenant.json` | "'credentials' has unexpected key(s)... must only hold Key Vault secret NAMES, never secret values" |

Close these PRs without merging.

## Act 3: Releases and tags

Run **OEA Release Publisher** each time.

| # | Branch / tag | You should see |
|---|---|---|
| 3.1 ★ | `main` / `v2026.09.1` | **Rejected** before anything is created: "not a valid dev/test tag for branch 'main'..." |
| 3.2 ★ | `qa` / `v2026.09.1.dev1` | Succeeds. On the Releases page: marked **Pre-release**, **not** "Latest"; assets: `oea_v2-2026.9.1.dev1-py3-none-any.whl`, `notebooks.zip`, `dags.zip`, `docs.zip`. |
| 3.3 ★ | Cut the release branch: `git fetch -q && git push origin origin/main:refs/heads/release/2026-09` | **Finding to note:** if the ruleset rejects creating the branch, that's a real issue for the real process. See "Findings" below. |
| 3.4 ★ | `release/2026-09` / `v2026.10.1` | Rejected: "does not match branch 'release/2026-09'. Expected a tag starting with v2026.09." |
| 3.5 | `release/2026-09` / `v2026.09.1.dev2` | Rejected: "not a valid release tag for a release/* branch... no suffix." |
| 3.6 ★ | `release/2026-09` / `v2026.09.1` | Succeeds. Marked **Latest**, not pre-release. |
| 3.7 | Same again: `release/2026-09` / `v2026.09.1` | Rejected: "Tag v2026.09.1 already exists!" |
| 3.8 | Hotfix: `git fetch -q && git checkout -b hotfix/demo/fix-x origin/release/2026-09`, edit, push, PR **into `release/2026-09`** titled `[hotfix] Fix x`, approve, merge. Then publish `release/2026-09` / `v2026.09.2` | New tag; **Latest moves to v2026.09.2**. |
| 3.9 | Older branch: `git push origin origin/main:refs/heads/release/2026-08`, publish `v2026.08.1` | Published but **not** "Latest": an old hotfix never steals the badge. |

## Act 4: Deploys (dry run, nothing reaches Fabric)

Always tick **dry run**. Needs the releases from Act 3.

| # | Workflow and inputs | You should see |
|---|---|---|
| 4.1 ★ | **Deploy to QA**, from `main`, tag `v2026.09.1.dev1`, dry run ✓ | Green. Job summary previews target, release and **enabled modules**. Token / trigger / poll steps are **skipped**. Log prints the exact request body. Final step: "DRY RUN... No call was made to Entra ID or Fabric." |
| 4.2 ★ | **Deploy to Prod**, tenant `demo-tenant`, tag `v2026.09.1.dev1` | **Rejected at validation**: "is a dev release... never Prod." No approval prompt: it failed *before* asking anyone. |
| 4.3 | Prod, `demo-tenant`, tag `v2026.09.99` | Rejected: "release 'v2026.09.99' was not found... Run OEA Release Publisher first." |
| 4.4 | Prod, tenant `acme`, tag `v2026.09.1` | Rejected: "configs/acme.json does not exist on main." |
| 4.5 ★ | Prod, **Use workflow from: `qa`**, tenant `demo-tenant`, tag `v2026.09.1` | Fails at the **guard**: "Prod deploys must be dispatched from main." |
| 4.6 ★ | Prod, from `main`, tenant `demo-tenant`, tag `v2026.09.2` (or `v2026.09.1` if you skipped 3.8), dry run ✓ | Validation passes, then the run **pauses: "Waiting for review"**. Reviewer approves in the Actions UI; run continues to "Dry run complete". |
| 4.7 ★ | Prod, tenant `demo-noreviewers`, tag `v2026.09.1` | Rejected: "has no required reviewers. Refusing to deploy to Prod without an approval gate." |
| 4.8 | Prod, tenant `demo-missing-env`, tag `v2026.09.1` | Rejected: "GitHub Environment 'demo-missing-env' does not exist. Running would auto-create it with no approval gate." |
| 4.9 | **Deploy to QA**, tag `v2026.09.1.dev1`, dry run **unticked** | Fails fast at the token step: "secret SERVICE_PRINCIPAL_TENANT_ID is empty..." This is where a real deploy would call Fabric once secrets exist. |

## Act 5: Cleanup

| # | Do | You should see |
|---|---|---|
| 5.1 ★ | Run **Cleanup dev releases** with defaults (14 days, dry run ✓) | "Found 0 expired dev release(s)." Nothing is old enough yet, and no production tag could ever match. |
| 5.2 | *Next day:* run it with retention `1`, dry run unticked | Deletes `v2026.09.1.dev1` **and its git tag**. `v2026.09.1`, `v2026.09.2`, `v2026.08.1` untouched. |

## Act 6 (optional): Make the checks blocking

Run it from the **demo-kit folder** (the script isn't part of the demo repo):

```bash
OWNER=$OWNER REPO=$REPO bash scripts/require_pr_checks.sh
```

Re-open one of the failing PRs from Act 1 or 2: the merge button is now blocked until the checks pass. This is the same step you would take in the real repo once the rulesets exist.

---

## Findings to bring back from the demo

Three things I could not verify without a real GitHub repo. Note what you see:

1. **Can a release branch be created under the `release/*` ruleset (3.3)?** If the push is rejected, whoever cuts releases needs a bypass or a different way to create the branch, and the client's ruleset script needs adjusting *before* they run it.
2. **Does the Prod environment check work with the default token (4.7 / 4.8)?** If you see a *warning* ("Could not verify protection rules") instead of an error, the token lacks permission to read environments. Note: in that case `demo-missing-env` gets silently auto-created; delete it under Settings → Environments.
3. **Do the required-check names match (Act 6)?** If a PR sits forever on "Expected: waiting for status to be reported", the names `conventions` / `tenant-configs` in `require_pr_checks.sh` need adjusting.
