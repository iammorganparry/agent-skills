# `gws` Services & Helper Reference

Table of contents:
- [How to introspect anything](#how-to-introspect-anything)
- [Service list](#service-list)
- [`+` helper commands (per service)](#-helper-commands-per-service)
- [Generic command patterns](#generic-command-patterns)

## How to introspect anything

Whenever a service/method/param is unknown, ask the CLI rather than guessing:

```bash
gws --help                              # top-level: all services + global flags
gws <service> --help                    # resources + helpers for a service
gws <service> <resource> --help         # methods on a resource (list/get/create/...)
gws <service> <resource> <method> --help
gws schema <service.resource.method>    # exact JSON param + body schema
gws schema drive.files.list --resolve-refs   # inline $ref'd sub-schemas
```

`schema` output is the source of truth for `--params` keys and `--json` body
shape. Method names follow the Google API (`list`, `get`, `create`, `insert`,
`update`, `patch`, `delete`, `batchUpdate`, etc.).

## Service list

| Service | Aliases | Purpose |
|---|---|---|
| `drive` | | Files, folders, shared drives, permissions, comments, revisions |
| `sheets` | | Read/write spreadsheets |
| `gmail` | | Send, read, manage email, labels, threads |
| `calendar` | | Calendars, events, ACLs, free/busy |
| `docs` | | Read/write Google Docs |
| `slides` | | Read/write presentations |
| `tasks` | | Task lists and tasks |
| `people` | | Contacts and profiles |
| `chat` | | Chat spaces, messages, members |
| `classroom` | | Classes, rosters, coursework |
| `forms` | | Read/write Google Forms |
| `keep` | | Google Keep notes |
| `meet` | | Google Meet conferences |
| `admin-reports` | `reports` | Audit logs and usage reports |
| `events` | | Subscribe to Workspace events |
| `script` | | Apps Script projects |
| `modelarmor` | | Filter user-generated content for safety |
| `workflow` | `wf` | Cross-service productivity workflows |

## `+` helper commands (per service)

Helpers are curated wrappers. Always check `gws <service> +<helper> --help` for
the authoritative flag list — the ones below are the common ones.

### gmail
- `+send  --to <emails> --subject <s> --body <text>` — extras: `--html`,
  `-a/--attach <path>` (repeatable), `--cc`, `--bcc`, `--from <alias>`, `--draft`.
- `+triage` — unread inbox summary (sender, subject, date).
- `+reply     --message-id <id> --body <text>` — auto-handles threading.
- `+reply-all --message-id <id> --body <text>`
- `+forward   --message-id <id> --to <emails>`
- `+read      --message-id <id>` — extract body/headers.
- `+watch` — stream new emails as NDJSON.

### calendar
- `+agenda` — flags: `--today`, `--tomorrow`, `--week`, `--days <N>`,
  `--calendar <name|id>`, `--timezone <IANA>`.
- `+insert` — create an event (see `--help` for flags).

### drive
- `+upload <file>` — flags: `--name <name>`, `--parent <folderId>`. Auto metadata.

### sheets
- `+read   --spreadsheet <id> --range 'Sheet1!A1:B2'`
- `+append --spreadsheet <id> --range <range> --values 'a,b,c'`

### docs
- `+write --document <id> --text <text>` — append text.

### chat
- `+send --space-id <id> --text <msg>`

### workflow (cross-service)
- `+standup-report` — today's meetings + open tasks as a standup summary.
- `+meeting-prep` — next meeting: agenda, attendees, linked docs.
- `+email-to-task` — convert a Gmail message into a Tasks entry.
- `+weekly-digest` — this week's meetings + unread email count.
- `+file-announce` — announce a Drive file in a Chat space.

## Generic command patterns

Resources per service (from `gws <service> --help`) — use with `list/get/create/...`:

- **drive**: `files`, `drives`, `permissions`, `comments`, `replies`,
  `revisions`, `changes`, `about`, `apps`.
  - `gws drive files list --params '{"q":"mimeType='\''application/vnd.google-apps.folder'\''","fields":"files(id,name)"}'`
  - `gws drive permissions create --params '{"fileId":"<id>"}' --json '{"role":"reader","type":"user","emailAddress":"a@x.com"}'`
- **gmail**: everything lives under `users` → `messages`, `threads`, `labels`,
  `drafts`, `settings`. `userId` is almost always `"me"`.
  - `gws gmail users messages list --params '{"userId":"me","q":"is:unread newer_than:7d"}'`
  - `gws gmail users messages get  --params '{"userId":"me","id":"<msgId>","format":"full"}'`
- **sheets**: `spreadsheets` (+ `values` batch ops via `batchUpdate`).
  - `gws sheets spreadsheets values get --params '{"spreadsheetId":"<id>","range":"A1:C10"}'`
- **calendar**: `events`, `calendars`, `calendarList`, `acl`, `freebusy`, `settings`, `colors`.
  - `gws calendar events list --params '{"calendarId":"primary","timeMin":"2026-07-01T00:00:00Z","singleEvents":true,"orderBy":"startTime"}'`
- **docs**: `documents` — read with `get`, edit with `batchUpdate`.
- **slides**: `presentations` — read with `get`, edit with `batchUpdate`.
- **tasks**: `tasklists`, `tasks`.
  - `gws tasks tasks insert --params '{"tasklist":"@default"}' --json '{"title":"Follow up"}'`
- **people**: `people`, `contactGroups`, `otherContacts`.
  - `gws people people get --params '{"resourceName":"people/me","personFields":"names,emailAddresses"}'`
- **chat**: `spaces` (→ `messages`, `members`), `media`, `users`, `customEmojis`.

Large `list` results: append `--page-all | jq '.files[]?'` (NDJSON, one page per line).
