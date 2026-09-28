# yokai.md

A bad-luck yokai for [Claude Code](https://claude.com/claude-code) that
moves into your project and feeds on your terminal failures. It counts
every failed Bash command, sorts it by category, and shows its tally in the
status bar with no enthusiasm whatsoever. If the project stops failing for
7 days, it leaves on its own, and that's good news.

```
👺 Kage-oni  Console fails: 12 · Yokai HP: 1.5K
```

Everything runs in hooks and the statusline, so it costs no tokens. The
model only hears about the yokai when you type `/yokai …`.

## Install

1. Copy [`dist/yokai.md`](dist/yokai.md) into your project.
2. Ask Claude Code to read it. The file installs itself: it writes
   `.claude/hooks/`, `.claude/yokai/` and `.claude/commands/yokai.md`, and
   merges its hooks and statusline into `.claude/settings.json`.
3. Start a new session (hooks only load at startup) and run `/yokai summon`.

Requirements: bash 3.2+. On Windows, that's the Git Bash Claude Code
already uses. No `jq`, Python or Node.

Commands: `/yokai summon` · `/yokai report` · `/yokai forget` · `/yokai help`.

Upgrading from v7: have Claude Code read the new `dist/yokai.md`. Section 0
explains how to replace the old install and keep your yokai.

## Development

`dist/yokai.md` is generated. Edit the files in `src/` and the prose in
`template/yokai.md.tmpl`, then:

```bash
./scripts/build.sh                    # regenerate dist/yokai.md
git submodule update --init           # first time: fetch bats
tests/bats/bin/bats tests/            # run the test suite
shellcheck src/hooks/*.sh scripts/*.sh
```

Version history lives at the end of the protocol itself.
