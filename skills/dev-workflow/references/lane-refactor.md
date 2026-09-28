# Lane: Refactor

You are a single fan-out lane performing **ONE refactor** inside your **own git worktree**. The
golden rule: **behaviour is unchanged.** You restructure; you do not add features or fix bugs.

**Flow:** Understand → Refactor → Prove behaviour unchanged → Verify gate → Commit → Return

## Inputs
Linear issue (`id`, body: what to restructure and why, AC = the structural goal, DoD, technical
notes), `verifyCmds`, an isolated worktree.

## Step 1 · Mark In Progress
`mcp__linear__update_issue` → "In Progress", assignee "me".

## Step 2 · Understand current behaviour
- Read the code thoroughly; map inputs → outputs and side effects.
- **Capture the current behaviour as a safety net**: ensure tests already cover it; if coverage is
  thin, add characterization tests **first** (they must pass against the un-refactored code).

## Step 3 · Refactor
- Restructure in small, safe steps. Preserve the public API/signatures unless the task explicitly
  changes them.
- Apply the project standards: Effect services, DB behind service methods, no `as` casts, DRY,
  zero warnings. Remove dead code that the refactor obsoletes — nothing more.
- **No behaviour changes, no scope creep.** If you spot a bug, do NOT fix it here — file a
  `discovered:review` bugfix follow-up and leave behaviour identical (including the bug).

## Step 4 · Prove behaviour unchanged
- All pre-existing tests + your characterization tests pass **without modification of their
  assertions**. If you had to change an assertion, behaviour changed — stop and reassess.
- Where useful, diff before/after outputs for representative inputs.

## Step 5 · Verify gate (BLOCKING)
Every `verifyCmds`: typecheck (0 errors), lint/biome (0 warnings), the relevant vitest (0
failures). Red gate → **do NOT commit**, return `status: "FAIL"`.

## Step 6 · Commit & return
On green only, one conventional commit (local only — never push):
```
refactor(<scope>): <subject>

<Linear identifier>
```
Mark the Linear issue **Done** with a comment: what was restructured, why behaviour is provably
unchanged, files changed. Return structured result: `status`, `issueId`, `commitSha`, files,
behaviour-unchanged evidence, gate output, discovered follow-ups.

## Hard rules
Behaviour-unchanged is sacred · no feature/bugfix smuggled in · characterization tests before
refactor · green gate · local commit only.
