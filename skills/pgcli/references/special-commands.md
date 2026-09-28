# pgcli special (backslash) commands

Meta-commands typed at the pgcli prompt (or piped over stdin). Most mirror psql.
`[+]` = add a verbose/detail variant. `[pattern]` = optional name pattern (supports
`*`/`?` wildcards and `schema.name`). Run `\?` inside pgcli for the live list.

## Table of contents
- [Inspecting the schema](#inspecting-the-schema)
- [Output format & display](#output-format--display)
- [Files & data transfer](#files--data-transfer)
- [Named (saved) queries](#named-saved-queries)
- [Session, timing & shell](#session-timing--shell)

## Inspecting the schema
| Command | Description |
|---|---|
| `\l[+] [pattern]` | List databases |
| `\d[+] [pattern]` | Describe a table/view/sequence, or list relations if no pattern |
| `\dt[+] [pattern]` | List tables |
| `\dv[+] [pattern]` | List views |
| `\dm[+] [pattern]` | List materialized views |
| `\di[+] [pattern]` | List indexes |
| `\ds[+] [pattern]` | List sequences |
| `\dn[+] [pattern]` | List schemas |
| `\du[+] [pattern]` | List roles/users |
| `\df[+] [pattern]` | List functions |
| `\dp [pattern]` / `\z` | List table access privileges |
| `\ddp [pattern]` | List default access privileges |
| `\dD[+] [pattern]` | List domains |
| `\dT[S+] [pattern]` | List data types |
| `\dE[+] [pattern]` | List foreign tables |
| `\dx[+] [pattern]` | List installed extensions |
| `\db[+] [pattern]` | List tablespaces |
| `\dF[+] [pattern]` | List text-search configurations |
| `\sf[+] FUNCNAME` | Show a function's definition |
| `\h [TOPIC]` | SQL syntax help (e.g. `\h SELECT`) |
| `\conninfo` | Show current connection details |

Tip: `\dt *.*` lists tables across every schema; `\d public.users` describes one table.

## Output format & display
| Command | Description |
|---|---|
| `\T [format]` | Set table output format (see list below). No arg shows current. |
| `\x` | Toggle expanded (one-column-per-line) output |
| `\x auto` | Expand only when a row is wider than the terminal |
| `\pset [key] [value]` | Adjust display settings (limited subset of psql's `\pset`) |
| `\pager [command]` | Set/toggle the pager program |
| `\timing` | Toggle showing statement execution time |

`\T` formats: `psql plain simple grid fancy_grid pipe ascii double github orgtbl rst
mediawiki html latex latex_booktabs textile moinmoin jira vertical tsv csv sql-insert
sql-update`. Use `csv`/`tsv` for machine parsing, `github` for pasting into markdown.

## Files & data transfer
| Command | Description |
|---|---|
| `\i FILENAME` | Execute SQL from a file |
| `\o [FILENAME]` | Redirect query results to a file (no arg = back to stdout) |
| `\e [FILE]` | Open the last query (or FILE) in `$EDITOR`, run on save |
| `\copy TABLE FROM/TO FILENAME` | Client-side COPY between a file and a table |
| `\log-file [FILENAME]` | Log results to a file |

## Named (saved) queries
Stored in the `[named queries]` section of your pgclirc, reusable across sessions.
| Command | Description |
|---|---|
| `\ns NAME QUERY` | Save `QUERY` under `NAME` |
| `\n[+]` | List all saved named queries (`+` shows the SQL) |
| `\n NAME [p1 p2 ...]` | Run a saved query; positional args fill `$1`, `$2`, … placeholders |
| `\np NAME` | Print a named query without running it |
| `\nd NAME` | Delete a named query |

Example: `\ns act "SELECT * FROM users WHERE status='$1'"` then `\n act active`.

## Session, timing & shell
| Command | Description |
|---|---|
| `\watch [SECONDS]` | Re-run the previous query every N seconds (default 2) |
| `\! [COMMAND]` | Run a shell command |
| `\refresh` / `\#` | Refresh autocompletion metadata (after schema changes) |
| `\c[onnect] DBNAME` | Switch to another database |
| `\echo TEXT` / `\qecho TEXT` | Print text to stdout / query output channel |
| `\?` | List all special commands |
| `\q` (or Ctrl-D) | Quit |
