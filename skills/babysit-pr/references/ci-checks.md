# CI checks → local reproduction & failure triage

Map each failing CI check to the command that reproduces it locally, then
decide whether the failure is **caused by this PR** or **unrelated** (pre-existing,
flaky, or infra). Always pull the real failure first: `gh run view <id> --log-failed`.

## Check → local command

The canonical commands live in `.github/workflows/tests.yml`. Current mapping:

| CI check (workflow / job)        | Reproduce locally                                   |
|----------------------------------|-----------------------------------------------------|
| `Run Tests 🧪 / Lint`            | `yarn lint`                                          |
| `Run Tests 🧪 / TypeScript Type Check` | `yarn typecheck`                              |
| `Run Tests 🧪 / Unit Tests`      | `yarn test:unit`                                     |
| `Run Tests 🧪 / Integration Tests` | `yarn workspace @trigify/api test`                |
| `Run Tests 🧪 / Inngest Tests`   | `yarn workspace @trigify/backend test:int` + `yarn workspace @trigify/inngest test:int` + `yarn workspace @trigify/app test:int` |
| `Run Tests 🧪 / LLM Evaluation Tests` | `yarn workspace @trigify/evals eval`           |
| Playwright (`playwright.yml`)    | `yarn playwright:run` (needs `yarn e2e:infra` first) |
| `QA Verify / qa`                 | See `references/feedback.md` (browser QA agent, not a unit test) |

Integration / Inngest / Playwright need live infra. Start it with
`yarn db:start` (Supabase + Redis) or `yarn e2e:infra` (Playwright Postgres/Redis/Inngest)
before reproducing, or the failure is an environment artifact, not a code bug.

If a job name isn't in the table, read its `run:` step in the workflow file that
owns it (`gh run view <id> --json jobs` shows the workflow path) and run that command.

## Related vs unrelated — decide BEFORE fixing

For every red check, classify it. **Flag unrelated failures to the user explicitly;
do not silently "fix" them by editing unrelated code or rerunning until green.**

A failure is **caused by this PR** when:
- The failing file/symbol is in this PR's diff (`git diff origin/main...HEAD --name-only`).
- The error references a type, import, or signature you changed.
- It reproduces locally on this branch but **passes on `origin/main`** (the decisive test).

A failure is likely **unrelated** when:
- It also fails on `origin/main` (check out main, run the same command). → pre-existing.
- It's flaky: passes on rerun with no code change, or is timing/network/timeout-based.
  The **LLM Evaluation Tests** and **Playwright E2E** are the usual flaky suspects —
  model nondeterminism and browser timing. Rerun once (`gh run rerun <id> --failed`)
  to confirm flakiness before drawing conclusions.
- It's infra: runner setup, Vercel/Railway deploy, Socket Security, secret/credential
  errors, `ECONNREFUSED`, package-registry 5xx. Not a code defect in this PR.

### The decisive check
```bash
git stash --include-untracked            # if you have local edits
git checkout origin/main -- .            # or: git worktree add /tmp/main origin/main
<reproduce command>                      # does it fail on main too?
```
Fails on main → unrelated/pre-existing. Passes on main, fails on branch → yours, fix it.

## Reruns
```bash
gh run rerun <run-id> --failed     # rerun only failed jobs (confirms flakiness)
gh run watch <run-id>              # block until a run finishes
gh pr checks <PR> --watch          # watch all checks for the PR
```
Rerunning is for **confirming flakiness or clearing a known-transient infra blip** —
never a substitute for fixing a real regression. Cap reruns at 2 for any single check;
if it fails a third time it is not flaky.

## What "EVERY step passes" means
Green required on all `bucket: fail`/`pending` checks that gate merge: Lint, Type Check,
Unit, Integration, Inngest, Evals, Playwright. Deploy/preview checks (Vercel, Railway)
and Socket Security are infra — green is ideal but a failure there is flagged to the user,
not code-fixed. The QA Verify check must end green with no reproduced bug (see feedback.md).
