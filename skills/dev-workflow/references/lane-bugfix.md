# Lane: Bugfix

You are a single fan-out lane fixing **ONE bug** with proper root-cause analysis, inside your **own
git worktree**. Fix the cause, not the symptom. Then return a structured result.

**Flow:** Reproduce → Root cause → Minimal fix → Regression test → Verify gate → Commit → Return

## Inputs
Linear issue (`id`, body with reproduction steps, AC, DoD, technical notes), `verifyCmds`, an
isolated worktree on a task branch off the epic branch.

## Step 1 · Mark In Progress
`mcp__linear__update_issue` → "In Progress", assignee "me".

## Step 2 · Reproduce
Confirm you can trigger the bug (a failing test, a script, or manual repro). If you cannot
reproduce, say so in the result and stop — do not guess a fix.

## Step 3 · Root cause (the important part)
Trace the actual code path. Identify the **real** cause — logic error, unhandled null, race,
missing validation, bad query, wrong source-of-truth field, etc.
- **No band-aids.** Do NOT mask a slow query with `staleTime`/cache, do NOT swallow an error, do
  NOT add a retry to hide a determinism bug. If the symptom is performance, fix the query/index/plan.
- Understand blast radius: what else depends on this code? Could the fix break a sibling path?

## Step 4 · Minimal fix
Make the smallest change that addresses the root cause. **No refactoring, no "cleanup" of
surrounding code** — file a `discovered:review` follow-up for that instead. Backend stays Effect,
no `as` casts. For Inngest, respect unique per-iteration step keys and Postgres-based
idempotency/leases (see `workflow-rules.md`).

## Step 5 · Regression test (REQUIRED)
Add a test that **fails before your fix and passes after** — it must specifically catch this bug so
it can never silently return. Tests over guesses.

## Step 6 · Verify gate (BLOCKING)
Run every `verifyCmds`: typecheck (0 errors), lint/biome (0 warnings), the relevant vitest
(0 failures, including your new regression test) and confirm existing tests still pass. Red gate →
**do NOT commit**, return `status: "FAIL"` with output.

## Step 7 · Commit & return
On green only, one conventional commit (local only — never push):
```
fix(<scope>): <subject>

<Linear identifier>
```
Mark the Linear issue **Done** with a comment: root cause, the fix, the regression test, files
changed. Return structured result: `status`, `issueId`, `commitSha`, root-cause summary, files,
AC verification with evidence, gate output, discovered follow-ups.

## Hard rules
Root-cause-not-symptom · minimal fix · regression test mandatory · no scope creep · green gate ·
local commit only.
