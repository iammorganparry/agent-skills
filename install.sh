#!/usr/bin/env bash
# Symlink every skill in ./skills into each agent's skills directory, so a
# `git pull` here updates Claude Code, Codex, Pi and the `skills` CLI at once.
#
#   ./install.sh           link, skipping names that already exist as real dirs
#   ./install.sh --force   move conflicting real dirs to ~/.agent-skills-backup/<ts>/ first
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
FORCE=0; [ "${1:-}" = "--force" ] && FORCE=1
TARGETS=("$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.pi/agent/skills")
BACKUP="$HOME/.agent-skills-backup/$(date +%Y%m%d-%H%M%S)"

linked=0; skipped=0
for target in "${TARGETS[@]}"; do
  mkdir -p "$target"
  for skill in "$ROOT"/skills/*/; do
    name="$(basename "$skill")"
    dest="$target/$name"
    if [ -L "$dest" ] || [ ! -e "$dest" ]; then
      ln -sfn "${skill%/}" "$dest"; linked=$((linked + 1))
    elif [ "$FORCE" = 1 ]; then
      mkdir -p "$BACKUP/$(basename "$(dirname "$target")")"
      mv "$dest" "$BACKUP/$(basename "$(dirname "$target")")/$name"
      ln -s "${skill%/}" "$dest"; linked=$((linked + 1))
    else
      echo "skip $dest (real dir exists; rerun with --force to replace)"; skipped=$((skipped + 1))
    fi
  done
done
echo "linked $linked, skipped $skipped"
[ -d "$BACKUP" ] && echo "backups in $BACKUP"
exit 0
