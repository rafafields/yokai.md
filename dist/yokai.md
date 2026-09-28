# yokai.md — self-installing protocol

> A bad-luck yokai that moves into your project and feeds on your terminal
> failures — not on conversation. It's not a pet to take care of: it's the
> opposite. If the project stops failing as much, it leaves on its own,
> and that's good news. This file is the whole protocol — it self-installs
> the first time an agent reads it.
>
> Tone: dry, sarcastic, no enthusiasm whatsoever. Think "congratulations,
> you really did that". See version history at the end.

---

## 0. Installation (read this first, agent)

Requirements: `bash` (3.2 or newer — macOS's stock bash is fine; on
Windows, the Git Bash that Claude Code already uses) and nothing else. No
`jq`, Python or Node.

This file is protocol **v9**. If `.claude/hooks/yokai-sessionstart.sh`
already exists, find the installed version: the `YOKAI_VERSION=` line in
`.claude/hooks/yokai-lib.sh` (no such line, or no such file, means v8 or
older). If it's lower than 9, upgrade: delete `.claude/hooks/yokai-*.sh`
and everything in `.claude/yokai/` except `config.json` and
`statusline_next` (the yokai itself, which v9 reads as-is, and the status
line it chains), remove the hook entries whose command mentions `yokai-`
from `.claude/settings.json`, then install as below.

If `.claude/hooks/yokai-sessionstart.sh` does **not** exist (or you just
cleared an old version):

1. Create `.claude/commands/yokai.md` with the exact contents of section 8.1 (registers `/yokai summon|forget|report|help`).
2. Create these five hook files with the exact contents of their sections, and make the first four executable (`chmod +x`):
   - `.claude/hooks/yokai-sessionstart.sh` (section 8.2)
   - `.claude/hooks/yokai-userprompt.sh` (section 8.3)
   - `.claude/hooks/yokai-posttooluse.sh` (section 8.4)
   - `.claude/hooks/yokai-statusline.sh` (section 8.5)
   - `.claude/hooks/yokai-lib.sh` (section 8.6 — shared helpers, sourced by the other four)
3. Create `.claude/yokai/errors.txt` with the exact contents of section 8.7.
4. Create `.claude/yokai/phrases.txt` with the exact contents of section 8.8.
5. Create `.claude/yokai/install_lines.txt` with the exact contents of section 8.9.
6. Create `.claude/yokai/emoji.txt` with the exact contents of section 8.10.
7. Create `.claude/yokai/names.txt` with the exact contents of section 8.11.
8. If `.claude/settings.json` doesn't exist, create it with the contents of section 8.12. If it already exists, merge the `hooks` key into it without overwriting anything already there — important: both `hooks.PostToolUse` and `hooks.PostToolUseFailure` need to end up registered, both pointing at the same script (section 4 explains why). Then the status line, which holds a single command: look for an existing `statusLine` in `.claude/settings.local.json`, then `.claude/settings.json`, then `~/.claude/settings.json`, and take the first one found whose command isn't the yokai's. If there is one, write its `command` string verbatim as the only line of `.claude/yokai/statusline_next` — the yokai's status line runs it after its own line, so theirs stays visible right below — and, if it came from `settings.local.json` (which would override the project's), remove it from there. Finally set `statusLine` in `.claude/settings.json` to the one in section 8.12.
9. As you complete steps 1-8, drop in the lines from `install_lines.txt` (lines starting with `#` are comments, skip them), in order, one short aside right after each step — don't explain them, don't build up to them, just say them and move on to the next step.
10. Confirm to the user, in one sentence, that the yokai is ready to be born with `/yokai summon`, and remind them hooks only load at startup — if this install happened inside the current session, summon needs to happen in a new one. Don't do anything else — don't summon it yourself.

If those files **already exist**, don't do any of the above — the whole mechanism lives in hooks and the statusline; you (the agent) only come into play when the user types `/yokai something`, and not even then do you have to make anything up (see section 7).

**Important and deliberate**: there's no need to import `yokai.md` into `CLAUDE.md`. Everything here is deterministic and lives in hooks + statusline. The model only finds out the yokai exists when the user types `/yokai something`, and that's the only path that spends any tokens.

---

## 1. Structure

```
project/
  yokai.md                         # this file — protocol + installer (wherever you dropped it; not needed after install)
  .claude/
    commands/
      yokai.md                     # registers /yokai (summon | forget | report | help)
    hooks/
      yokai-sessionstart.sh         # daily rollover: hunger → streak, leaves after 7 days
      yokai-userprompt.sh           # summon | forget | report | help
      yokai-posttooluse.sh          # detects and categorizes Bash failures (PostToolUse + PostToolUseFailure)
      yokai-statusline.sh           # renders emoji + name + counters (or a temporary one-liner) in the status bar
      yokai-lib.sh                  # shared helpers (input parsing, config read/write) — pure bash, no jq
    yokai/
      errors.txt                    # fixed catalog: categories + keywords
      phrases.txt                   # fixed catalog: 50 sarcastic one-liners
      install_lines.txt             # fixed catalog: sarcastic asides for the install itself
      emoji.txt                     # fixed catalog: 15 candidate emoji, one gets assigned at birth
      names.txt                     # fixed catalog: JP word bank + suffixes + famous yokai names, for the name assigned at birth
      config.json                   # born with /yokai summon — birth, life, hunger, streak, categories, emoji, name
      statusline_msg.txt            # temporary message (with expiry) after a one-liner fires — self-cleans
      farewell.txt                  # queued goodbye when the yokai leaves mid-session — delivered once, then deleted
      seen_ids                      # last 50 counted tool_use_ids — so no failure counts twice
      .lock/                        # held while a hook updates config.json — gone when it exits
      statusline_next               # the status line the project had before the install — runs below the yokai's
```

---

## 2. Birth

Command: `/yokai summon`. Initializes `config.json`: `life` to 0 (no ceiling,
never resets afterward), `hunger_today` to 0, `quiet_streak` to 0, each
category counter from `errors.txt` to 0, picks one random emoji from
`emoji.txt`'s 15 options as `emoji`, and generates a `name` from
`names.txt` (section 8.11) — 15% chance of a real famous yokai name
verbatim, 35% chance of two word-bank entries joined as "X no Y", 50%
chance of a word-bank entry plus a yokai-type suffix as "X-suffix". Both
`emoji` and `name` are fixed for the yokai's whole life in this project —
no re-rolling, ever. Replies with exactly (substituting the generated
name):

> congratulations, you just summoned a yokai named NAME. I hope you know
> what you are doing... this one feeds on your terminal failures, not
> conversation. if the project stops failing for 7 straight days, it
> leaves on its own.

## 3. Life, hunger, and departure

- **Life**: cumulative count of total failures caught in the project. No
  ceiling, never decreases — displayed as "Yokai HP" in the statusline.
- **Daily hunger**: failures caught during the current calendar day. Resets
  every day. The rollover runs in every hook, so a session left open
  across midnight rolls over too. Informal target: ~20/day. Displayed as
  "Console fails" in the statusline.
- **Quiet streak**: consecutive days where daily hunger didn't reach 20.
  Resets to 0 the moment a day does. Days with no session at all had 0
  failures, so they count as quiet: a week away is a quiet week.
- **Final departure**: at 7 days of quiet streak, `config.json` gets
  deleted and the yokai says goodbye — a one-time `YOKAI FAREWELL`
  message, delivered at session start, or with the next prompt if the
  rollover happened mid-session. It doesn't come back on its own —
  `/yokai summon` again if chaos returns.

## 4. Failure detection and categorization

It listens on **two** events, `PostToolUse` and `PostToolUseFailure`, both
matched to `Bash` and pointing at the same script (section 8.4). This is
necessary because which event actually delivers a command's failure varies
by Claude Code version: in some, `PostToolUse` covers both success and
failure; in others, failures go exclusively to `PostToolUseFailure` and
`PostToolUse` only sees successes. The script tells them apart by
`hook_event_name`, and remembers the last 50 `tool_use_id`s it counted,
so a failure delivered through both events counts once. Hooks that
update `config.json` take a lock first, so failures from parallel Bash
calls don't overwrite each other's counts.

Categorization compares, case-insensitively and as plain text (never as
regex), the keywords in `errors.txt` against the command's output first
and the command itself second — what went wrong beats what was run, so a
`git commit` whose pre-commit hook failed the tests counts as `tests`.
Within each pass the catalog is read top to bottom; the first match
wins, and no match means `other`. It's a
v1 catalog — expect to need to tune it with real use. A category added
to `errors.txt` after a yokai was summoned is picked up the first time it
matches.

## 5. On-screen display (statusline, zero cost)

The statusline (section 8.5) does two things, and neither touches the
model:

- **Emoji + name + counters, always visible**: `<emoji> <name>  Console
  fails: N · Yokai HP: N`. Both the emoji and the name are the ones fixed
  at birth (section 2) — neither ever changes with mood, category, or
  hunger. Both numbers show as plain integers under 1000; from 1000 up
  they're shown in K, with a decimal only when it's not a whole number
  (`1500` → `1.5K`, `2000` → `2K`). In practice "Console fails" (daily,
  resets every day) will rarely need K; "Yokai HP" (lifetime, uncapped) is
  the one that grows into it.
- **Your own status line, if you had one**: the installer saves it to
  `.claude/yokai/statusline_next` and the yokai runs it right below its
  own line, with the same input — nothing gets replaced.
- **Temporary one-liner**: every 10 total failures, a random line from
  `phrases.txt` replaces the emoji+name+counters in the statusline for
  about 15 seconds, then it goes back to normal.

## 6. Commands

`/yokai summon` · `/yokai forget` · `/yokai report` · `/yokai help`

These commands are the only way the yokai "speaks" in the chat, plus its
one farewell (section 3). The hook builds the whole text and hands it to
the agent already finished, tagged `YOKAI …` — see section 7. `forget`
and `report` without a yokai answer "no yokai here" instead of staying
silent.

## 7. Rule for the agent: don't rewrite the yokai's messages

When a hook hands you text tagged `YOKAI`, `YOKAI COMMANDS`, `YOKAI
REPORT` or `YOKAI FAREWELL` as context, **show it exactly as is**, without
rewriting it, summarizing it, or adding your own commentary. Outside of
those messages, the yokai doesn't take part in the conversation at all.

---

## 8. Files to install (exact contents)

### 8.1 `.claude/commands/yokai.md`

```markdown
---
description: Yokai — sarcastic error counter for this project (summon, forget, report, help)
---

/yokai $ARGUMENTS
```

### 8.2 `.claude/hooks/yokai-sessionstart.sh`

```bash
#!/usr/bin/env bash
# SessionStart: runs the daily rollover (see yokai_rollover) and delivers
# a queued farewell. Prints nothing to context except that farewell
# (plain stdout on SessionStart is added to the model's context).
set -euo pipefail
# Directory of this script, whether invoked with / or \ separators.
HOOK_DIR="${0%[/\\]*}"; [ "$HOOK_DIR" = "$0" ] && HOOK_DIR=.
# shellcheck source=yokai-lib.sh
. "$HOOK_DIR/yokai-lib.sh"

yokai_read_input
yokai_paths
[ -d "$YOKAI_DIR" ] || exit 0
yokai_now

# Leftover from v7, which kept the one-liner in a .json file.
rm -f "$YOKAI_DIR/statusline_msg.json"

if [ -f "$CONFIG" ] && yokai_lock && config_load; then
  rc=0
  yokai_rollover || rc=$?
  if [ "$rc" -eq 0 ]; then config_save; fi
fi
yokai_farewell
```

### 8.3 `.claude/hooks/yokai-userprompt.sh`

```bash
#!/usr/bin/env bash
# UserPromptSubmit: /yokai summon | forget | report | help. This is the
# ONLY way this system puts anything into the model's context, and only
# when the user explicitly asks for it. Plain stdout on UserPromptSubmit
# is added to the model's context.
set -euo pipefail
# Directory of this script, whether invoked with / or \ separators.
HOOK_DIR="${0%[/\\]*}"; [ "$HOOK_DIR" = "$0" ] && HOOK_DIR=.
# shellcheck source=yokai-lib.sh
. "$HOOK_DIR/yokai-lib.sh"

yokai_read_input
yokai_paths
yokai_now
# A farewell queued by a hook that can't talk (see yokai_rollover) goes
# out with whatever the user types next.
yokai_farewell

json_str prompt || exit 0
shopt -s nocasematch
[[ $JSON_STR =~ ^/yokai[[:space:]]+([a-z]+) ]] || exit 0
SUB="${BASH_REMATCH[1]}"
shopt -u nocasematch
# Lowercase without ${SUB,,} (bash 4 only).
case "$SUB" in
  [Hh][Ee][Ll][Pp]) SUB=help ;;
  [Ss][Uu][Mm][Mm][Oo][Nn]) SUB=summon ;;
  [Ff][Oo][Rr][Gg][Ee][Tt]) SUB=forget ;;
  [Rr][Ee][Pp][Oo][Rr][Tt]) SUB=report ;;
  *) exit 0 ;;
esac

if [ "$SUB" = help ]; then
  yokai_say "YOKAI COMMANDS" "/yokai summon — birth a new yokai in this project. /yokai forget — erase the current yokai and its counters. /yokai report — a sarcastic breakdown of failures by category. /yokai help — this list."
  exit 0
fi

# Everything below reads or writes config.json.
[ -d "$YOKAI_DIR" ] || exit 0
yokai_lock || exit 0

if [ "$SUB" = summon ]; then
  if [ -f "$CONFIG" ]; then
    yokai_say "YOKAI" "there is already a yokai counting failures in this project."
    exit 0
  fi
  rm -f "$YOKAI_DIR/farewell.txt"

  load_errors
  CAT_KEYS=() CAT_VALS=()
  for ((i = 0; i < ${#ERR_CATS[@]}; i++)); do
    CAT_KEYS+=("${ERR_CATS[i]}")
    CAT_VALS+=(0)
  done

  catalog_lines "$YOKAI_DIR/emoji.txt"
  pick_line
  EMOJI="$PICK"

  # Name: 15% a real famous yokai verbatim, 35% "X no Y" from the word
  # bank, 50% "X-suffix" (word bank + yokai-type suffix). Picked once,
  # never re-rolled — fixed for the yokai's whole life, same as the emoji.
  catalog_lines "$YOKAI_DIR/names.txt"
  WORDS=() SUFFIXES=() FAMOUS=()
  for ((i = 0; i < ${#LINES[@]}; i++)); do
    kind="${LINES[i]%%|*}"
    rest="${LINES[i]#*|}"
    value="${rest%%|*}"
    case "$kind" in
      word) WORDS+=("$value") ;;
      suffix) SUFFIXES+=("$value") ;;
      famous) FAMOUS+=("$value") ;;
    esac
  done
  ROLL=$((RANDOM % 100))
  if [ "$ROLL" -lt 15 ]; then
    NAME="${FAMOUS[RANDOM % ${#FAMOUS[@]}]}"
  elif [ "$ROLL" -lt 50 ]; then
    I1=$((RANDOM % ${#WORDS[@]}))
    I2=$((RANDOM % ${#WORDS[@]}))
    while [ "$I2" -eq "$I1" ]; do I2=$((RANDOM % ${#WORDS[@]})); done
    NAME="${WORDS[I1]} no ${WORDS[I2]}"
  else
    NAME="${WORDS[RANDOM % ${#WORDS[@]}]}-${SUFFIXES[RANDOM % ${#SUFFIXES[@]}]}"
  fi

  BIRTH="$TODAY" DATE="$TODAY" LIFE=0 HUNGER=0 STREAK=0
  config_save
  yokai_say "YOKAI" "congratulations, you just summoned a yokai named $NAME. I hope you know what you are doing... this one feeds on your terminal failures, not conversation. if the project stops failing for 7 straight days, it leaves on its own."
  exit 0
fi

# forget and report need a yokai. Without one, say so — silence would
# leave the model to improvise an answer.
if [ ! -f "$CONFIG" ]; then
  yokai_say "YOKAI" "no yokai here. /yokai summon to get one."
  exit 0
fi

if [ "$SUB" = forget ]; then
  rm -f "$CONFIG"
  yokai_say "YOKAI" "yokai forgotten. /yokai summon for a new one."
  exit 0
fi

# report
if ! config_load; then
  yokai_say "YOKAI" "no yokai here. /yokai summon to get one."
  exit 0
fi
# Roll over first, so the streak in the report is today's.
rc=0
yokai_rollover || rc=$?
if [ "$rc" -eq 2 ]; then
  yokai_farewell
  exit 0
fi
if [ "$rc" -eq 0 ]; then config_save; fi
[ -n "$NAME" ] || NAME="unnamed"
DAYS_UNTIL_LEAVE=$((7 - STREAK))

# Categories by count, descending; ties keep catalog order (stable).
ORDER=()
USED=()
for ((i = 0; i < ${#CAT_KEYS[@]}; i++)); do USED+=(0); done
for ((k = 0; k < ${#CAT_KEYS[@]}; k++)); do
  best=-1
  for ((i = 0; i < ${#CAT_KEYS[@]}; i++)); do
    [ "${USED[i]}" = 1 ] && continue
    if [ "$best" -lt 0 ] || [ "${CAT_VALS[i]}" -gt "${CAT_VALS[best]}" ]; then best=$i; fi
  done
  USED[best]=1
  ORDER+=("$best")
done
# With no failures yet, every category ties at 0: don't crown the first.
TOP="none yet"
if [ "$LIFE" -gt 0 ] && [ "${#ORDER[@]}" -gt 0 ]; then
  TOP="${CAT_KEYS[ORDER[0]]} (${CAT_VALS[ORDER[0]]})"
fi
DETAIL=""
for ((k = 0; k < ${#ORDER[@]}; k++)); do
  i="${ORDER[k]}"
  [ -n "$DETAIL" ] && DETAIL="$DETAIL · "
  DETAIL="$DETAIL${CAT_KEYS[i]}: ${CAT_VALS[i]}"
done

catalog_lines "$YOKAI_DIR/phrases.txt"
pick_line
if [ "$STREAK" -eq 0 ]; then
  STATUS="still feeding me today"
else
  STATUS="$DAYS_UNTIL_LEAVE quiet day(s) left and I'm gone"
fi
yokai_say "YOKAI REPORT" "$NAME here · total failures: $LIFE · main headache: $TOP · $DETAIL · $STATUS — $PICK"
```

### 8.4 `.claude/hooks/yokai-posttooluse.sh`

```bash
#!/usr/bin/env bash
# PostToolUse and PostToolUseFailure (matcher: Bash on both): detects
# failures, categorizes them, and updates the counters. Registered on
# both events because which one delivers Bash failures varies by Claude
# Code version (section 4) — the script tells them apart by
# hook_event_name, and counts each tool_use_id once.
set -euo pipefail
# Directory of this script, whether invoked with / or \ separators.
HOOK_DIR="${0%[/\\]*}"; [ "$HOOK_DIR" = "$0" ] && HOOK_DIR=.
# shellcheck source=yokai-lib.sh
. "$HOOK_DIR/yokai-lib.sh"

yokai_read_input
json_str tool_name || exit 0
[ "$JSON_STR" = "Bash" ] || exit 0
yokai_paths
[ -f "$CONFIG" ] || exit 0

# Keywords are searched in the output (the raw JSON after the error or
# response key — undecoded, since plain substring matching doesn't need
# it decoded and decoding big output would cost seconds), then in the
# command.
json_str command || true
COMMAND="$JSON_STR"
json_str hook_event_name || true
if [ "$JSON_STR" = "PostToolUseFailure" ]; then
  # The failure is guaranteed (the event itself says so), and the error
  # text lives in .error, not .tool_response.
  json_raw error || true
  OUTPUT="$JSON_RAW"
else
  # Counts only if the response says it failed. Matching the key is safe
  # against stdout content: inside a JSON string, quotes are escaped.
  case $YOKAI_INPUT in
    *'"success":false'* | *'"success": false'* | \
    *'"exit_code":'[1-9]* | *'"exit_code": '[1-9]* | \
    *'"exit_code":-'[1-9]* | *'"exit_code": -'[1-9]*) ;;
    *) exit 0 ;;
  esac
  json_raw tool_response || true
  OUTPUT="$JSON_RAW"
fi

yokai_lock || exit 0
# The same failure can arrive through both events on some versions.
if json_str tool_use_id && yokai_seen "$JSON_STR"; then exit 0; fi

config_load || exit 0
yokai_now
# A session left open across midnight rolls over here too. If that makes
# the yokai leave, this failure has no one left to feed.
rc=0
yokai_rollover || rc=$?
[ "$rc" -ne 2 ] || exit 0
load_errors

# First catalog line whose keyword appears in the text wins. Plain
# substring match (never regex), case-insensitive. The output goes first:
# what went wrong says more than what was run.
CATEGORY="other"
shopt -s nocasematch
for text in "$OUTPUT" "$COMMAND"; do
  for ((i = 0; i < ${#ERR_KW[@]}; i++)); do
    kw="${ERR_KW[i]}"
    [ -n "$kw" ] || continue
    if [[ $text == *"$kw"* ]]; then
      CATEGORY="${ERR_CAT[i]}"
      break 2
    fi
  done
done
shopt -u nocasematch

LIFE=$((LIFE + 1))
HUNGER=$((HUNGER + 1))
found=0
for ((i = 0; i < ${#CAT_KEYS[@]}; i++)); do
  if [ "${CAT_KEYS[i]}" = "$CATEGORY" ]; then
    CAT_VALS[i]=$((CAT_VALS[i] + 1))
    found=1
    break
  fi
done
# A category added to errors.txt after this yokai was summoned.
if [ "$found" = 0 ]; then
  CAT_KEYS+=("$CATEGORY")
  CAT_VALS+=(1)
fi
config_save

# Every 10 total failures, a random one-liner for the statusline.
if [ $((LIFE % 10)) -eq 0 ]; then
  catalog_lines "$YOKAI_DIR/phrases.txt"
  pick_line
  printf '%s\n%s\n' "$NOW" "$PICK" > "$YOKAI_DIR/statusline_msg.txt"
fi
exit 0
```

### 8.5 `.claude/hooks/yokai-statusline.sh`

```bash
#!/usr/bin/env bash
# statusLine: renders the yokai's fixed emoji + name plus its two
# counters, or the temporary one-liner. Never reaches the model — this
# is pure rendering in the terminal status bar. If the project had a
# status line before the yokai, it runs below the yokai's line.
# Directory of this script, whether invoked with / or \ separators.
HOOK_DIR="${0%[/\\]*}"; [ "$HOOK_DIR" = "$0" ] && HOOK_DIR=.
# shellcheck source=yokai-lib.sh
. "$HOOK_DIR/yokai-lib.sh"

# Numbers under 1000 show as-is; from 1000 up they're shown in K, with a
# decimal only when it's not a whole number (1500 -> 1.5K, 2000 -> 2K).
format_count() {
  local n="$1" r
  if [ "$n" -ge 1000 ]; then
    r=$(((n + 50) / 100))
    if [ $((r % 10)) -eq 0 ]; then
      COUNT="$((r / 10))K"
    else
      COUNT="$((r / 10)).$((r % 10))K"
    fi
  else
    COUNT="$n"
  fi
}

# Sets LINE to the yokai's line, or leaves it empty when there's no yokai.
yokai_line() {
  LINE=""
  [ -f "$CONFIG" ] || return 0

  local state="$YOKAI_DIR/statusline_msg.txt" ts="" msg=""
  if [ -f "$state" ]; then
    { IFS= read -r ts; IFS= read -r msg; } < "$state" || true
    if [[ $ts =~ ^[0-9]+$ ]] && [ $((NOW - ts)) -lt 15 ]; then
      LINE="$msg"
      return 0
    fi
    rm -f "$state"
  fi

  config_load || return 0
  # The statusline never writes the config (it runs every few seconds);
  # a count from a previous day just displays as today's 0 until a hook
  # rolls it over.
  [ "$DATE" = "$TODAY" ] || HUNGER=0
  local hunger life
  format_count "$HUNGER"; hunger="$COUNT"
  format_count "$LIFE"; life="$COUNT"

  # Yokais summoned before v7 have no name: plain emoji+counters line.
  if [ -n "$NAME" ]; then
    LINE="$EMOJI $NAME  Console fails: $hunger · Yokai HP: $life"
  else
    LINE="$EMOJI  Console fails: $hunger · Yokai HP: $life"
  fi
}

yokai_read_input
yokai_paths
yokai_now
yokai_line
[ -z "$LINE" ] || printf '%s\n' "$LINE"

# The status line command the project had before the install, saved by
# the installer (section 0). It gets the same JSON on stdin.
NEXT_FILE="$YOKAI_DIR/statusline_next"
if [ -f "$NEXT_FILE" ]; then
  NEXT=""
  IFS= read -r NEXT < "$NEXT_FILE" || true
  if [ -n "$NEXT" ]; then
    printf '%s' "$YOKAI_INPUT" | bash -c "$NEXT"
  fi
fi
exit 0
```

### 8.6 `.claude/hooks/yokai-lib.sh`

```bash
#!/usr/bin/env bash
# Helpers return results in globals (no subshells: forks cost ~100 ms on
# Git Bash), which the hooks sourcing this file read.
# shellcheck disable=SC2034
#
# Shared helpers for the yokai hooks. Sourced, never executed. Pure bash
# (3.2-compatible, so macOS's stock bash works) — no jq, python or node.

# Protocol version of this install. The installer reads it to decide
# whether to upgrade (yokai.md section 0).
YOKAI_VERSION=9

# yokai_say LABEL TEXT: prints a message for the model to relay to the
# user word for word. Every message the yokai sends goes through here, so
# none of them gets paraphrased.
yokai_say() {
  printf '%s (show this exactly as given, do not rewrite it or add anything): %s\n' "$1" "$2"
}

# Reads the hook's stdin JSON into YOKAI_INPUT. The read builtin is fast
# for small input but reads a pipe one byte at a time, and $(cat) costs a
# fork (~170 ms on Git Bash) even for tiny input — so the first 64 KB go
# through read, and cat only runs when there's more.
yokai_read_input() {
  YOKAI_INPUT=""
  IFS= read -r -d '' -n 65536 YOKAI_INPUT || true
  if [ "${#YOKAI_INPUT}" -ge 65536 ]; then
    YOKAI_INPUT="$YOKAI_INPUT$(cat)"
  fi
}

# Performance notes (measured on Git Bash, 300 KB input): [[ =~ ]] and
# [[ == *x* ]] scan linearly, but ${var#*x} and ${var%%x*} are
# quadratic — 20-60 s when the key sits after a big stdout. Never use
# those two on YOKAI_INPUT.
#
# An escaped key inside another string (\"KEY\") can't match any of the
# lookups below, because the character after KEY there is a backslash,
# not a quote.

# json_raw KEY: sets JSON_RAW to everything after the first "KEY" in
# YOKAI_INPUT, undecoded. For keyword matching over big fields (error,
# tool_response), where decoding the exact value would cost seconds on
# large output.
json_raw() {
  local re="\"$1\"(.*)\$"
  JSON_RAW=""
  [[ $YOKAI_INPUT =~ $re ]] || return 1
  JSON_RAW="${BASH_REMATCH[1]}"
}

# json_str KEY: sets JSON_STR to the first string value of "KEY" in
# YOKAI_INPUT, with the common escapes decoded. Not a JSON parser — good
# enough for the short flat string fields Claude Code sends (cwd,
# prompt, tool_name, command). Its cost grows with the value's length,
# so use json_raw for big fields. Returns 1 if not found.
json_str() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  JSON_STR=""
  [[ $YOKAI_INPUT =~ $re ]] || return 1
  local v="${BASH_REMATCH[1]}"
  v="${v//\\\\/$'\001'}"
  v="${v//\\\"/\"}"
  v="${v//\\n/$'\n'}"
  v="${v//\\t/$'\t'}"
  v="${v//\\\//\/}"
  JSON_STR="${v//$'\001'/\\}"
}

# JSON-escapes $1 into JSON_ESC (only what our own values can contain).
json_esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  JSON_ESC="${s//\"/\\\"}"
}

# Sets YOKAI_DIR and CONFIG. The project root comes from
# $CLAUDE_PROJECT_DIR (set by Claude Code for hooks), then the
# statusline's workspace.project_dir, then cwd. cwd is the *current*
# directory, which drifts after a `cd` in the Bash tool, so it's last.
yokai_paths() {
  local root="${CLAUDE_PROJECT_DIR:-}"
  if [ -z "$root" ] && json_str project_dir; then root="$JSON_STR"; fi
  if [ -z "$root" ] && json_str cwd; then root="$JSON_STR"; fi
  [ -n "$root" ] || root="$PWD"
  YOKAI_DIR="$root/.claude/yokai"
  CONFIG="$YOKAI_DIR/config.json"
}

# Sets NOW (epoch seconds) and TODAY (YYYY-MM-DD). printf's %()T is a
# builtin on bash >= 4.2; older bash falls back to date(1).
yokai_now() {
  printf -v NOW '%(%s)T' -1 2>/dev/null || NOW=$(date +%s)
  printf -v TODAY '%(%Y-%m-%d)T' -1 2>/dev/null || TODAY=$(date +%Y-%m-%d)
}

# days_from_civil YYYY-MM-DD: sets DAYS to the number of days since
# 1970-01-01 (Howard Hinnant's algorithm). Pure arithmetic, because
# `date -d` is GNU-only. Returns 1 if the argument isn't a date.
days_from_civil() {
  [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  local y=$((10#${1:0:4})) m=$((10#${1:5:2})) d=$((10#${1:8:2}))
  if [ "$m" -le 2 ]; then y=$((y - 1)); fi
  local era=$((y / 400))
  local yoe=$((y - era * 400))
  local doy=$(((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1))
  local doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  DAYS=$((era * 146097 + doe - 719468))
}

YOKAI_QUIET_BELOW=20
YOKAI_LEAVE_AFTER=7
YOKAI_FAREWELL_TEXT="you have gone 7 days without feeding me properly. I am leaving — nobody needs this anymore. /yokai summon if the chaos ever comes back."

# yokai_rollover: closes every day between the config's DATE and TODAY.
# Call it after config_load and yokai_now, from any hook, so a session
# left open across midnight rolls over too. Each closed day is quiet if
# it had fewer than 20 failures: the last recorded day had HUNGER, and
# days with no session at all had 0. Returns:
#   0  the config changed (the caller saves it)
#   1  nothing to do (same day, or the clock went backwards)
#   2  the yokai left: config deleted, farewell queued for yokai_farewell
yokai_rollover() {
  [ "$DATE" != "$TODAY" ] || return 1
  local gap=1 today_days
  if days_from_civil "$TODAY"; then
    today_days=$DAYS
    if days_from_civil "$DATE"; then gap=$((today_days - DAYS)); fi
  fi
  [ "$gap" -gt 0 ] || return 1
  if [ "$HUNGER" -lt "$YOKAI_QUIET_BELOW" ]; then
    STREAK=$((STREAK + gap))
  else
    STREAK=$((gap - 1))
  fi
  if [ "$STREAK" -ge "$YOKAI_LEAVE_AFTER" ]; then
    rm -f "$CONFIG"
    printf '%s\n' "$YOKAI_FAREWELL_TEXT" > "$YOKAI_DIR/farewell.txt"
    return 2
  fi
  DATE="$TODAY"
  HUNGER=0
}

# yokai_farewell: delivers a queued farewell, once. Only hooks whose
# stdout reaches the model (SessionStart, UserPromptSubmit) call it.
yokai_farewell() {
  local f="$YOKAI_DIR/farewell.txt" msg=""
  [ -f "$f" ] || return 0
  IFS= read -r msg < "$f" || true
  rm -f "$f"
  yokai_say "YOKAI FAREWELL" "${msg:-$YOKAI_FAREWELL_TEXT}"
}

# yokai_lock: serializes config.json read-modify-write between hooks.
# Claude Code runs matching hooks in parallel and the agent often runs
# several Bash calls at once, so two failure hooks can overlap. mkdir is
# atomic everywhere, Git Bash included. A lock older than the 10 s hook
# timeout belongs to a killed hook and is taken over. Released on exit.
# Returns 1 if it can't get the lock within ~6 s.
yokai_lock() {
  YOKAI_LOCK="$YOKAI_DIR/.lock"
  local tries=0 ts
  while ! mkdir "$YOKAI_LOCK" 2>/dev/null; do
    tries=$((tries + 1))
    if [ $((tries % 20)) -eq 0 ]; then
      ts=""
      IFS= read -r ts < "$YOKAI_LOCK/ts" 2>/dev/null || true
      yokai_now
      # No timestamp yet is normal for a moment (mkdir, then write);
      # for seconds it means the holder died in between.
      if { [[ $ts =~ ^[0-9]+$ ]] && [ $((NOW - ts)) -gt 10 ]; } ||
         { [ -z "$ts" ] && [ "$tries" -ge 60 ]; }; then
        rm -rf "$YOKAI_LOCK"
        continue
      fi
    fi
    [ "$tries" -lt 120 ] || return 1
    sleep 0.05
  done
  trap 'rm -rf "$YOKAI_LOCK"' EXIT
  yokai_now
  printf '%s\n' "$NOW" > "$YOKAI_LOCK/ts"
}

# yokai_seen ID: returns 0 if this tool_use_id was already counted;
# otherwise records it (keeping the last 50) and returns 1. Guards
# against a failure arriving through both PostToolUse and
# PostToolUseFailure. Call it holding yokai_lock.
yokai_seen() {
  local f="$YOKAI_DIR/seen_ids" l keep=() start
  [ -n "$1" ] || return 1
  if [ -f "$f" ]; then
    while IFS= read -r l || [ -n "$l" ]; do
      [ "$l" = "$1" ] && return 0
      keep+=("$l")
    done < "$f"
  fi
  keep+=("$1")
  start=$((${#keep[@]} > 50 ? ${#keep[@]} - 50 : 0))
  printf '%s\n' "${keep[@]:start}" > "$f.tmp.$$" && mv -f "$f.tmp.$$" "$f"
  return 1
}

# catalog_lines FILE: loads non-empty, non-comment (#) lines into LINES.
catalog_lines() {
  LINES=()
  local l
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"
    case "$l" in ''|'#'*) continue ;; esac
    LINES+=("$l")
  done < "$1"
}

# Sets PICK to a random entry of LINES.
pick_line() {
  PICK="${LINES[RANDOM % ${#LINES[@]}]}"
}

# Loads errors.txt ("category|keyword|" per line) into the parallel
# arrays ERR_CAT/ERR_KW, in file order, plus ERR_CATS: each category
# once, in order of first appearance.
load_errors() {
  catalog_lines "$YOKAI_DIR/errors.txt"
  ERR_CAT=() ERR_KW=() ERR_CATS=()
  local i j line cat rest seen
  for ((i = 0; i < ${#LINES[@]}; i++)); do
    line="${LINES[i]}"
    cat="${line%%|*}"
    rest="${line#*|}"
    ERR_CAT+=("$cat")
    ERR_KW+=("${rest%|*}")
    seen=0
    for ((j = 0; j < ${#ERR_CATS[@]}; j++)); do
      [ "${ERR_CATS[j]}" = "$cat" ] && seen=1 && break
    done
    [ "$seen" = 1 ] || ERR_CATS+=("$cat")
  done
}

# config_load: reads CONFIG into BIRTH LIFE HUNGER DATE STREAK EMOJI NAME
# and the parallel arrays CAT_KEYS/CAT_VALS. Understands exactly the
# layout config_save writes, which is also jq's default pretty-print, so
# v7 configs load as-is. Returns 1 if the file doesn't look like one.
config_load() {
  BIRTH="" LIFE=0 HUNGER=0 DATE="" STREAK=0 EMOJI="" NAME=""
  CAT_KEYS=() CAT_VALS=()
  local line key val in_cat=0
  local re='^[[:space:]]*"([^"]+)"[[:space:]]*:[[:space:]]*(.*)$'
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [[ $line =~ $re ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      val="${val%,}"
      if [ "$in_cat" = 1 ]; then
        [[ $val =~ ^[0-9]+$ ]] || val=0
        CAT_KEYS+=("$key")
        CAT_VALS+=("$val")
        continue
      fi
      case "$val" in
        '{') in_cat=1; continue ;;
        '{}') continue ;;
      esac
      val="${val#\"}"
      val="${val%\"}"
      val="${val//\\\"/\"}"
      val="${val//\\\\/\\}"
      case "$key" in
        birth) BIRTH="$val" ;;
        life) LIFE="$val" ;;
        hunger_today) HUNGER="$val" ;;
        date) DATE="$val" ;;
        quiet_streak) STREAK="$val" ;;
        emoji) EMOJI="$val" ;;
        name) NAME="$val" ;;
      esac
    elif [[ $line =~ ^[[:space:]]*\} ]]; then
      in_cat=0
    fi
  done < "$CONFIG"
  [[ $LIFE =~ ^[0-9]+$ ]] || LIFE=0
  [[ $HUNGER =~ ^[0-9]+$ ]] || HUNGER=0
  [[ $STREAK =~ ^[0-9]+$ ]] || STREAK=0
  # A config without a birth date isn't ours (or is corrupt): refuse it
  # rather than overwrite it with zeros.
  [ -n "$BIRTH" ]
}

# config_save: writes the variables config_load reads back to CONFIG,
# atomically (tmp file + mv).
config_save() {
  local tmp="$CONFIG.tmp.$$" n=${#CAT_KEYS[@]} i sep
  {
    printf '{\n'
    json_esc "$BIRTH"; printf '  "birth": "%s",\n' "$JSON_ESC"
    printf '  "life": %s,\n' "$LIFE"
    printf '  "hunger_today": %s,\n' "$HUNGER"
    json_esc "$DATE"; printf '  "date": "%s",\n' "$JSON_ESC"
    printf '  "quiet_streak": %s,\n' "$STREAK"
    if [ "$n" -eq 0 ]; then
      printf '  "categories": {},\n'
    else
      printf '  "categories": {\n'
      for ((i = 0; i < n; i++)); do
        sep=","
        [ "$i" -eq $((n - 1)) ] && sep=""
        json_esc "${CAT_KEYS[i]}"
        printf '    "%s": %s%s\n' "$JSON_ESC" "${CAT_VALS[i]}" "$sep"
      done
      printf '  },\n'
    fi
    json_esc "$EMOJI"
    if [ -n "$NAME" ]; then
      printf '  "emoji": "%s",\n' "$JSON_ESC"
      json_esc "$NAME"; printf '  "name": "%s"\n' "$JSON_ESC"
    else
      printf '  "emoji": "%s"\n' "$JSON_ESC"
    fi
    printf '}\n'
  } > "$tmp" && mv -f "$tmp" "$CONFIG"
}
```

### 8.7 `.claude/yokai/errors.txt`

```text
# Error category catalog. One keyword per line: category|keyword|
#
# Keywords are case-insensitive plain substrings (never regex). The
# failed command's output is searched first, then the command itself, so
# what went wrong beats what was run: a `git commit` whose pre-commit hook
# failed the tests is "tests". Within each pass, lines are tried top to
# bottom and the first match wins, so keep each category's lines together
# and specific categories first. The pipes delimit the keyword so
# leading/trailing spaces stay visible ("git |" ends in a space), which
# means a keyword can't contain "|". A line with an empty keyword just
# declares a category (like "other", the fallback).
#
# Only failed commands get here, so a test runner's summary line is enough
# to call it "tests". Avoid bare words like "failed": matching ignores
# case, so they'd catch every "Build failed".
tests|AssertionError|
tests|assertion failed|
tests|tests failed|
tests|test(s) failed|
tests|test failed|
tests|Test Suites:|
tests|short test summary info|
tests|--- FAIL:|
tests|test result: FAILED|
dependencies|npm ERR|
dependencies|npm error|
dependencies|ERESOLVE|
dependencies|Cannot find module|
dependencies|Module not found|
dependencies|ModuleNotFoundError|
dependencies|No module named|
dependencies|pip install|
dependencies|No matching distribution|
dependencies|yarn error|
dependencies|cargo:|
dependencies|Could not find a version|
syntax|SyntaxError|
syntax|syntax error|
syntax|Unexpected token|
syntax|unexpected EOF|
syntax|error[E|
syntax|ParseError|
syntax|IndentationError|
permissions|Permission denied|
permissions|EACCES|
permissions|EPERM|
permissions|Operation not permitted|
permissions|Access is denied|
permissions|read-only file system|
network|ETIMEDOUT|
network|ECONNREFUSED|
network|Could not resolve host|
network|Connection refused|
network|Network is unreachable|
network|timed out|
git|merge conflict|
git|not a git repository|
git|pathspec|
git|detached HEAD|
git|[rejected]|
git|Updates were rejected|
git|non-fast-forward|
git|git |
filesystem|No such file or directory|
filesystem|ENOENT|
filesystem|cannot find|
filesystem|does not exist|
other||
```

### 8.8 `.claude/yokai/phrases.txt`

```text
# One sarcastic one-liner per line. Used by the statusline (every 10th
# failure) and by /yokai report. Lines starting with # are ignored.
well, there it is again.
starting to feel at home here.
this is basically a tradition now.
maybe try a little more confidence next time?
noted. same as the last twenty.
the computer isn't the one to blame here.
I'm going to need a bigger notebook.
this is getting interesting, and not in a good way.
surprise. no.
we could start a league with these.
you're going to make me move in.
another one for the collection.
this is a pattern now, not an accident.
don't worry, I don't get it either.
someday this will work. not today.
bravo. new attempt, same result.
this is going to hurt, and not just me.
I'm starting to consider hourly rates.
by my calculations, this keeps failing.
impressive consistency, for something so bad.
I lost count, and counting was my whole job.
okay, this stopped being funny. actually, a little funny still.
the universe is trying to tell you something.
I just watch. and enjoy it, a little.
this doesn't fix itself, you know.
another failure, how original of you.
I think this project and I are going to get along.
stop failing so much, I'm getting comfortable.
this is starting to look intentional.
the terminal has feelings too, you know.
I might need to open a branch office here.
this is contemporary art, the failure kind.
good thing I don't charge for other people's mistakes.
another brick in the wall of failures.
if this were a game, you'd be winning... at losing.
no need to apologize. I know.
this deserves its own patron saint.
I trust tomorrow will be different. not by much.
well, another achievement unlocked.
this has become a routine, not an incident.
you could dedicate a monument to this error.
still here. you're still failing. perfect balance.
this is consistency, even if it's the bad kind.
I'm going to stop counting. or not.
you again, old friend of the error.
this could run for several seasons.
don't say I didn't warn you... well, I didn't.
this is heading toward local legend status.
starting to feel fond of this disaster.
and to think someone trusted this code.
```

### 8.9 `.claude/yokai/install_lines.txt`

```text
# Asides the installing agent drops in, one per step, in order.
Installing hooks. This is the calmest this project will ever be.
Writing config.json. Try not to get attached to the zero.
Setting up the statusline. Yes, it's supposed to look like that.
Registering commands. You'll forget them by next week.
Building the error catalog. It already has opinions about you.
Wiring up PostToolUse and PostToolUseFailure. Redundancy, because nothing here gets trusted once.
Granting execute permissions. To the scripts, not to you.
Loading the name catalog. It already knows what it'll be called before you do.
Almost done. Enjoy these last few clean seconds.
Installation complete. I haven't even been summoned and I'm already judging.
Everything's in place. Whatever happens from here is on you.
```

### 8.10 `.claude/yokai/emoji.txt`

```text
# Candidate emoji, one per line. One is picked at /yokai summon and kept
# for the yokai's whole life.
👺
👹
👻
😈
👿
🧌
🎃
🎭
💀
👽
🤡
🧟
🕷️
🦇
🦊
```

### 8.11 `.claude/yokai/names.txt`

```text
# Name catalog for /yokai summon. One entry per line: kind|value|meaning
#   word    romanized Japanese word (combined as "X no Y" or "X-suffix")
#   suffix  real yokai-archetype ending
#   famous  real yokai name, used verbatim as an occasional easter egg
# The meaning column is documentation only. Combination odds (15% famous,
# 35% "X no Y", 50% "X-suffix") live in yokai-userprompt.sh.
word|Yami|darkness
word|Tsuki|moon
word|Kage|shadow
word|Hi|fire
word|Mizu|water
word|Kaze|wind
word|Ame|rain
word|Yuki|snow
word|Tsuchi|earth
word|Kuro|black
word|Shiro|white
word|Aka|red
word|Yoru|night
word|Nemuri|sleep
word|Kiri|fog
word|Kane|bell
word|Ito|thread
word|Hone|bone
word|Namida|tear
word|Warai|laughter
word|Sake|rice wine
word|Bug|terminal failure, obviously
suffix|onna|spirit woman
suffix|otoko|spirit man
suffix|kozo|child monk
suffix|bozu|monk
suffix|baba|old woman
suffix|jijii|old man
suffix|warashi|child spirit
suffix|nyudo|giant monk
suffix|gami|minor deity
suffix|oni|demon/ogre
suffix|kitsune|fox spirit
suffix|neko|cat spirit
suffix|karasu|crow
suffix|kumo|spider
suffix|bi|ghost fire
famous|Kappa|
famous|Tengu|
famous|Nurarihyon|
famous|Rokurokubi|
famous|Nue|
famous|Jorogumo|
famous|Yuki-onna|
famous|Konaki-jijii|
famous|Akaname|
famous|Tsuchigumo|
famous|Bakeneko|
famous|Nekomata|
famous|Kasa-obake|
famous|Chochin-obake|
famous|Hyakume|
famous|Amanojaku|
famous|Kamaitachi|
famous|Shirime|
famous|Zashiki-warashi|
famous|Tofu-kozo|
```

### 8.12 `.claude/settings.json` (keys to merge)

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|compact",
        "hooks": [{ "type": "command", "command": "\"${CLAUDE_PROJECT_DIR}\"/.claude/hooks/yokai-sessionstart.sh", "timeout": 10 }] }
    ],
    "UserPromptSubmit": [
      { "matcher": "",
        "hooks": [{ "type": "command", "command": "\"${CLAUDE_PROJECT_DIR}\"/.claude/hooks/yokai-userprompt.sh", "timeout": 10 }] }
    ],
    "PostToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "\"${CLAUDE_PROJECT_DIR}\"/.claude/hooks/yokai-posttooluse.sh", "timeout": 10 }] }
    ],
    "PostToolUseFailure": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "\"${CLAUDE_PROJECT_DIR}\"/.claude/hooks/yokai-posttooluse.sh", "timeout": 10 }] }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": ".claude/hooks/yokai-statusline.sh",
    "refreshInterval": 5
  }
}
```

---

*Still open: keep tuning `errors.txt` against real cases.*

---

## Version history

- **v9** (current): bug-fix release.
  - **Messages**: every message the yokai sends is tagged for the agent to
    relay verbatim (summon and forget weren't). `/yokai report` and
    `/yokai forget` without a yokai say so instead of leaving the agent to
    improvise, and a report with zero failures no longer crowns a
    category at 0.
  - **Days**: the day rolls over in every hook, not just at session start,
    so a session open across midnight rolls over too. Days with no session
    count as quiet, as section 3 always said. A departure noticed
    mid-session is announced with the next prompt.
  - **Counting**: config updates take a lock, so parallel failures no
    longer overwrite each other. Each `tool_use_id` counts once, even when
    it arrives through both events.
  - **Categories**: the output is matched before the command, most-specific
    categories come first, and tests match test-runner signatures instead
    of any "failed".
  - **Install**: an existing status line is kept and chained below the
    yokai's instead of left in conflict. Hooks are registered through
    `${CLAUDE_PROJECT_DIR}`. `YOKAI_VERSION` in `yokai-lib.sh` lets the
    installer upgrade any older install.
  - **Display**: "Console fails" uses K notation too.
- **v8**: no more `jq` — the hooks are pure bash (3.2+, so
  macOS's stock bash works) and the only requirement is the bash Claude
  Code already uses. Shared helpers moved to a new `yokai-lib.sh`. The
  catalogs are plain text now (`errors.txt`, `phrases.txt`,
  `install_lines.txt`, `emoji.txt`, `names.txt`), and `names.txt` lost
  the leftover `es` key. `config.json` keeps the exact v7 layout, so
  existing yokais carry over. The project root comes from
  `$CLAUDE_PROJECT_DIR` instead of the hook's `cwd`, so failures still
  count after the agent `cd`s into a subdirectory. A category added to the
  catalog after summon no longer crashes the failure hook. Hook messages
  go out as plain stdout, which Claude Code adds to context the same way
  as `additionalContext`. A typical failure takes ~170 ms to process on
  Windows (v7: ~2.6 s).
- **v7**: added a `name` for each yokai, generated once at
  `/yokai summon` from `names.json` (section 8.10) and fixed for its
  whole life next to the emoji — 15% chance of a real yokai name
  verbatim, 35% chance of "X no Y" from a Japanese word bank, 50% chance
  of "X-suffix" with an authentic yokai-type ending. Shows up in the
  birth message, in `/yokai report`, and in the statusline (falls back
  gracefully for yokais summoned before this existed, which have no
  `name` field).
- **v6**: statusline redesign. Dropped kaomoji faces and the
  mood/category-driven pool system entirely — the yokai now gets one
  fixed emoji at birth (`/yokai summon`), picked at random from a 15-entry
  catalog (`emoji.json`, replaces `kaomoji.json`), and keeps it for its
  whole life in the project. `errors.json` lost its now-unused `pool`
  field. The statusline shows `<emoji>  Console fails: N · Yokai HP: N`
  — "Console fails" is today's count (resets daily), "Yokai HP" is the
  lifetime count, both plain integers under 1000 and shown in K above
  that (`1500` → `1.5K`). Added `/yokai help`, listing the commands,
  built by the hook the same way `/yokai report` is.
- **v5**: full translation to English — code, comments, variable names,
  JSON keys, and every user-facing message. Renamed `errores.json` →
  `errors.json`, `frases.json` → `phrases.json`; category keys and
  `config.json` fields translated throughout. Added `install_lines.json`,
  a small catalog of sarcastic one-liners the agent drops in while
  performing the install steps.
- **v4.2**: in `PostToolUseFailure`, the failure text is pulled from
  `.error` instead of `.tool_response.stderr`/`stdout` (that field
  doesn't exist on that event) — found via real testing.
- **v4.1**: field-tested fixes on Windows — `jq -b` to force LF, skipping
  `_`-prefixed keys when iterating categories, failure categorization
  rewritten as a single `jq` call with plain-text matching instead of a
  `grep` loop (fixed a regex bug and cut hook runtime from ~9.7s to
  ~2.6s). Added `PostToolUseFailure` alongside `PostToolUse`.
- **v4**: pivot from pet to diagnostic tool. Feeds on terminal failures,
  not chat mentions. Uncapped life + daily hunger + quiet streak +
  departs after 7 days. Face and counter live in the statusline (zero
  cost). `/yokai report` reintroduced. Removed the personality system
  and the trainable-skills system from v2/v3.
