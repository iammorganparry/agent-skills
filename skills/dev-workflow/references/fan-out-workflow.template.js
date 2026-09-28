export const meta = {
  name: 'fan-out-execute',
  description: 'Fan out approved Linear issues across worktree-isolated agents (waves of 5), build + verify each lane, then serially merge green lanes into the epic branch',
  phases: [
    { title: 'Build' },
    { title: 'Verify' },
    { title: 'Reconcile' },
  ],
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTRACT — the router (dev-workflow Phase 2) passes args:
//   args.epicBranch : string                  branch the lanes merge into
//   args.verifyCmds : string[]                 e.g. ["yarn typecheck", "yarn lint", "yarn workspace @trigify/<pkg> test"]
//   args.issues     : Array<{
//       id, identifier, title,
//       type,            // 'feature' | 'bugfix' | 'refactor' | 'unit-tests' | 'spike'
//       acceptance,      // acceptance criteria (string or list)
//       technicalNotes,  // notes incl. file:line refs
//       files,           // files this task is expected to touch
//   }>
// Lane behaviour is defined by the per-type templates at:
//   ~/.claude/skills/dev-workflow/references/lane-<type>.md
// ─────────────────────────────────────────────────────────────────────────────

const MAX_CONCURRENT = 5 // HARD cap — worktrees are resource-heavy. Do not raise.

const issues = Array.isArray(args?.issues) ? args.issues : []
const verifyCmds = args?.verifyCmds ?? []
const epicBranch = args?.epicBranch ?? 'HEAD'

const code = issues.filter((i) => i.type !== 'spike')
const spikes = issues.filter((i) => i.type === 'spike')

// ── Schemas (force structured returns) ───────────────────────────────────────
const LANE_RESULT = {
  type: 'object',
  required: ['status', 'issueId', 'summary'],
  properties: {
    status: { enum: ['PASS', 'PARTIAL', 'FAIL', 'BLOCKED'] },
    issueId: { type: 'string' },
    identifier: { type: 'string' },
    branch: { type: 'string', description: 'task branch holding the commit, if any' },
    commitSha: { type: 'string' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    acVerification: { type: 'string', description: 'AC-by-AC evidence' },
    gateOutput: { type: 'string', description: 'summary of verify gate results' },
    discovered: { type: 'array', items: { type: 'string' }, description: 'out-of-scope follow-ups to file' },
    summary: { type: 'string' },
  },
}
const VERDICT = {
  type: 'object',
  required: ['isReal', 'reason'],
  properties: {
    isReal: { type: 'boolean', description: 'does the lane genuinely satisfy its AC with a green gate?' },
    reason: { type: 'string' },
    blocking: { type: 'array', items: { type: 'string' } },
  },
}
const SPIKE_RESULT = {
  type: 'object',
  required: ['status', 'issueId', 'findings', 'recommendation'],
  properties: {
    status: { enum: ['PASS', 'BLOCKED'] },
    issueId: { type: 'string' },
    findings: { type: 'string' },
    recommendation: { type: 'string', description: 'next lane type + draft tasks + files' },
  },
}
const RECONCILE_RESULT = {
  type: 'object',
  required: ['merged', 'skipped'],
  properties: {
    merged: { type: 'array', items: { type: 'string' } },
    skipped: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
}

// ── Prompt builders ──────────────────────────────────────────────────────────
const laneFile = (type) => `~/.claude/skills/dev-workflow/references/lane-${type}.md`

function laneprompt(issue) {
  return [
    `You are the "${issue.type}" lane for Linear issue ${issue.identifier ?? issue.id}: "${issue.title}".`,
    `You are running in your OWN git worktree (isolated copy of the repo). Work only on this task.`,
    ``,
    `FIRST, read and follow exactly: ${laneFile(issue.type)}`,
    `Also read the project's .claude/workflow-rules.md for verify-gate commands, git/Linear conventions, and the hard guardrails.`,
    ``,
    `## Task`,
    `Acceptance criteria:\n${fmt(issue.acceptance)}`,
    `Technical notes (cite/reuse these):\n${fmt(issue.technicalNotes)}`,
    `Files expected to touch: ${fmt(issue.files)}`,
    ``,
    `## Verify gate (BLOCKING — run before any commit)`,
    verifyCmds.map((c) => `  - ${c}`).join('\n') || '  - (none provided — use project defaults from workflow-rules.md)',
    `All must pass with zero errors/warnings. If the gate is red, DO NOT commit; return status FAIL with the failing output.`,
    ``,
    `## On green only`,
    `Create ONE conventional commit on a task branch named "${issue.identifier ?? issue.id}-<slug>" off ${epicBranch}. Local commit only — never push.`,
    `Update the Linear issue to Done with a completion comment.`,
    `Return the structured result (status, branch, commitSha, filesChanged, acVerification, gateOutput, discovered).`,
  ].join('\n')
}

function verifyprompt(build, issue) {
  return [
    `Adversarially verify the "${issue.type}" lane for ${issue.identifier ?? issue.id}: "${issue.title}".`,
    `The lane reported: status=${build?.status}, branch=${build?.branch ?? 'n/a'}, summary=${build?.summary ?? ''}.`,
    `Its AC evidence: ${build?.acVerification ?? '(none)'}`,
    `Its gate output: ${build?.gateOutput ?? '(none)'}`,
    ``,
    `Check out the lane's branch (read-only inspection) and judge SKEPTICALLY:`,
    `  - Does the diff actually satisfy EVERY acceptance criterion (not just claim to)?`,
    `  - Did the verify gate genuinely pass (typecheck/lint/tests), or was a check skipped/weakened?`,
    `  - Any scope creep, unrequested refactor, band-aid (cache masking a real issue), 'as' cast, or missing regression test (bugfix)?`,
    `Default isReal=false if you are not convinced. Return the verdict with blocking issues if any.`,
  ].join('\n')
}

function spikeprompt(issue) {
  return [
    `You are the "spike" (read-only) lane for Linear issue ${issue.identifier ?? issue.id}: "${issue.title}".`,
    `FIRST, read and follow exactly: ${laneFile('spike')}`,
    `Make NO code changes, NO commits. Investigate read-only and produce evidence-backed findings.`,
    ``,
    `## Question / goal`,
    fmt(issue.acceptance),
    `Technical notes:\n${fmt(issue.technicalNotes)}`,
    ``,
    `End with a concrete recommendation: which lane type should follow, draft AC, and files involved.`,
    `Update the Linear issue to Done with the findings as a comment. Return the structured result.`,
  ].join('\n')
}

function fmt(v) {
  if (v == null) return '(none)'
  if (Array.isArray(v)) return v.map((x) => `  - ${x}`).join('\n')
  return String(v)
}

// ── Phase: Build + Verify in waves of <=5 (concurrency hard-capped) ───────────
const built = []
for (let i = 0; i < code.length; i += MAX_CONCURRENT) {
  const wave = code.slice(i, i + MAX_CONCURRENT)
  log(`Build wave ${Math.floor(i / MAX_CONCURRENT) + 1}: ${wave.length} lane(s) — ${wave.map((w) => w.identifier ?? w.id).join(', ')}`)
  // pipeline: each issue flows build -> verify independently; the wave is a barrier that bounds concurrency to <=5
  const waveResults = await pipeline(
    wave,
    (issue) =>
      agent(laneprompt(issue), {
        label: `build:${issue.identifier ?? issue.id}`,
        phase: 'Build',
        isolation: 'worktree',
        schema: LANE_RESULT,
      }),
    (build, issue) =>
      agent(verifyprompt(build, issue), {
        label: `verify:${issue.identifier ?? issue.id}`,
        phase: 'Verify',
        schema: VERDICT,
      }).then((verdict) => ({ ...build, issue, verdict })),
  )
  built.push(...waveResults.filter(Boolean))
}

// ── Spikes: read-only, also waved at 5 to keep total agents bounded ──────────
const findings = []
for (let i = 0; i < spikes.length; i += MAX_CONCURRENT) {
  const wave = spikes.slice(i, i + MAX_CONCURRENT)
  log(`Spike wave ${Math.floor(i / MAX_CONCURRENT) + 1}: ${wave.length} spike(s)`)
  const res = await parallel(
    wave.map((s) => () => agent(spikeprompt(s), { label: `spike:${s.identifier ?? s.id}`, phase: 'Build', schema: SPIKE_RESULT })),
  )
  findings.push(...res.filter(Boolean))
}

// ── Phase: Reconcile — serially merge only PASS + verified lanes into the epic ─
const green = built.filter((b) => b.status === 'PASS' && b.verdict?.isReal && b.branch)
const failed = built.filter((b) => !(b.status === 'PASS' && b.verdict?.isReal))

let reconcile = { merged: [], skipped: failed.map((f) => f.issue?.identifier ?? f.issueId), notes: 'no green lanes to merge' }
if (green.length > 0) {
  reconcile = await agent(
    [
      `Reconcile the fan-out into the epic branch "${epicBranch}".`,
      `Merge these verified-green task branches into ${epicBranch}, ONE AT A TIME, in this order:`,
      green.map((g) => `  - ${g.branch}  (${g.issue?.identifier ?? g.issueId}: ${g.issue?.title ?? ''})`).join('\n'),
      ``,
      `After EACH merge, re-run the verify gate (${verifyCmds.join(' && ') || 'project defaults'}).`,
      `If a merge conflicts or the gate goes red after a merge, STOP merging that branch, leave it unmerged, record it in "skipped" with the reason, and continue with the rest.`,
      `Do NOT push and do NOT merge the epic branch to any protected branch. Local only.`,
      `Return which branches merged and which were skipped (with reasons).`,
    ].join('\n'),
    { label: 'reconcile:merge', phase: 'Reconcile', schema: RECONCILE_RESULT },
  )
}

return {
  summary: {
    total: issues.length,
    passed: green.length,
    failed: failed.length,
    spikes: findings.length,
  },
  built: built.map((b) => ({ issue: b.issue?.identifier ?? b.issueId, status: b.status, verdict: b.verdict, branch: b.branch, commitSha: b.commitSha, discovered: b.discovered })),
  findings,
  reconcile,
}
