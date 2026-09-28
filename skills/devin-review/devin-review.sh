#!/usr/bin/env bash
# Wrapper that triggers a Devin AI review of a PR.
#
# Usage:
#   devin-review.sh [--wait|--background] [<pr-number>] [extra focus text...]
#
# - Without a PR number, derives it from `gh pr view --json number` for the
#   current branch.
# - With --background (default), POSTs to the Devin REST API so the session
#   runs in the cloud and returns immediately with a session URL.
# - With --wait, shells out to the local `devin -p` CLI and blocks until the
#   session completes (requires `devin` on PATH and `devin auth login`).
#
# Auth: reads DEVIN_API_KEY from the environment, falling back to
# ~/.config/devin/credentials (KEY=value format, mode 600).
set -euo pipefail

CREDS_FILE="${HOME}/.config/devin/credentials"
if [[ -z "${DEVIN_API_KEY:-}" && -r "${CREDS_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CREDS_FILE}"
  export DEVIN_API_KEY
fi

mode="background"
pr_number=""
focus_parts=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait) mode="wait"; shift ;;
    --background) mode="background"; shift ;;
    --help|-h)
      sed -n '2,15p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "${pr_number}" && "$1" =~ ^[0-9]+$ ]]; then
        pr_number="$1"
      else
        focus_parts+=("$1")
      fi
      shift
      ;;
  esac
done

if [[ -z "${pr_number}" ]]; then
  pr_number="$(gh pr view --json number --jq '.number' 2>/dev/null || true)"
fi
if [[ -z "${pr_number}" ]]; then
  echo "error: no PR number provided and no PR found for the current branch" >&2
  exit 2
fi

repo_slug="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
if [[ -z "${repo_slug}" ]]; then
  echo "error: could not resolve repo via gh CLI" >&2
  exit 2
fi
pr_url="https://github.com/${repo_slug}/pull/${pr_number}"

focus_text=""
if (( ${#focus_parts[@]} > 0 )); then
  focus_text="${focus_parts[*]}"
fi

read -r -d '' prompt <<EOF || true
Please perform a thorough code review of pull request ${pr_url}.

Repository: ${repo_slug}
PR number: ${pr_number}

Focus areas:
- Correctness bugs (race conditions, null/undefined handling, logic errors).
- Type safety violations (any \`as\` casts, unsafe \`any\`, missing narrowing).
- Test coverage gaps for the new behaviour.
- Security issues (auth bypass, injection, secret handling, missing org scoping).
- Performance regressions on hot paths.
- Adherence to repo conventions (Effect-TS for backend services, tRPC for data fetching, no useEffect abuse, dayjs for dates).

Please leave inline review comments on the PR via the GitHub API where issues are concrete; if a finding is broad, include it in the summary review body. Submit the review as either "request changes" if blocking issues are found, "comment" for non-blocking observations, or "approve" only if no issues are found.

${focus_text:+Additional focus from the requester: ${focus_text}}
EOF

if [[ -z "${DEVIN_API_KEY:-}" && "${mode}" == "background" ]]; then
  echo "error: DEVIN_API_KEY is not set and ~/.config/devin/credentials is missing" >&2
  echo "       Either set DEVIN_API_KEY or run with --wait after \`devin auth login\`." >&2
  exit 3
fi

case "${mode}" in
  background)
    response="$(curl -sS -X POST "https://api.devin.ai/v1/sessions" \
      -H "Authorization: Bearer ${DEVIN_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg p "${prompt}" --arg t "Review PR #${pr_number}" '{prompt: $p, title: $t, idempotent: true}')")"
    echo "${response}"
    session_url="$(echo "${response}" | jq -r '.url // .session_url // empty' 2>/dev/null || true)"
    if [[ -n "${session_url}" ]]; then
      echo ""
      echo "Devin session: ${session_url}"
    fi
    ;;
  wait)
    if ! command -v devin >/dev/null 2>&1; then
      echo "error: \`devin\` CLI not found on PATH. Install with:" >&2
      echo "       curl -fsSL https://cli.devin.ai/install.sh | bash" >&2
      exit 4
    fi
    exec devin -p "${prompt}"
    ;;
esac
