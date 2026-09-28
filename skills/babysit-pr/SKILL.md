---
name: babysit-pr
description: >-
  Drive a pull request all the way to green and approved. Use when the user
  asks to "babysit", "shepherd", "watch", "nurse", "get this PR merged/green",
  or to handle PR feedback + CI together. Works in any GitHub repo: discovers the
  repo's own CI jobs, verify commands and conventions, resolves review feedback
  from humans and review bots (Devin, CodeRabbit, Copilot, …), respects any QA
  bot verdict, and makes EVERY CI check pass — reproducing each failure locally,
  separating PR-caused failures from unrelated/flaky/infra ones (which it flags
  before touching), then fixing the real ones and re-running until clean.
  Defaults to the current branch's PR; accepts a PR number.
---

# Babysit a PR

Take ownership of a pull request and shepherd it to "all checks green + all
feedback resolved", running autonomously and only surfacing to the user what
genuinely needs a human decision.

Requires `gh` (authenticated) and `jq`.

## Operating principles

- **Fix root causes, never the scoreboard.** Make code/tests correct. Never edit
  a test to pass, weaken an assertion, edit a QA checklist to dodge a step, or
  rerun-until-green to mask a real failure.
- **Triage before fixing.** For every red check, decide *PR-caused* vs
  *unrelated* (pre-existing / flaky / infra) BEFORE editing anything, and flag
  the unrelated ones to the user instead of silently fixing or hiding them.
- **Question feedback, then act.** Reviewer suggestions aren't automatically
  right. Address / Decline / Clarify each, concisely, with reasons.
- **Respect repo law.** Before the first edit, read whatever the repo documents:
  `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, branching or release docs, PR
  templates. Follow its commit style, branch rules and code conventions. Never
  push to the default branch or hand-edit release-managed version fields.
- **Report honestly.** If something is still red, say so with the output. Don't
  claim green you haven't verified.

## Step 0 — learn the repo (once per PR)

1. **Base branch:** `gh pr view <PR> --json baseRefName --jq .baseRefName`
   (called `<base>` below).
2. **Package manager / task runner:** infer from lockfiles and config —
   `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `bun.lock(b)`,
   `Cargo.toml`, `go.mod`, `pyproject.toml`/`uv.lock`, `Makefile`, `justfile`.
3. **Verify gate:** the commands the repo expects before a push — look in the
   agent docs above, then `package.json` scripts (`typecheck`, `lint`, `test`),
   then the CI workflow `run:` steps.
4. **CI map:** build a check → command table from `.github/workflows/*.yml`
   (see `references/ci-checks.md`). Note which jobs need services (DB, Redis,
   emulators) and how the repo starts them locally.

## The loop

Repeat until the exit criteria are met. One pass:

### 1. Snapshot the PR
```bash
bash "<this skill's dir>/scripts/pr-status.sh" [PR_NUMBER]
```
The single source of truth each pass: CI checks (with run IDs for failed logs),
inline review threads grouped by author, bot verdict comments, and reviews.
Defaults to the current branch's PR; pass a number to target another.

If there's no PR yet, stop and tell the user (offer `gh pr create`). If checks are
still `pending`, note what you're waiting on — you may address feedback that's
already in while CI runs.

### 2. Triage everything into a worklist
One list across all sources, each item tagged **PR-caused** or **unrelated**:

- **Failing CI checks** → classify per `references/ci-checks.md`. The decisive
  test: does it also fail on `origin/<base>`? Reproduce locally with the mapped
  command. Flag unrelated/flaky/infra failures to the user now.
- **Review threads (humans and bots)** → triage per `references/feedback.md`
  (Address / Decline / Clarify).
- **QA / preview-test bot verdict**, if the repo has one → any failing step is a
  blocker; fix the behaviour, per `references/feedback.md`.
- **Human `CHANGES_REQUESTED`** → gates merge; must be addressed and re-reviewed.

Present the worklist when there are non-obvious calls (unrelated failures,
declines, scope questions). Obvious fixes: just do them.

### 3. Fix the PR-caused items
- Minimal, root-cause edits that follow repo conventions.
- Reproduce locally and confirm the fix.
- Run the repo's verify gate (Step 0.3) plus the specific tests for what you
  touched before pushing.
- Batch related changes; match the repo's commit message style.

### 4. Push and respond
- `git push` once per pass (updates the PR and re-triggers CI / previews).
- Reply `✅ Addressed in <sha>` on addressed threads and **resolve** them
  (GraphQL snippet in `references/feedback.md`). Leave Declined/Clarify threads
  open with your reasoning.

### 5. Wait, then re-snapshot
```bash
gh pr checks <PR> --watch          # block until checks settle
```
Then go back to step 1. Bot verdicts tied to preview deployments only refresh
after the new preview is live, so allow time for them.

## Exit criteria — all of:
1. Every check that gates merge is green (see "What EVERY check passes means"
   in `references/ci-checks.md`). Non-gating deploy/security/infra checks are
   green or explicitly flagged.
2. Any QA bot verdict is **pass**.
3. Every review thread is resolved or has a posted Decline/Clarify reply; no open
   human `CHANGES_REQUESTED`.
4. No unresolved unrelated failures — each is fixed or flagged to the user with
   evidence and an explicit "not caused by this PR" note.

## Final report
A concise status: what was fixed (with SHAs), what feedback was
addressed/declined/clarified, the state of every check, any QA verdict, and
anything flagged as unrelated that the user must decide on. If not fully green,
say exactly what's blocking and why.

## Long-running waits
CI can take many minutes per pass. If asked to run unattended, drive the loop
with `/loop` or `gh pr checks <PR> --watch` rather than busy-polling.

## References
- `references/ci-checks.md` — mapping checks to local commands, related-vs-unrelated heuristics, reruns.
- `references/feedback.md` — human / bot / QA triage, reply & thread-resolve mechanics.
- `scripts/pr-status.sh` — consolidated PR dashboard (read-only).
