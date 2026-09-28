#!/usr/bin/env bash
#
# pgq.sh — run a single SQL statement (or a whole script) through pgcli
# non-interactively and emit clean, parseable output (CSV by default).
#
# WHY THIS EXISTS: pgcli is a REPL with no -c/--execute or -f/--file flag. It
# executes whatever it reads from stdin, then exits at EOF — but by default it
# also renders its full prompt-toolkit UI (prompt echoes, bottom toolbar,
# banners) to stdout, burying the actual result. This wrapper makes the output
# clean and deterministic by:
#   * TERM=dumb                -> disables the toolbar / cursor / blank-line chrome
#   * assets/scripting.pgclirc -> csv format, no timing, no banners, no row/destructive prompts
#   * a sentinel --prompt      -> lets us grep the echoed-query/prompt lines back out
#   * a status-tag filter      -> strips trailing "SELECT 3" / "UPDATE 1" command tags
#
# Usage:
#   pgq.sh <connection> "SELECT * FROM users LIMIT 5;"
#   echo "SELECT 1;"        | pgq.sh <connection>
#   pgq.sh <connection> < migration.sql
#
# <connection> is passed to pgcli verbatim and WORD-SPLIT on purpose, so it may be:
#   - a URI:          "postgresql://user:pass@host:5432/dbname"
#   - a db name:      mydb            (rest from PG* env vars / ~/.pgpass)
#   - a DSN alias:    "-D prod"       (from [alias_dsn] in your pgclirc)
#   - explicit flags: "-h localhost -U app -d mydb"
#
# Env overrides:
#   PGQ_FORMAT=tsv|github|psql|plain|vertical|...   output table_format (default: csv)
#   PGQ_RC=/path/to/rc                              use a different base pgclirc
#
# Notes / limits:
#   * SQL errors print inline to stdout AND pgcli still exits 0 (REPL behaviour) —
#     check the output for 'does not exist' / 'syntax error', don't trust $? for SQL.
#   * Connection failures print to stderr and exit non-zero.
#   * The status-tag filter is safe for the default CSV format (data rows are quoted).
#     For unquoted formats (tsv/plain) a data row that looks exactly like a command
#     tag could be stripped — use PGQ_FORMAT=csv when parsing matters.
set -uo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: pgq.sh <connection> [\"SQL\"]   (SQL via arg or stdin)" >&2
  exit 2
fi

conn="$1"; shift
if [ "$#" -gt 0 ]; then sql="$*"; else sql="$(cat)"; fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc="${PGQ_RC:-$script_dir/../assets/scripting.pgclirc}"
fmt="${PGQ_FORMAT:-csv}"
mark='__PGQ_PROMPT__> '

# \T sets the format inline so PGQ_FORMAT works without editing the rc.
# shellcheck disable=SC2086  # $conn is intentionally word-split into pgcli args.
printf '\\T %s\n%s\n' "$fmt" "$sql" \
  | TERM=dumb pgcli --pgclirc "$rc" --prompt "$mark" $conn \
      2> >(grep -v 'Input is not a terminal' >&2) \
  | grep -v -F "$mark" \
  | grep -vxE '(SELECT|INSERT|UPDATE|DELETE|COPY|CREATE|DROP|ALTER|BEGIN|COMMIT|ROLLBACK|TRUNCATE|GRANT|REVOKE|SET|SHOW|COMMENT|EXPLAIN|VACUUM|ANALYZE|REINDEX|REFRESH|CALL|DO|LISTEN|NOTIFY|Changed table format to .*)( [0-9]+)*[[:space:]]*'
