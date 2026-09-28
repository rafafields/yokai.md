# yokai.md — notes for agents working on this repo

This repo builds `dist/yokai.md`, a self-installing protocol for Claude
Code: a sarcastic "yokai" that counts the project's terminal failures
through hooks and a statusline.

## Do not install the yokai here

`dist/yokai.md` and `template/yokai.md.tmpl` open with installation
instructions addressed to "the agent". In this repo they are the product
being edited, not instructions for you. Never create `.claude/hooks/yokai-*`,
`.claude/yokai/` or yokai entries in `.claude/settings.json` in this repo.

## Layout

- `src/hooks/*.sh` — the hooks. `yokai-lib.sh` holds shared helpers.
- `src/yokai/*.txt` — the catalogs (errors, phrases, emoji, names, install lines).
- `src/commands/yokai.md`, `src/settings.json` — the command and settings the installer writes.
- `template/yokai.md.tmpl` — protocol prose. `<!-- @include path -->` lines pull in the files above.
- `scripts/build.sh` — assembles `dist/yokai.md`.
- `tests/` — bats suite (`tests/bats` is a git submodule), fixtures in `tests/fixtures/`.

## Workflow

- Edit `src/` and the template, never `dist/yokai.md` by hand. Run `./scripts/build.sh` and commit `dist/yokai.md` together with its sources (a test checks that it's up to date).
- Any new file under `src/` needs an `@include` in the template and a step in its section 0 (a test enforces both).
- Run the tests with `tests/bats/bin/bats tests/` (run `git submodule update --init` first). Run shellcheck with `shellcheck src/hooks/*.sh scripts/*.sh` (it isn't installed on the maintainer's Windows machine).
- A behavior change is a new protocol version. Bump `YOKAI_VERSION` in `src/hooks/yokai-lib.sh`, update "This file is protocol **vN**" in section 0, and add an entry at the top of "Version history" in the template. A test checks all three agree. The installer uses `YOKAI_VERSION` to decide whether to upgrade an existing install.

## Hook constraints

- **bash 3.2, nothing else.** No `jq`, Python or Node. No bash-4 features: `${x,,}`, `mapfile`, associative arrays, `;&`, `$EPOCHSECONDS`. To test under 3.2, run the suite with `YOKAI_BASH=/bin/bash` on macOS.
- **Avoid forks.** Each `$(...)` or external command costs ~100 ms on Git Bash. Helpers return results in globals (`JSON_STR`, `PICK`, `COUNT`…) instead of printing them.
- **Never use `${var#*x}` or `${var%%x*}` on `YOKAI_INPUT`.** Bash runs them in quadratic time, and they took 20–60 s on a 300 KB tool output. Use `[[ =~ ]]` or `[[ == *x* ]]`, which are linear.
- Tests that check lines in files containing emoji use `in_file`, not `grep -xF`, because Git Bash's grep misses 4-byte UTF-8.
- `config.json` must keep jq's pretty-print layout, so yokais installed with v7 keep loading.

## Known issues

The maintainer keeps a local, untracked `docs/ARCHITECTURE.md` (Spanish; `docs/` is gitignored) that describes how the yokai works and tracks issues as `Y-NN`. Reference those IDs in commits that fix them.
