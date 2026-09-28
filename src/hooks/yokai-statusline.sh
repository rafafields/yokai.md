#!/usr/bin/env bash
# statusLine: renders the yokai's fixed emoji + name plus its two
# counters, or the temporary one-liner. Never reaches the model — this
# is pure rendering in the terminal status bar.
jq() { command jq -b "$@"; }

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd' 2>/dev/null || pwd)
YOKAI_DIR="$CWD/.claude/yokai"
CONFIG="$YOKAI_DIR/config.json"
[ -f "$CONFIG" ] || exit 0

STATE="$YOKAI_DIR/statusline_msg.json"
if [ -f "$STATE" ]; then
  TS=$(jq -r '.ts' "$STATE")
  NOW=$(date +%s)
  if [ $(( NOW - TS )) -lt 15 ]; then
    jq -r '.msg' "$STATE"
    exit 0
  fi
  rm -f "$STATE"
fi

# Numbers under 1000 show as-is; from 1000 up they're shown in K, with a
# decimal only when it's not a whole number (1500 -> 1.5K, 2000 -> 2K).
format_count() {
  local n="$1"
  if [ "$n" -ge 1000 ]; then
    jq -r -n --argjson n "$n" '($n/1000*10|round)/10 as $k | if ($k == ($k|floor)) then "\($k|floor)K" else "\($k)K" end'
  else
    echo "$n"
  fi
}

EMOJI=$(jq -r '.emoji' "$CONFIG")
# '// empty' covers yokais summoned before names.json existed — no name
# field, falls back to the plain emoji+counters line below.
NAME=$(jq -r '.name // empty' "$CONFIG")
LIFE=$(jq -r '.life' "$CONFIG")
HUNGER_TODAY=$(jq -r '.hunger_today' "$CONFIG")
LIFE_DISPLAY=$(format_count "$LIFE")

if [ -n "$NAME" ]; then
  echo "$EMOJI $NAME  Console fails: $HUNGER_TODAY · Yokai HP: $LIFE_DISPLAY"
else
  echo "$EMOJI  Console fails: $HUNGER_TODAY · Yokai HP: $LIFE_DISPLAY"
fi
