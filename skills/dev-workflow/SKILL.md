---
name: dev-workflow
description: Default front-door workflow router. Use when the user asks to "create a workflow for this", "implement", "build", "fix", "refactor", "add", "plan this task", or hands over any non-trivial engineering request. Classifies the task, plans it interactively (interview + mandatory codebase research → Linear issues), then fans every task out in parallel across worktree-isolated agents via the Workflow tool, and reconciles results back to Linear.
allowed-tools: Bash, Read, Glob, Grep, Edit, Write, Task, Workflow, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, TaskGet, mcp__linear__*, mcp__linear-server__*
model: opus
---

# Dev Workflow — Default Engineering Front-Door

This is the **single deterministic entrypoint** for engineering work. Given any request it:
1. **Classifies** the task and announces the track (so the user can veto).
2. **Plans** it interactively — interview + *mandatory* codebase research → Linear issues.
3. **Fans out** execution in parallel: one worktree-isolated agent per issue, via the Workflow tool.
4. **Reconciles** results back to Linear and reports.

Linear is kept **only** as the issue/status
ledger — it does not drive execution. Parallelism comes from the Workflow tool, not hand-coordinated agent teams.

> ## ⛔ NON-NEGOTIABLE: this skill executes via the Workflow tool
> **Invoking this skill IS your explicit, standing opt-in to multi-agent orchestration. It
> satisfies the `Workflow` tool's opt-in requirement on its own — you do not need `ultracode` or any
> further confirmation.** For ANY non-trivial task you MUST run execution through the **`Workflow`
> tool** in Phase 2.
>
> The failure mode this skill exists to prevent: **doing the work inline yourself** (editing files
> in the main session), or substituting plain `Agent`/`Task` calls. Both are WRONG here. A single
> focused task is NOT a reason to go inline — it runs as a **one-lane Workflow**. The Workflow tool's
> general reluctance ("don't orchestrate a task that merely benefits") **does not apply** inside this
> skill: the user opted in by invoking it. If you finish a non-trivial `/dev-workflow` request
> without ever calling the `Workflow` tool, you have used the skill incorrectly.
>
> The ONLY path that skips the Workflow tool is a genuinely **trivial** task (Phase 0).

> **Read `<project>/.claude/workflow-rules.md` before doing anything.** It carries the
> project-specific verify gate commands, git/release rules, Linear conventions, and the hard
> guardrails this workflow must enforce. The router is generic; that file makes it concrete.

---

## Phase 0 · CLASSIFY (always first)

Before any work, decide the track and **state it in one line** so the user can redirect:

- **Trivial** — a true one-liner: typo, a single obvious one-line fix, a doc/comment tweak, a config
  value nudge. No design, no logic to reason about, touches ~1 file. **If you have to think about how
  to do it, it is NOT trivial.**
  → **Handle inline**: make the change, run the relevant verify command, report. **Skip planning,
  Linear, and fan-out entirely.** This is the only escape hatch — keep it narrow.

- **Non-trivial** — EVERYTHING else. A feature, ANY single focused feature/fix/refactor, a
  multi-step change, "build/implement/add X", anything spanning >1 file, or any uncertainty about
  scope. **A "single focused task" is non-trivial — it does NOT go inline.**
  → Proceed to **Phase 1 → 2 → 3**. The Workflow tool is mandatory here. A single task runs as a
  **one-lane** Workflow — still via the Workflow tool, never inline.

Announce like: `Track: non-trivial → plan + fan-out (1 lane)` or `Track: trivial → inline fix`.
When in doubt, classify **non-trivial** and run the Workflow — the user can veto after you announce.

If the user pointed at existing Linear issues (e.g. `/dev-workflow TRI-1234` or a project/label),
**skip the interview** — pull those issues (`mcp__linear__list_issues` / `get_issue`), confirm the
set with the user, and jump to Phase 2.

---

## Phase 1 · PLAN  (interactive, in this conversation)

Goal: turn the request into a researched, approved set of Linear issues. **Never write code in
this phase.**

### 1.1 Interview (one question at a time, plain text)
Walk the 4-part framework, asking only what you actually don't know:
1. **Problem** — what's the real need / pain, and who has it?
2. **Scope & boundaries** — what's explicitly IN and OUT? (Pin this down — scope creep is the #1
   correction in this repo's history.)
3. **Stories & acceptance** — concrete, testable acceptance criteria per outcome.
4. **Technical context** — constraints, integrations, data sources, deadlines.

### 1.2 Codebase research — MANDATORY, DO NOT SKIP
Use Glob/Grep/Read (or spawn `Explore` agents for breadth). **Every technical note in the plan
must cite a real `file:line` + snippet.** A plan with no research evidence is rejected.
- **Reuse before build**: find the existing table/service/component/util that already does this.
  The repo's recurring lesson is *"trace the existing pattern/boundary/source-of-truth before
  acting — don't duplicate, don't fall back, don't cast, don't assume."*
- Identify the files each task will touch (this feeds worktree conflict-awareness in Phase 2).

### 1.3 Decompose → task list
Break the work into the **smallest independently-shippable tasks**. For each, assign a **lane type**:

| Lane | Use when | Template |
|---|---|---|
| `feature` | new capability / behaviour | `references/lane-feature.md` |
| `bugfix` | something is broken | `references/lane-bugfix.md` |
| `refactor` | restructure, behaviour unchanged | `references/lane-refactor.md` |
| `unit-tests` | add/expand test coverage | `references/lane-unit-tests.md` |
| `spike` | research/diagnosis, **no code** | `references/lane-spike.md` |

Each task carries: user story, acceptance criteria, definition of done, technical notes (with
`file:line` refs), lane type, and the files it's expected to touch.

### 1.4 Approval gate
Present the task list (titles, lane types, one-line scope, files touched). **Stop and get explicit
user approval.** Do not create Linear issues or fan out until approved.

### 1.5 Create Linear issues
On approval, create one Linear issue per task (`mcp__linear__create_issue`), following the team
and label conventions in `workflow-rules.md` (`skill:<lane>`, an `epic` link, etc.). Embed the full
AC/DoD/technical-notes in each issue body. **This is the only Phase-1 write.** Capture the issue set
(id, identifier, title, lane type, files) for Phase 2.

---

## Phase 2 · FAN-OUT EXECUTE  (the Workflow tool — MANDATORY)

**You MUST call the `Workflow` tool here. This is not optional and not conditional on task size.**
Do not implement the issues yourself in the main session. Do not use plain `Agent`/`Task` calls
instead. If the approved set is a single task, you still call `Workflow` — it runs as one lane.
Skipping this step means the skill failed.

Read the canonical script at `references/fan-out-workflow.template.js`, parameterise it, and run it
via the `Workflow` tool, passing:
- `epicBranch` — the epic/feature branch tasks merge into,
- `verifyCmds` — the verify gate commands from `workflow-rules.md`,
- `issues` — the approved issue set from Phase 1.5 (`{ id, title, type, acceptance, technicalNotes, files }`).

What the script does (do **not** re-implement — read the template and run it):
- **Waves of ≤5** issues at a time — **hard concurrency cap of 5 lanes** (worktrees are
  resource-heavy). Later issues wait for the next wave.
- Each code issue runs in **its own git worktree** (`isolation:'worktree'`), executes its **lane
  template**, then hits the **verify gate** (typecheck + lint/biome + the relevant vitest), and
  only on green does it commit (conventional message) and merge its worktree back.
- A failing gate → that lane does **not** commit/merge and is reported FAIL.
- `spike` issues run read-only (no worktree, no edits) → return findings.
- Each lane updates its own Linear issue status.

Call it like:
`Workflow({ script: <contents of fan-out-workflow.template.js>, args: { epicBranch, verifyCmds, issues } })`
then watch `/workflows`. The tool persists the script and returns a `scriptPath` — iterate on that
file and re-run with `{ scriptPath, resumeFromRunId }` if a wave needs rework.

> **Args marshalling gotcha:** if the run completes instantly with `total: 0`, the `args` payload
> didn't reach the script. Fall back to writing a wave script with the issues inlined as consts
> (copy the template, replace the three `args` reads) and invoke via `{ scriptPath }`.

**Self-check before leaving Phase 2:** did you actually call the `Workflow` tool? If not, you did the
work the wrong way — stop and run it.

---

## Phase 3 · RECONCILE

When the Workflow returns:
1. **Aggregate** per-issue results: PASS / PARTIAL / FAIL with evidence.
2. **Review pass** — invoke the `code-review` skill (or an adversarial review agent) over the merged
   diff for correctness + reuse/simplification. Cross-check against the guardrails in `workflow-rules.md`.
3. **File gaps** — anything discovered (missing tests, follow-up bugs, refactors) becomes a new Linear
   issue labelled `discovered:review`, which can re-enter this workflow.
4. **Reconcile Linear** — ensure every issue's status reflects reality.
5. **Report** to the user: what shipped, what failed and why, what gap issues were filed.
6. **Commits are LOCAL.** Never push or merge to a protected branch without explicit go-ahead.

### Phase 3.5 · HUMAN REVIEW GATE (MANDATORY — after EVERY wave, before the next one)
The gate runs **per wave/workflow run, not once at the end of the epic**. When a wave's reconcile
finishes, **STOP — do not launch the next wave** until the user approves or denies the wave's
changes. This is a blocking gate; there are no autonomous multi-wave runs.

- Present a per-wave review pack: lanes PASS/FAIL, what merged, the wave's diffstat on the epic
  branch, and the exact commands to review locally, e.g.:
  `git log --oneline <prev-wave-tip>..<epicBranch>` ·
  `git diff <prev-wave-tip>...<epicBranch>` (or per-area: `… -- packages/services`).
  The user is already on the epic branch locally — changes are immediately inspectable.
- **Approve** → launch the next wave. **Deny / request changes** → apply fixes (small ones inline
  on the epic branch; substantial ones as a fix lane), re-present, and only proceed on approval.
  A denied lane's merge can be reverted (`git revert -m 1 <merge-commit>`) before continuing.
- After the FINAL wave is approved, the same gate doubles as the whole-epic review before the PR.

### PR policy — ONE PR per epic, ever
- **NEVER create PRs for individual lane/workflow branches.** Lane branches are merge vehicles
  into the epic branch only; delete them after reconcile (`git branch -d`).
- After the user explicitly approves the local review: push the epic branch and open **exactly ONE
  PR** (epic branch → base), with a Conventional-Commit title per `workflow-rules.md`, a body
  summarising the issue set (link every Linear issue), and the verify-gate evidence.

---

## Memory protocol (from `~/.claude/CLAUDE.md` — honour it)
- Review recalled memories / threads **before** Phase 1 research; don't re-explore what they cover.
- On a feature branch with no thread, create one before work; append decisions/findings as you go.
- Store 1–3 reflection memories at the end (DECISION / GOTCHA / WORKING_SOLUTION / APP_KNOWLEDGE).

## Hard rules (always)
- **Non-trivial work executes via the `Workflow` tool — never inline, never via plain `Agent`/`Task`.**
  A single focused task still runs as a one-lane Workflow. Inline editing is only for trivial one-liners.
- **No scope creep, no unrequested refactor.** Build exactly the task.
- **Reuse before build.** Verify against existing code/tables/services first.
- **Root cause, not band-aids.** No cache/`staleTime` masking a real problem.
- **Tests, not guesses.** Every bugfix lane ships a regression test.
- **No `as` casts; Effect for backend; unique per-iteration Inngest step keys.** (See `workflow-rules.md`.)
- **Don't re-read files already seen; don't read whole large files needlessly.**
- **Announce the classification; stop for approval before creating issues; never push without go-ahead.**
