# Triaging & answering PR feedback (Devin / QA agent / humans)

Three feedback sources land on a PR. Each has its own marker, mechanics, and
reply protocol. **CodeRabbit feedback is owned by the separate `pr-feedback`
skill** — invoke that for `coderabbitai` comments rather than duplicating it here.

## Source identification

| Source        | Author login                 | Marker / shape                                  |
|---------------|------------------------------|-------------------------------------------------|
| Devin         | `devin-ai-integration[bot]`  | inline comment body starts `<!-- devin-review-comment {...} -->`, severity flagged with 🚩 |
| QA agent      | github-actions / runner      | PR-level comment with `<!-- qa-runner-verdict -->` + a pass/fail table |
| CodeRabbit    | `coderabbitai`               | → use the `pr-feedback` skill                   |
| Humans        | real logins                  | inline review comments or `CHANGES_REQUESTED` reviews |

`scripts/pr-status.sh` groups all of these and prints the QA verdict in full.

## Devin & human inline comments

Read each thread, then **question it before acting** (per `pr-feedback` philosophy):
is it a real issue, does it fit project conventions in `CLAUDE.md`, is it actionable?
Take one of three actions — Address / Decline / Clarify — and reply concisely (≤3
sentences, lead with ✅ / ❌ / ❓).

Fetch full bodies (pr-status.sh truncates to 200 chars):
```bash
gh api repos/{owner}/{repo}/pulls/{PR}/comments --paginate \
  | jq -r '.[] | select(.user.login=="devin-ai-integration[bot]") | "### \(.path):\(.line)\n\(.body)\n"'
```

Reply in-thread (use the comment `id` from pr-status.sh):
```bash
gh api repos/{owner}/{repo}/pulls/comments/{COMMENT_ID}/replies \
  -f body="✅ Addressed in <sha> — <one line what changed>."
```

**Resolve the thread** after addressing (review threads need GraphQL, not REST):
```bash
# find unresolved thread ids
gh api graphql -f query='
{ repository(owner:"OWNER", name:"REPO") {
    pullRequest(number: PR) { reviewThreads(first:100) {
      nodes { id isResolved comments(first:1){nodes{author{login} path}} } } } } }'
# resolve one
gh api graphql -f query='mutation{ resolveReviewThread(input:{threadId:"THREAD_ID"}){thread{isResolved}} }'
```
Only resolve threads you actually addressed or that the author confirms. Leave
Declined/Clarify threads open with your reply so the human can weigh in.

Batch all code changes into focused commits, run the verify gate (`yarn typecheck
&& yarn lint` minimum), push once, then post the `✅ Addressed in <sha>` replies.

## QA agent verdict

The verdict table has per-step `pass`/`fail` and a `Summary`. `reproduced_bug: true`
means the original bug was still reproducible on the preview — treat that as a hard
blocker. The QA agent re-runs automatically on each new Preview deployment
(`deployment_status` → `QA Verify / qa`), so **the loop is: fix → push → wait for the
new preview → re-read the verdict**. You do not trigger it manually.

Respond to QA findings by **fixing the product behaviour**, not by editing the QA
checklist to dodge the step. The checklist lives in the PR body between
`<!-- qa-checklist:v1 -->` … `<!-- /qa-checklist -->`; only edit it if a step is
genuinely wrong (bad route, stale label) — and say so in a PR comment. If the change
is truly not user-facing, the checklist should be `Not user-facing — no browser QA
required.` and the QA check will no-op.

A QA failure that is real and in-scope → fix it. A QA failure caused by preview-env
flakiness (seed data, third-party outage) → flag to the user with evidence from the
verdict's Evidence column; do not paper over it.

## Reviews (approvals / change requests)
```bash
gh pr view {PR} --json reviews --jq '.reviews[] | "\(.author.login): \(.state)"'
```
A `CHANGES_REQUESTED` from a human gates merge until they re-review — address the
points, reply, and ping that the changes are pushed. Never dismiss a human review.
