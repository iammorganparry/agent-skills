# CI checks → local reproduction & failure triage

Map each failing CI check to the command that reproduces it locally, then
decide whether the failure is **caused by this PR** or **unrelated** (pre-existing,
flaky, or infra). Always pull the real failure first: `gh run view <id> --log-failed`.

## Building the check → command map

Every repo is different, so derive the map instead of assuming one:

```bash
# which workflow + jobs produced a failing run
gh run view <run-id> --json workflowName,jobs --jq '{workflowName, jobs:[.jobs[]|{name,conclusion}]}'
ls .github/workflows/
```

Open the workflow file and read the failing job's `run:` steps. That command,
with the same working directory, env and matrix values, is the local
reproduction. Carry over:

- **Setup steps** — tool versions (`node-version`, `python-version`), the install
  command (frozen lockfile?), and any codegen/build step that runs before tests.
- **`services:` / docker-compose** — DB, Redis, queues, emulators. Start the
  repo's local equivalent first (check `package.json` scripts, `Makefile`,
  `docker-compose.yml`, the README). Without them the failure is an
  environment artifact, not a code bug.
- **Env vars** — anything the job sets that changes behaviour (`CI=true`,
  feature flags, test DB URLs). Secrets you can't reproduce hint the job may be
  infra, not code.
- **Matrix** — reproduce the specific failing combination (OS / version).

Write the resulting table down for the rest of the session, e.g.:

| CI check (workflow / job) | Reproduce locally | Needs |
|---------------------------|-------------------|-------|
| `CI / lint`               | `pnpm lint`       | —     |
| `CI / test (node 22)`     | `pnpm test`       | Postgres via `docker compose up -d db` |

## Related vs unrelated — decide BEFORE fixing

For every red check, classify it. **Flag unrelated failures to the user explicitly;
do not silently "fix" them by editing unrelated code or rerunning until green.**

A failure is **caused by this PR** when:
- The failing file/symbol is in this PR's diff (`git diff origin/<base>...HEAD --name-only`).
- The error references a type, import, or signature you changed.
- It reproduces locally on this branch but **passes on `origin/<base>`** (the decisive test).

A failure is likely **unrelated** when:
- It also fails on `origin/<base>` → pre-existing. Check recent base-branch runs
  too: `gh run list --branch <base> --workflow <file> --limit 5`.
- It's flaky: passes on rerun with no code change, or is timing/network/timeout-based.
  E2E/browser suites and anything calling an LLM or external API are the usual
  suspects. Rerun once (`gh run rerun <id> --failed`) to confirm before concluding.
- It's infra: runner setup, deploy previews, dependency/security scanners,
  secrets missing on fork PRs, `ECONNREFUSED`, package-registry 5xx, rate limits.

### The decisive check
```bash
git fetch origin <base>
git worktree add ../base-check origin/<base>
(cd ../base-check && <install> && <reproduce command>)   # fails on base too?
git worktree remove ../base-check
```
Fails on base → unrelated/pre-existing. Passes on base, fails on branch → yours, fix it.

## Reruns
```bash
gh run rerun <run-id> --failed     # rerun only failed jobs (confirms flakiness)
gh run watch <run-id>              # block until a run finishes
gh pr checks <PR> --watch          # watch all checks for the PR
```
Rerunning is for **confirming flakiness or clearing a known-transient infra blip** —
never a substitute for fixing a real regression. Cap reruns at 2 for any single check;
if it fails a third time it is not flaky.

## What "EVERY check passes" means
Green is required on every check that gates merge. `gh pr checks <PR> --required`
lists the ones branch protection requires; if none are configured, treat every
code check (lint, types, tests, build) as gating. Deploy-preview and third-party
scanner failures are infra: green is ideal, but a failure there is flagged to
the user, not code-fixed.
