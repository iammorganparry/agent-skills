---
name: babysit-pr
description: >-
  Drive a pull request all the way to green and approved. Use when the user
  asks to "babysit", "shepherd", "watch", "nurse", "get this PR merged/green",
  or to handle PR feedback + CI together. Resolves Devin and human review
  feedback, respects the browser QA agent's verdict, and makes EVERY CI step
  pass — reproducing each failure locally, distinguishing PR-caused failures
  from unrelated/flaky/infra ones (which it flags before touching), then fixing
  the real ones and re-running until clean. Defaults to the current branch's PR;
  accepts a PR number. (CodeRabbit feedback is delegated to the pr-feedback skill.)
---

# Babysit a PR

Take ownership of a pull request and shepherd it to "all checks green + all
feedback resolved + QA passing", running autonomously and only surfacing to the
user what genuinely needs a human decision.

## Operating principles

- **Fix root causes, never the scoreboard.** Make code/tests correct. Never edit
  a test to pass, weaken an assertion, edit the QA checklist to dodge a step, or
  rerun-until-green to mask a real failure.
- **Triage before fixing.** For every red check, decide *PR-caused* vs
  *unrelated* (pre-existing / flaky / infra) BEFORE editing anything, and flag
  the unrelated ones to the user instead of silently fixing or hiding them.
- **Question feedback, then act.** Reviewer suggestions aren't automatically
  right. Address / Decline / Clarify each, concisely, with reasons.
- **Respect repo law.** Follow `CLAUDE.md` (Effect-TS, no `as` casts, React rules)
  and `docs/BRANCHING_STRATEGY.md`. Never hand-edit `version` fields or push to
  `main`/`prod`. Conventional-Commit titles.
- **Report honestly.** If something is still red, say so with the output. Don't
  claim green you haven't verified.

## The loop

Repeat until the exit criteria are met. One pass:

### 1. Snapshot the PR
```bash
~/.claude/skills/babysit-pr/scripts/pr-status.sh [PR_NUMBER]
```
This is the single source of truth each pass: CI checks (with run IDs for failed
logs), inline review threads grouped by author, the QA verdict, and reviews.
Defaults to the current branch's PR; pass a number to target another.

If there's no PR yet, stop and tell the user (offer `gh pr create`). If checks are
still `pending`, note what you're waiting on — you may proceed to address feedback
that's already in while CI runs.

### 2. Triage everything into a worklist
Build one list across all sources, each item tagged **PR-caused** or **unrelated**:

- **Failing CI checks** → classify with `references/ci-checks.md`. The decisive
  test: does it also fail on `origin/main`? Reproduce locally with the mapped
  command. Flag unrelated/flaky/infra failures to the user now.
- **Devin & human review threads** → triage per `references/feedback.md`
  (Address / Decline / Clarify).
- **QA agent verdict** → any `fail` step or `reproduced_bug: true` is a blocker;
  fix the behaviour, per `references/feedback.md`.
- **CodeRabbit comments present?** → invoke the **`pr-feedback`** skill for those;
  don't re-implement that flow here.
- **Human `CHANGES_REQUESTED`** → gates merge; must be addressed and re-reviewed.

Present the worklist to the user when there are non-obvious calls (unrelated
failures, declines, or scope questions). Obvious fixes: just do them.

### 3. Fix the PR-caused items
- Make minimal, root-cause edits that follow repo conventions.
- Reproduce locally and confirm the fix (`references/ci-checks.md` for commands).
- Run the local verify gate before pushing: at minimum `yarn typecheck && yarn lint`,
  plus the specific test command(s) for whatever you touched.
- Batch related changes; write Conventional-Commit messages.

### 4. Push and respond
- `git push` once per pass (updates the PR, re-triggers CI + a new preview → QA).
- Post `✅ Addressed in <sha>` replies on addressed threads and **resolve** them
  (GraphQL snippet in `references/feedback.md`). Leave Declined/Clarify threads
  open with your reasoning.

### 5. Wait, then re-snapshot
CI and the QA agent re-run on the new commit/preview. Wait for them:
```bash
gh pr checks <PR> --watch          # block until checks settle
```
Then go back to step 1. The QA verdict only refreshes after the new Vercel preview
deploys, so allow time for it.

## Exit criteria — all of:
1. Every gating CI check is green (Lint, Type Check, Unit, Integration, Inngest,
   Evals, Playwright). Deploy/Socket/infra checks green or explicitly flagged.
2. The `QA Verify / qa` verdict is **pass** with no `reproduced_bug`.
3. Every Devin/human review thread is resolved or has a posted Decline/Clarify
   reasoning; no open human `CHANGES_REQUESTED`.
4. No unresolved unrelated failures — each is either fixed or flagged to the user
   with evidence and an explicit "not caused by this PR" note.

## Final report
End with a concise status: what was fixed (with SHAs), what feedback was
addressed/declined/clarified, the current state of every check, the QA verdict,
and anything flagged as unrelated that the user must decide on. If not fully
green, say exactly what's blocking and why.

## Long-running waits
CI + QA can take many minutes per pass. If asked to run unattended, drive the loop
with the `/loop` skill or `gh pr checks <PR> --watch` rather than busy-polling.

## References
- `references/ci-checks.md` — CI check → local command, related-vs-unrelated heuristics, reruns.
- `references/feedback.md` — Devin / QA / human triage, reply & thread-resolve mechanics.
- `scripts/pr-status.sh` — consolidated PR dashboard (read-only).
