---
name: pgcli
description: >-
  Use pgcli (the autocompleting Postgres CLI, https://www.pgcli.com) as the tool for ALL
  PostgreSQL queries and interactions from the command line — running SQL, inspecting schemas
  (tables, columns, indexes, functions), exploring or debugging data, listing databases, and
  running migrations or ad-hoc DDL. Use whenever a task involves talking to a Postgres/Supabase
  database over a connection string, DSN, or PG* env vars via a terminal (not the tRPC/Prisma
  app layer). Covers non-interactive/scripted execution (pgcli has no -c or -f flag — it reads
  SQL from stdin), clean machine-parseable output, connection handling (URI, DSN aliases, pgpass,
  env vars), backslash meta-commands, and named queries.
---

# pgcli — Postgres from the command line

pgcli is a psql-compatible Postgres client with autocompletion and syntax highlighting.
Prefer it over raw `psql` for any command-line Postgres work. The one thing that trips
up automation: **pgcli has no `-c`/`--execute` and no `-f`/`--file` flag.** It runs
whatever SQL it reads from **stdin**, then exits at EOF.

## 0. Ensure pgcli is installed
```bash
command -v pgcli || pipx install pgcli || pip install pgcli   # macOS: brew install pgcli
```

## 1. Run a query non-interactively (the default for agent use)
**Always use the bundled wrapper `scripts/pgq.sh`.** Do NOT hand-roll `printf ... | pgcli`:
even when piped, pgcli renders its full REPL UI (prompt echoes, bottom toolbar, banners) to
stdout, burying the result. Getting clean output requires `TERM=dumb` + a sentinel prompt +
line filtering, which the wrapper handles.
```bash
# scripts/pgq.sh <connection> "<SQL>"  — connection = URI, db name, "-D alias", or flags
scripts/pgq.sh "postgresql://app:pw@localhost:5432/mydb" "SELECT id, email FROM users LIMIT 5;"
echo "SELECT count(*) FROM orders;" | scripts/pgq.sh mydb
scripts/pgq.sh "-D prod" < migration.sql          # whole file over stdin
PGQ_FORMAT=github scripts/pgq.sh mydb "SELECT * FROM plans;"   # markdown table instead of CSV
```
Output is clean CSV (every field quoted), e.g. `"id","email"` then one quoted row per record.

What the wrapper does and why (verified against pgcli 4.5.0):
- Pipes SQL over **stdin** — there is no `-c`/`-f`; pgcli runs stdin then exits at EOF.
- Sets **`TERM=dumb`** — without it, prompt-toolkit paints a toolbar and blank-line chrome
  onto stdout even when redirected to a file.
- Loads `assets/scripting.pgclirc`: `table_format=csv`, `timing=False`, `less_chatty=True`,
  `row_limit=0` (no "N rows, continue?" prompt that would hang/eat stdin),
  `use_local_timezone=False`, `keyring=False`.
- Uses a sentinel `--prompt` and greps out the echoed-query/prompt/status-tag lines.

**Error handling gotcha:** a *SQL* error (bad table, syntax) prints inline to stdout **and
pgcli still exits 0** — inspect the output for `does not exist` / `syntax error`; do not trust
`$?` for SQL validity. A *connection* failure prints to stderr and exits non-zero.

For writes/DDL, don't reuse the read-optimized config blindly — see Safety below.

## 2. Connecting
```bash
pgcli mydb                                       # db name; host/user/password from PG* env / pgpass
pgcli postgresql://user:pw@host:5432/mydb        # URI (percent-encode special chars, quote it)
pgcli -h localhost -U app -d mydb                # explicit flags
pgcli -D prod                                    # DSN alias from [alias_dsn] in the config
pgcli --ping -D prod                             # connectivity check only, then exit
```
Keep secrets out of the command line: prefer `~/.pgpass`, `PG*` env vars, or `-D` aliases.
Full flag list, DSN aliases, pgpass, SSL, and env vars: **references/config-and-cli.md**.

## 3. Inspect the schema
Backslash meta-commands, same as psql. Run them through the wrapper for clean output
(they behave like queries — a bare `pgcli mydb <<< '\dt'` shows REPL chrome):
```bash
scripts/pgq.sh mydb '\dt'              # list tables
scripts/pgq.sh mydb '\d public.users'  # describe a table (columns, types, indexes, FKs)
scripts/pgq.sh mydb '\df'              # list functions
scripts/pgq.sh mydb '\l'               # list databases
```
(For a human at the keyboard, just run `pgcli mydb` and type these interactively — that's
where pgcli's autocompletion and highlighting shine.)
Common ones: `\dt` tables · `\d NAME` describe · `\dn` schemas · `\di` indexes · `\dv`
views · `\du` roles · `\dx` extensions · `\sf FUNC` show function · `\h SELECT` SQL help.
Full meta-command catalog (inspection, output formats, `\copy`, `\watch`, `\i`, `\o`):
**references/special-commands.md**.

## 4. Reusable named queries
Save frequently-used SQL in the config's `[named queries]` section and run with `\n NAME
[args]` (`$1`, `$2` placeholders). Manage live with `\ns` (save) / `\nd` (delete) / `\n+`
(list). Details in references/config-and-cli.md.

## Safety
- **Read vs write.** The CSV scripting config disables destructive warnings for frictionless
  reads. For `DELETE`/`UPDATE`/`DROP`/`ALTER`/`TRUNCATE`, do NOT reuse it blindly — run
  through plain `pgcli` (which prompts on destructive statements per `destructive_warning`),
  or scope changes in a transaction: pipe `BEGIN; …; COMMIT;` and inspect before committing.
- **Confirm the target DB** before writes — check `\conninfo`; never assume prod vs local.
- **`--row-limit 0`** only disables the prompt, not a real limit; add `LIMIT` to exploratory
  `SELECT`s so you don't stream millions of rows.
- **Never inline passwords** in commands that get logged; use pgpass / env / DSN aliases.

## Files in this skill
- `scripts/pgq.sh` — run one-off SQL/scripts via stdin with clean CSV output (`PGQ_FORMAT`,
  `PGQ_RC` env overrides).
- `assets/scripting.pgclirc` — minimal config for machine-parseable, non-blocking output.
- `references/special-commands.md` — every backslash meta-command.
- `references/config-and-cli.md` — all CLI flags, config keys, connection/DSN/pgpass/env.
