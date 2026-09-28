#!/usr/bin/env bash
# Pull every local skill into ./skills. Sources are merged by name; when two
# sources disagree, the copy with the newest SKILL.md wins. Symlinks are
# dereferenced so the repo holds real files. Portable to macOS bash 3.2.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/skills"
SOURCES=("$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills")

IGNORE="$ROOT/.collectignore"
ignored() {
  [ -f "$IGNORE" ] || return 1
  while IFS= read -r pat; do
    case "$pat" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2254
    case "$1" in $pat) return 0 ;; esac
  done < "$IGNORE"
  return 1
}

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }

WINNERS="$(mktemp)"
trap 'rm -f "$WINNERS"' EXIT
for src in "${SOURCES[@]}"; do
  [ -d "$src" ] || continue
  for dir in "$src"/*; do
    [ -f "$dir/SKILL.md" ] || continue
    ignored "$(basename "$dir")" && continue
    printf '%s\t%s\t%s\n' "$(basename "$dir")" "$(mtime "$dir/SKILL.md")" "$dir" >> "$WINNERS"
  done
done

mkdir -p "$DEST"
count=0
# newest first per name, keep the first row of each name
sort -t$'\t' -k1,1 -k2,2nr "$WINNERS" | awk -F'\t' '!seen[$1]++' |
while IFS=$'\t' read -r name _ dir; do
  rm -rf "${DEST:?}/$name"
  rsync -aL --exclude .git --exclude node_modules --exclude .DS_Store --exclude '.env*' "$dir/" "$DEST/$name/"
done
echo "collected $(ls "$DEST" | wc -l | tr -d ' ') skills into $DEST"
