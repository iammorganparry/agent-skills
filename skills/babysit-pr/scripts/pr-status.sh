#!/usr/bin/env bash
# pr-status.sh [PR_NUMBER]
#
# Prints a consolidated "babysitting dashboard" for a PR: CI checks (with the
# run id needed to pull failed logs), open review threads grouped by author
# (Devin / CodeRabbit / humans), and the QA agent's machine verdict.
#
# Defaults to the current branch's PR when PR_NUMBER is omitted.
# Read-only: fetches state only, never edits the PR.
set -euo pipefail

PR="${1:-}"
if [[ -z "$PR" ]]; then
  PR="$(gh pr view --json number --jq '.number' 2>/dev/null || true)"
fi
if [[ -z "$PR" || "$PR" == "null" ]]; then
  echo "ERROR: no PR number given and no PR for the current branch." >&2
  echo "Pass one explicitly: pr-status.sh 1234" >&2
  exit 2
fi

REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"

echo "═══════════════════════════════════════════════════════════════"
gh pr view "$PR" --json number,title,url,author,state,isDraft,mergeable,headRefName \
  --jq '"PR #\(.number)  \(.title)\nAuthor: \(.author.login)   Branch: \(.headRefName)   State: \(.state)   Draft: \(.isDraft)   Mergeable: \(.mergeable)\n\(.url)"'
echo "═══════════════════════════════════════════════════════════════"

echo
echo "── CI CHECKS ──────────────────────────────────────────────────"
# bucket is one of: pass | fail | pending | skipping | cancel
checks_json="$(gh pr checks "$PR" --json name,state,bucket,link,workflow 2>/dev/null || echo '[]')"
if [[ "$checks_json" == "[]" || -z "$checks_json" ]]; then
  echo "(no checks reported yet — CI may not have started)"
else
  echo "$checks_json" | jq -r '
    sort_by(.bucket) | .[] |
    ( if .bucket=="fail" then "❌"
      elif .bucket=="pass" then "✅"
      elif .bucket=="pending" then "⏳"
      elif .bucket=="skipping" then "⚪"
      else "🚫" end) as $i |
    "\($i) [\(.bucket)] \(.workflow // "?") / \(.name)\n      \(.link // "")"'
  echo
  echo "Summary: $(echo "$checks_json" | jq -r '[.[]|.bucket]|group_by(.)|map("\(length) \(.[0])")|join(", ")')"
  echo
  # Surface run IDs for failing checks so logs can be pulled directly.
  fails="$(echo "$checks_json" | jq -r '.[]|select(.bucket=="fail")|.link' | grep -oE '/runs/[0-9]+' | grep -oE '[0-9]+' | sort -u || true)"
  if [[ -n "$fails" ]]; then
    echo "Failed run IDs (pull logs with:  gh run view <id> --log-failed):"
    for id in $fails; do echo "   gh run view $id --log-failed"; done
  fi
fi

echo
echo "── REVIEW THREADS (inline code comments) ──────────────────────"
# Inline review comments. in_reply_to_id present => it's a reply in a thread.
comments_json="$(gh api "repos/$REPO/pulls/$PR/comments" --paginate 2>/dev/null || echo '[]')"
total="$(echo "$comments_json" | jq 'length')"
echo "Total inline comments: $total"
if [[ "$total" != "0" ]]; then
  echo
  echo "By author:"
  echo "$comments_json" | jq -r 'group_by(.user.login)|map("   \(length)x \(.[0].user.login)")|.[]'
  echo
  echo "Top-level comments (not replies) — these are the threads to resolve:"
  echo "$comments_json" | jq -r '
    .[] | select(.in_reply_to_id == null) |
    "  • [\(.user.login)] \(.path):\(.line // .original_line // "?")  (id \(.id))\n      \(.body | gsub("\r";"") | gsub("\n";" ") | .[0:200])"'
fi

echo
echo "── PR-LEVEL COMMENTS & QA VERDICT ─────────────────────────────"
issue_json="$(gh api "repos/$REPO/issues/$PR/comments" --paginate 2>/dev/null || echo '[]')"
# QA agent verdict carries the marker <!-- qa-runner-verdict -->
qa="$(echo "$issue_json" | jq -r '[.[]|select(.body|contains("qa-runner-verdict"))]|last // empty')"
if [[ -n "$qa" ]]; then
  echo "🤖 QA agent verdict (latest):"
  echo "$qa" | jq -r '.body' | sed 's/^/   /'
else
  echo "🤖 QA agent: no verdict comment yet (marker <!-- qa-runner-verdict -->)."
fi
echo
echo "Other PR-level comments by author:"
echo "$issue_json" | jq -r 'group_by(.user.login)|map("   \(length)x \(.[0].user.login)")|.[]' 2>/dev/null || echo "   (none)"

echo
echo "── REVIEWS (approvals / change requests) ──────────────────────"
gh pr view "$PR" --json reviews \
  --jq '.reviews | if length==0 then "   (no reviews)" else (group_by(.author.login)|map("   \(.[-1].author.login): \(.[-1].state)")|.[]) end' 2>/dev/null || echo "   (none)"

echo
echo "═══════════════════════════════════════════════════════════════"
echo "Next: triage failing checks & unresolved threads per SKILL.md."
