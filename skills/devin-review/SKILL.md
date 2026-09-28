---
name: devin-review
description: Trigger a Devin AI code review of a GitHub PR from the terminal. Defaults to the current branch's PR. Dispatches to Devin's cloud (background) or runs the local Devin CLI synchronously (--wait).
allowed-tools: Bash, AskUserQuestion
---

# Devin Review Skill

Kicks off a Devin AI review session for a pull request without leaving the
terminal. Wraps `~/.claude/skills/devin-review/devin-review.sh`, which either
POSTs to the Devin REST API for fire-and-forget cloud execution or shells
out to the local `devin -p` CLI when the user wants to wait.

## Core constraint

This command only **dispatches** the review — it does not perform a review
itself. Do not summarize, paraphrase, or replace Devin's output. Hand back
whatever the wrapper script prints (session URL, errors, or, in `--wait`
mode, Devin's transcript) verbatim.

## Argument handling

The user may pass:
- A PR number (e.g. `/devin-review 1145`). If omitted, the wrapper derives
  it from the current branch via `gh pr view --json number`.
- `--wait` — run the local Devin CLI and block until the session ends.
- `--background` — POST to the Devin REST API and return a session URL
  immediately. **Default** when neither flag is present.
- Free-form focus text after the flags — passed through to Devin as
  "Additional focus from the requester".

Preserve the user's arguments. Do not strip flags. Do not rewrite the focus
text.

## Execution mode rules

- If the raw arguments include `--wait`, do not ask. Run in the foreground
  via `Bash` (no `run_in_background`).
- If the raw arguments include `--background`, do not ask. Run via `Bash`
  with `run_in_background: false` — the cloud dispatch returns instantly
  anyway.
- Otherwise, use `AskUserQuestion` exactly once with two options, putting
  the recommended option first and suffixing its label with `(Recommended)`:
  - `Run in cloud (background) (Recommended)` — fast, fire-and-forget,
    review continues even after this terminal closes.
  - `Wait for results in this terminal` — blocks; useful when you want the
    transcript inline.

Pick the recommendation based on PR size: for small PRs (<5 files), either
mode is fine; for larger PRs, recommend background.

## Foreground / wait flow

```bash
~/.claude/skills/devin-review/devin-review.sh --wait <pr-number-or-empty> [focus text]
```

Return the command stdout verbatim.

## Background flow

```bash
~/.claude/skills/devin-review/devin-review.sh --background <pr-number-or-empty> [focus text]
```

Return the command stdout verbatim. The script prints the raw Devin API
response followed by a `Devin session: <url>` line on success. Surface that
URL to the user so they can open the session in the Devin web UI.

## Authentication

Auth is configured one of two ways:

1. **`DEVIN_API_KEY` env var** — preferred for `--background` (REST API).
2. **`~/.config/devin/credentials`** — `DEVIN_API_KEY=cog_…` line, mode 600.
   The wrapper sources this if the env var is unset. Already populated.

For `--wait` mode, the user must additionally have run `devin auth login`
once so the local CLI has its own session token.

## Failure handling

The wrapper exits non-zero on these conditions:
- `2` — no PR number provided and no PR for the current branch.
- `3` — `--background` requested but no `DEVIN_API_KEY` available.
- `4` — `--wait` requested but `devin` is not on `PATH`.

Surface the wrapper's stderr message verbatim and stop — do not retry with
a different mode without asking the user.

## Examples

```text
/devin-review                          # current branch's PR, background (after asking)
/devin-review 1145                     # PR #1145 in current repo
/devin-review --wait 1145              # block on local CLI
/devin-review --background 1145 focus on the credit cap math
```
