---
name: mole
description: >-
  Clean up and free disk space on this Mac using the mole CLI (tw93/mole, binary
  `mo`) — reclaim caches, logs, build artifacts, and app leftovers; analyze where
  space is going; uninstall apps cleanly. Use when the user asks to clean their
  Mac, free/reclaim disk space, fix a full disk / "no space left on device"
  (ENOSPC), find what is eating storage, purge node_modules/build artifacts, or
  uninstall an app with all its remnants. Encodes which mole commands can run
  headlessly vs. which the user must run interactively, and how to avoid deleting
  agent/session data (jingler, .claude, .codex).
---

# Mole — Mac cleanup

Mole is an all-in-one macOS maintenance CLI (like CleanMyMac + AppCleaner +
DaisyDisk in one binary). It is already installed on this machine: `mo` and
`mole` at `/opt/homebrew/bin` (install with `brew install mole` if missing;
needs macOS 14+). `mo` is the primary command.

## Critical gotcha: most mole commands are interactive TUIs

`mo clean`, `mo purge`, `mo uninstall`, `mo installer`, and `mo optimize`
launch a full-screen selection UI and **block waiting for keyboard input**.
They **HANG when run through a non-interactive shell** (the Bash tool) — even
with `--dry-run`, and even piped to `cat`. Do **not** run them yourself; they
time out and get backgrounded with no output.

**Hand these to the user to run in their own terminal.** Tell them to type, in
the Claude Code prompt, with the leading `!`:

```
! mo clean
```

The `!` prefix runs it in the session's real terminal so its output returns to
the conversation. Or the user runs `mo clean` directly in any Terminal tab.

## What YOU can run headlessly (safe from the Bash tool)

These produce output without a TUI and are safe to run directly:

```bash
mo status --json                # system health dashboard as JSON
mo analyze --json ~/some/path   # disk usage tree for a path, as JSON
mo --version
```

Use `mo analyze --json <path>` to quantify where space is going before
recommending a clean. The interactive `mo analyze` moves files to Trash rather
than hard-deleting — safer than direct removal.

## What mole cleans (by command)

- `mo clean` — user/browser/dev caches, system logs, temp files, Trash, and
  leftovers from already-uninstalled apps. The everyday reclaim.
- `mo purge` — project build artifacts: `node_modules`, `target`, `.build`,
  `build`, `dist`, `venv`. Default scan roots: `~/Projects`, `~/GitHub`, `~/dev`
  (configure via `mo purge --paths` or `~/.config/mole/purge_paths`). Projects
  touched in the last 7 days are unselected by default.
- `mo uninstall` — remove an app plus Application Support, caches, prefs, logs,
  WebKit storage, cookies, launch daemons.
- `mo installer` — find and remove large installer files (Downloads, Desktop,
  Homebrew cache, etc.).
- `mo optimize` — refresh caches and system services.

## Safety — protect agent/session data

Never let a clean touch coding-agent memory, config, or live session data.

**Whitelist** persists in `~/.config/mole/whitelist`, edited via
`mo clean --whitelist`. This machine already protects:

```
/Users/morganparry/.claude
/Users/morganparry/.codex
/Users/morganparry/repos/trigify-app/.claude
/Users/morganparry/repos/trigify-app/.codex
```

Before recommending a clean, confirm the whitelist still covers `.claude` and
`.codex`. Add any new agent-data paths the same way.

**Jingler data lives in `~/jingler` and is NOT a cache — never purge it.**
Especially `~/jingler/worktrees` (git worktrees for live sessions, often tens of
GB) holds uncommitted work. `mo clean`/`mo purge` do not target `~/jingler` by
default; keep it that way. If worktrees are the disk hog, that is Jingler
housekeeping (remove stale sessions from within Jingler), not a mole job.

## When the disk is critically full

Order of operations for "no space left on device" on this Mac:

1. **Reclaim regenerable caches first (headless, high-confidence safe):**
   ```bash
   pnpm store prune          # usually the biggest win here (10GB+ seen)
   npm cache clean --force
   brew cleanup -s
   ```
2. Have the user run `! mo clean` for the deep pass (caches/logs/leftovers).
3. `mo analyze --json ~` (or a suspected subtree) to find remaining hogs.
4. Surface large user-data hogs (e.g. `~/jingler/worktrees`) to the user for a
   decision — do not auto-delete them.

## Other commands

`mo` (menu) · `mo history` / `mo history --json` (operation log at
`~/Library/Logs/mole/operations.log`; disable logging with `MO_NO_OPLOG=1`) ·
`mo touchid` (Touch ID for sudo) · `mo completion` · `mo update` · `mo remove`.
