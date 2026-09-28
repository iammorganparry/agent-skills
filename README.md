# agent-skills

General-purpose coding skills for AI agents: one repo, linked into Claude Code, Codex, Pi and the `skills` CLI.

## New machine

```bash
git clone https://github.com/iammorganparry/agent-skills ~/repos/agent-skills
cd ~/repos/agent-skills
./install.sh            # add --force to replace existing real skill dirs (backed up first)
```

Skills are symlinked into `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`
and `~/.pi/agent/skills`. Edit a skill anywhere and it edits it here.

## Staying in sync

```bash
git pull                 # get changes from the other laptop
./scripts/collect.sh     # pull newly installed local skills into the repo (existing ones untouched)
git add -A && git commit -m "skills: sync" && git push
```

The repo is the source of truth: edit skills here (or through the symlinks
`install.sh` creates). `collect.sh --refresh` overwrites repo copies from local ones.

`collect.sh` merges `~/.agents/skills`, `~/.claude/skills` and `~/.codex/skills`
by name; where copies differ, the newest `SKILL.md` wins. Names in `.collectignore`
(company-specific or product-vendor skills) are never imported.

## Other ways in

- One skill: `npx skills add iammorganparry/agent-skills --skill tdd`
- Jingler: Settings › Skills imports from `~/.pi/agent/skills`.

Some skills are vendored from third parties (Cloudflare, Firecrawl, Runpod,
Vercel, …); they remain under their original licences.
