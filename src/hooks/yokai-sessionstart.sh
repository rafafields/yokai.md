#!/usr/bin/env bash
# SessionStart: only handles the daily rollover and the final departure.
# Prints nothing to context except the one farewell message.
set -euo pipefail
# jq on Windows ends its output lines in CRLF, which breaks the bash
# comparisons and arithmetic below. -b/--binary forces LF everywhere.
jq() { command jq -b "$@"; }

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
YOKAI_DIR="$CWD/.claude/yokai"
CONFIG="$YOKAI_DIR/config.json"

[ -f "$CONFIG" ] || exit 0

TODAY=$(date +%Y-%m-%d)
DATE=$(jq -r '.date' "$CONFIG")

if [ "$TODAY" != "$DATE" ]; then
  HUNGER_TODAY=$(jq -r '.hunger_today' "$CONFIG")
  THRESHOLD=20
  if [ "$HUNGER_TODAY" -lt "$THRESHOLD" ]; then
    STREAK=$(( $(jq -r '.quiet_streak' "$CONFIG") + 1 ))
  else
    STREAK=0
  fi

  if [ "$STREAK" -ge 7 ]; then
    rm -f "$CONFIG"
    jq -n '{hookSpecificOutput:{hookEventName:"SessionStart",
      additionalContext:"you have gone 7 days without feeding me properly. I am leaving — nobody needs this anymore. /yokai summon if the chaos ever comes back."}}'
    exit 0
  fi

  jq --arg d "$TODAY" --argjson s "$STREAK" '.date=$d | .hunger_today=0 | .quiet_streak=$s' \
    "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
fi
