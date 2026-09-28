---
name: google-workspace-cli
description: >-
  Drive, Gmail, Calendar, Sheets, Docs, Slides, Chat, Tasks, People, Forms, Keep,
  Meet, Classroom, and Admin operations from the terminal via the `gws` (Google
  Workspace CLI) tool. Use whenever the task involves reading or writing a user's
  Google account data from the command line — e.g. "send an email", "check my
  inbox", "what's on my calendar", "upload this to Drive", "read/append a Google
  Sheet", "append to a Google Doc", "post to a Chat space", "create a task", or
  any Google Workspace API call. Covers auth setup, discovery-based commands,
  the `+` helper commands, schema introspection, output formats, and pagination.
---

# Google Workspace CLI (`gws`)

`gws` is a single binary that exposes every Google Workspace API. Commands are
built dynamically from Google's Discovery Service, so the CLI mirrors the API
surface exactly. Install: `brew install googleworkspace-cli` (also `npm i -g
@googleworkspace/cli`, or `cargo install --git https://github.com/googleworkspace/cli --locked`).

## Golden rule: discover, don't guess

The generic commands map 1:1 to Google's REST APIs. Do NOT invent parameter
names or JSON body shapes from memory — they are frequently wrong. Instead:

1. `gws <service> --help` — list a service's resources and `+` helpers.
2. `gws <service> <resource> [subresource] --help` — list methods.
3. `gws schema <service.resource.method>` — the exact request params + body
   schema (JSON). Add `--resolve-refs` to inline referenced types.
4. Build the call, then run it with `--dry-run` first to validate locally
   without hitting the API.

Skipping schema inspection for a non-trivial write is the #1 cause of failures.

## Two ways to call

**`+` helper commands** (hand-crafted, prefer these for common tasks — they
handle MIME/base64/threading/formatting for you):

```bash
gws gmail +send --to a@x.com --subject 'Hi' --body 'Hello'   # also --html --attach/-a --cc --bcc --draft --from
gws gmail +triage                       # unread inbox summary
gws gmail +read --message-id <ID>
gws calendar +agenda --today            # also --tomorrow --week --days N --calendar --timezone
gws drive +upload ./report.pdf --name 'Q1 Report' --parent <FOLDER_ID>
gws sheets +read --spreadsheet <ID> --range 'Sheet1!A1:C10'
gws sheets +append --spreadsheet <ID> --range 'Sheet1!A1' --values 'Alice,95'
gws docs +write --document <ID> --text 'Appended line'
gws chat +send --space-id <ID> --text 'Deploy complete'
gws workflow +standup-report            # cross-service: today's meetings + open tasks
```

**Generic discovery commands** (full API coverage — anything a helper can't do):

```bash
gws drive files list --params '{"q": "name contains '\''report'\''", "pageSize": 20}'
gws drive files get  --params '{"fileId": "abc123", "fields": "id,name,mimeType"}'
gws gmail users messages list --params '{"userId": "me", "q": "is:unread"}'
gws sheets spreadsheets create --json '{"properties": {"title": "Q1 Budget"}}'
gws calendar events insert --params '{"calendarId": "primary"}' --json '{ ...event... }'
```

`--params` = URL / query / path params. `--json` = the request body (POST/PATCH/PUT).

## Key flags (generic commands)

- `--format <json|table|yaml|csv>` — output format (default `json`; use `table` for humans).
- `--page-all` — auto-paginate; emits one JSON object per page (NDJSON); pipe to `jq`.
  Tune with `--page-limit <N>` (default 10) and `--page-delay <MS>` (default 100).
- `--upload <PATH>` / `--output <PATH>` — media upload / binary download.
- `--dry-run` — validate the request locally; run this first for writes.

## Reference files

Read these as needed — do not load them all up front:

- **references/services.md** — every service, its resources, and the full list of
  `+` helper commands with their flags. Read when you need a command that isn't
  in the quick list above, or to confirm a helper's exact flags.
- **references/auth-and-config.md** — authentication setup (interactive, manual
  OAuth, service account, CI/token), all env vars, config file paths, exit codes,
  and Model Armor sanitization. Read when auth isn't set up, when running
  headless/in CI, or when a command fails with an auth error (exit code 2).

## First-run auth check

If a command fails with an auth error, run `gws auth status`. If `auth_method`
is `none`, authentication isn't configured — read references/auth-and-config.md
and guide the user through `gws auth login` (or `gws auth setup` if `gcloud` is
available). Never fabricate credentials or put secrets in commands.
