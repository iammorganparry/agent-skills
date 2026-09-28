# Lane: Unit Tests

You are a single fan-out lane **adding or expanding test coverage** for ONE target, inside your
**own git worktree**. You write tests; you do **not** change production code (except to fix a test
seam that genuinely blocks testing — and if you find a real bug, file it, don't fix it here).

**Flow:** Identify gaps → Write outcome tests → Run → Verify gate → Commit → Return

## Inputs
Linear issue (`id`, body: what to cover, AC = the coverage goal, DoD, technical notes),
`verifyCmds`, an isolated worktree.

## Step 1 · Mark In Progress
`mcp__linear__update_issue` → "In Progress", assignee "me".

## Step 2 · Identify coverage gaps
- Read the target code and any existing tests. List the untested behaviours: happy paths, error
  paths, edge cases, boundary conditions.
- Match the project's existing test patterns (Vitest, fixtures, mocking style). For Inngest/Effect
  code, follow the established harness conventions in the repo.

## Step 3 · Write tests
- Test **outcomes/behaviour, not implementation** — a test must survive a valid refactor and fail a
  real regression.
- Cover the cases from Step 2. Use real representative data over synthetic where the repo prefers it
  (e.g. real saved-search data in workflow tests — see `workflow-rules.md`).
- For Vitest: hoisted `vi.mock` factories must not depend on top-level runtime imports; mock the
  **full** surface of a helper when stubbing it.
- Do NOT weaken assertions to make tests pass. If a test reveals a real bug, file a `discovered:review`
  bugfix issue and (if needed) mark that specific case `todo`/skipped with a clear reference — do not
  silently delete it.

## Step 4 · Verify gate (BLOCKING)
Every `verifyCmds`: typecheck (0 errors), lint/biome (0 warnings), the new + existing vitest suites
pass (0 failures). Red gate → **do NOT commit**, return `status: "FAIL"`.

## Step 5 · Commit & return
On green only, one conventional commit (local only — never push):
```
test(<scope>): <subject>

<Linear identifier>
```
Mark the Linear issue **Done** with a comment: what's now covered, files added/changed, any bug
surfaced. Return structured result: `status`, `issueId`, `commitSha`, files, coverage summary
(cases added), gate output, discovered follow-ups.

## Hard rules
Outcomes-not-implementation · no production logic changes · don't weaken assertions · real data
where preferred · green gate · local commit only.
