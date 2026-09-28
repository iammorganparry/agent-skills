# Triaging & answering PR feedback (humans / review bots / QA bots)

Feedback lands on a PR from people and from bots. Identify each source by its
author login, then triage every item the same way.

## Source identification

| Source             | How to recognise it                                                        |
|--------------------|-----------------------------------------------------------------------------|
| Humans             | real logins; inline review comments or `CHANGES_REQUESTED` reviews          |
| Review bots        | logins ending `[bot]` or known bot accounts — e.g. `devin-ai-integration[bot]`, `coderabbitai[bot]`, `copilot-pull-request-reviewer[bot]`, `greptile-apps[bot]`, `sourcery-ai[bot]` |
| QA / preview bots  | a PR-level comment from a bot or Actions run with a pass/fail table, often behind an HTML marker (`<!-- …verdict… -->`) |
| Status-only bots   | Vercel, Netlify, Codecov, Socket, Dependabot — informational; act only when they gate merge |

`scripts/pr-status.sh` groups inline comments and PR-level comments by author and
prints the latest bot comment that looks like a verdict (override the match with
`QA_MARKER=<text>`).

If a dedicated skill exists for a specific bot's workflow (for example a
CodeRabbit feedback skill), prefer it for that bot's comments.

## Review threads (humans and bots)

Read each thread, then **question it before acting**: is it a real issue, does it
fit the repo's conventions (agent docs, linters, existing patterns), is it in scope
for this PR? Take one of three actions and reply concisely (≤3 sentences, lead
with ✅ / ❌ / ❓):

- **Address** — make the change, reply with the SHA.
- **Decline** — explain why (wrong, out of scope, conflicts with conventions).
- **Clarify** — ask the one question that unblocks it.

Bots are wrong more often than humans; decline confidently when they are, but
never ignore a comment silently.

Fetch full bodies (pr-status.sh truncates to 200 chars):
```bash
gh api repos/{owner}/{repo}/pulls/{PR}/comments --paginate \
  | jq -r '.[] | select(.in_reply_to_id == null) | "### [\(.user.login)] \(.path):\(.line // .original_line)  (id \(.id))\n\(.body)\n"'
```

Reply in-thread (use the comment `id`):
```bash
gh api repos/{owner}/{repo}/pulls/{PR}/comments/{COMMENT_ID}/replies \
  -f body="✅ Addressed in <sha> — <one line what changed>."
```

**Resolve the thread** after addressing (review threads need GraphQL, not REST):
```bash
# find unresolved thread ids
gh api graphql -f query='
{ repository(owner:"OWNER", name:"REPO") {
    pullRequest(number: PR) { reviewThreads(first:100) {
      nodes { id isResolved comments(first:1){nodes{author{login} path body}} } } } } }'
# resolve one
gh api graphql -f query='mutation{ resolveReviewThread(input:{threadId:"THREAD_ID"}){thread{isResolved}} }'
```
Only resolve threads you actually addressed or that the author confirms. Leave
Declined/Clarify threads open with your reply so a human can weigh in.

Batch code changes into focused commits, run the repo's verify gate, push once,
then post the `✅ Addressed in <sha>` replies.

## QA / preview-test bot verdicts

Some repos run an agent or E2E suite against each preview deployment and post a
verdict. Treat any failing step as a blocker. These usually re-run on each new
preview, so the loop is: **fix → push → wait for the new preview → re-read the
verdict**.

Respond by **fixing the product behaviour**, not by editing the QA checklist or
test plan to dodge the step. Only change the checklist if a step is genuinely
wrong (bad route, stale label) — and say so in a PR comment.

A real, in-scope QA failure → fix it. A failure caused by preview-environment
flakiness (seed data, third-party outage) → flag to the user with the verdict's
evidence; do not paper over it.

## Reviews (approvals / change requests)
```bash
gh pr view {PR} --json reviews --jq '.reviews[] | "\(.author.login): \(.state)"'
```
A human `CHANGES_REQUESTED` gates merge until they re-review — address the
points, reply, and ping that the changes are pushed. Never dismiss a human review.
