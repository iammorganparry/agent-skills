# pgcli CLI flags, config, and connection reference

## Table of contents
- [Command-line flags](#command-line-flags)
- [Connecting](#connecting)
- [DSN aliases (-D)](#dsn-aliases--d)
- [Passwords: pgpass & env vars](#passwords-pgpass--env-vars)
- [Config file (~/.config/pgcli/config)](#config-file-configpgcliconfig)
- [Named queries in config](#named-queries-in-config)

## Command-line flags
There is **no `-c`/`--execute` and no `-f`/`--file`** — see SKILL.md for how to run
queries non-interactively (pipe over stdin). Full flag list:

| Flag | Description |
|---|---|
| `-h, --host TEXT` | Database host address |
| `-p, --port INTEGER` | Port (default 5432) |
| `-U, --username` / `-u, --user TEXT` | Username |
| `-W, --password` | Force a password prompt |
| `-w, --no-password` | Never prompt for a password (fail instead of hanging) |
| `-d, --dbname TEXT` | Database name |
| `-D, --dsn TEXT` | Use a DSN alias from the `[alias_dsn]` config section |
| `--list-dsn` | List configured DSN aliases and exit |
| `-l, --list` | List databases and exit |
| `--ping` | Check connectivity and exit (exit code reflects reachability) |
| `--pgclirc PATH` | Use an alternate config file |
| `--row-limit INTEGER` | Row-count threshold before the confirmation prompt; `0` disables |
| `--warn [all\|moderate\|off]` | Destructive-query warning level |
| `--less-chatty` | Skip the intro banner and goodbye line |
| `--auto-vertical-output` | Auto-switch to expanded output when rows exceed terminal width |
| `--single-connection` | Don't open a second connection for autocompletion |
| `--init-command TEXT` | SQL to run immediately after connecting (then stay interactive) |
| `--log-file TEXT` | Write queries and their output to a log file |
| `--application-name TEXT` | Sets `application_name` on the connection |
| `--ssh-tunnel ADDR` | Open an SSH tunnel to reach the DB |
| `--prompt TEXT` | Prompt format (default `\u@\h:\d> `) |
| `-v, --version` | Print version |
| `--help` | Show help |

Prompt escapes for `--prompt`: `\u` user, `\h` host, `\d` database, `\n` newline,
`\p` port, `\#` `#`/`>` for super/normal user, `\T` transaction status.

## Connecting
```bash
pgcli mydb                                            # db name; rest from PG* env vars
pgcli -h localhost -p 5432 -U app -d mydb             # explicit flags
pgcli postgresql://app:s3cret@localhost:5432/mydb     # URI
pgcli 'postgresql://app:%40pw@host:5432/mydb?sslmode=require'   # URL-encode special chars, quote the URI
pgcli service=prod                                    # a service from ~/.pg_service.conf
```
Special characters in a password inside a URI must be percent-encoded (`@` → `%40`,
`:` → `%3A`). SSL params go in the query string (`sslmode`, `sslrootcert`, `sslcert`,
`sslkey`) or via `PGSSLMODE` etc.

## DSN aliases (-D)
Define reusable connection strings so secrets/hosts stay out of the command line:
```ini
[alias_dsn]
prod    = postgresql://app:s3cret@prod-db.internal:5432/appdb?sslmode=require
local   = postgresql://postgres@localhost:5432/appdb
```
Then: `pgcli -D prod`. List them with `--list-dsn`.

## Passwords: pgpass & env vars
Avoid inline passwords. pgcli honors libpq mechanisms:
- **`~/.pgpass`** — lines of `hostname:port:database:username:password` (chmod `600`).
- **Env vars** — `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`,
  `PGSSLMODE`, `PGSSLCERT`, `PGSSLKEY`, `PGSSLROOTCERT`, `PGSERVICE`.
- **`~/.pg_service.conf`** — named connection services, used via `service=NAME`.

## Config file (~/.config/pgcli/config)
Auto-created on first run. Settings live under `[main]`. Most useful keys:

| Key | Default | Notes |
|---|---|---|
| `table_format` | `psql` | Output style. `csv`/`tsv` for parsing; also `github`, `grid`, `plain`, `vertical`, `sql-insert`, `html`, `latex`, … |
| `syntax_style` | `default` | Pygments color theme (`monokai`, `native`, `vs`, …) |
| `row_limit` | `1000` | Prompt threshold for large results; `0` disables (essential for scripting) |
| `destructive_warning` | `drop, shutdown, delete, truncate, alter, update, unconditional_update` | Statement types that trigger a confirm prompt; empty string disables all |
| `expand` | `False` | Always use expanded output |
| `auto_expand` | `False` | Expand only when wider than terminal |
| `less_chatty` | `False` | Skip banner/goodbye |
| `timing` | `True` | Show `Time: …` after each statement |
| `multi_line` | `False` | If `True`, Enter never submits; statements end on `;` |
| `on_error` | `STOP` | `STOP` or `RESUME` when a multi-statement batch hits an error |
| `null_string` | `<null>` | How NULLs render |
| `keyword_casing` | `auto` | `auto`/`lower`/`upper` for autocompleted keywords |
| `pager` | `$PAGER` | Pager program; auto-disabled when stdout isn't a TTY |
| `keyring` | `True` | Store passwords in the OS keyring |

Other sections: `[colors]` (prompt-toolkit token colors), `[data_formats]`,
`[alias_dsn]`, `[named queries]`.

## Named queries in config
```ini
[named queries]
biggest_tables = SELECT schemaname, relname, pg_size_pretty(pg_total_relation_size(relid)) AS size FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;
active_users = SELECT count(*) FROM users WHERE status = '$1';
```
Run with `\n biggest_tables` or `\n active_users active`. Manage interactively with
`\ns` (save), `\nd` (delete), `\n+` (list with SQL).
