#!/usr/bin/env bash
# UserPromptSubmit: /yokai summon | forget | report | help. This is the
# ONLY way this system puts anything into the model's context, and only
# when the user explicitly asks for it.
set -euo pipefail
jq() { command jq -b "$@"; }

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
PROMPT=$(echo "$INPUT" | jq -r '.prompt')
YOKAI_DIR="$CWD/.claude/yokai"
CONFIG="$YOKAI_DIR/config.json"
ERRORS="$YOKAI_DIR/errors.json"
PHRASES="$YOKAI_DIR/phrases.json"
EMOJI_FILE="$YOKAI_DIR/emoji.json"
NAMES_FILE="$YOKAI_DIR/names.json"
TODAY=$(date +%Y-%m-%d)

if echo "$PROMPT" | grep -qiE '^/yokai help'; then
  jq -n '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",
    additionalContext:"YOKAI COMMANDS (show this exactly as given, do not rewrite it or add anything): /yokai summon — birth a new yokai in this project. /yokai forget — erase the current yokai and its counters. /yokai report — a sarcastic breakdown of failures by category. /yokai help — this list."}}'
  exit 0
fi

if echo "$PROMPT" | grep -qiE '^/yokai summon'; then
  if [ -f "$CONFIG" ]; then
    jq -n '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:"there is already a yokai counting failures in this project."}}'
    exit 0
  fi
  CJSON="{}"
  for c in $(jq -r 'keys_unsorted[] | select(startswith("_") | not)' "$ERRORS"); do
    CJSON=$(echo "$CJSON" | jq --arg k "$c" '.[$k]=0')
  done
  N_EMOJI=$(jq 'length' "$EMOJI_FILE")
  EIDX=$((RANDOM % N_EMOJI))
  EMOJI=$(jq -r ".[$EIDX]" "$EMOJI_FILE")

  # Name: 15% a real famous yokai verbatim, 35% "X no Y" from the word
  # bank, 50% "X-suffix" (word bank + yokai-type suffix). Picked once,
  # never re-rolled — fixed for the yokai's whole life, same as the emoji.
  ROLL=$((RANDOM % 100))
  if [ "$ROLL" -lt 15 ]; then
    N=$(jq '.famous | length' "$NAMES_FILE")
    IDX=$((RANDOM % N))
    NAME=$(jq -r ".famous[$IDX]" "$NAMES_FILE")
  elif [ "$ROLL" -lt 50 ]; then
    NW=$(jq '.words | length' "$NAMES_FILE")
    I1=$((RANDOM % NW))
    I2=$((RANDOM % NW))
    while [ "$I2" -eq "$I1" ]; do I2=$((RANDOM % NW)); done
    W1=$(jq -r ".words[$I1].jp" "$NAMES_FILE")
    W2=$(jq -r ".words[$I2].jp" "$NAMES_FILE")
    NAME="$W1 no $W2"
  else
    NW=$(jq '.words | length' "$NAMES_FILE")
    NS=$(jq '.suffixes | length' "$NAMES_FILE")
    IW=$((RANDOM % NW))
    IS=$((RANDOM % NS))
    W=$(jq -r ".words[$IW].jp" "$NAMES_FILE")
    S=$(jq -r ".suffixes[$IS].jp" "$NAMES_FILE")
    NAME="$W-$S"
  fi

  jq -n --arg d "$TODAY" --argjson cat "$CJSON" --arg e "$EMOJI" --arg n "$NAME" \
    '{birth:$d, life:0, hunger_today:0, date:$d, quiet_streak:0, categories:$cat, emoji:$e, name:$n}' > "$CONFIG"
  jq -n --arg n "$NAME" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",
    additionalContext:("congratulations, you just summoned a yokai named " + $n + ". I hope you know what you are doing... this one feeds on your terminal failures, not conversation. if the project stops failing for 7 straight days, it leaves on its own.")}}'
  exit 0
fi

[ -f "$CONFIG" ] || exit 0

if echo "$PROMPT" | grep -qiE '^/yokai forget'; then
  rm -f "$CONFIG"
  jq -n '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:"yokai forgotten. /yokai summon for a new one."}}'
  exit 0
fi

if echo "$PROMPT" | grep -qiE '^/yokai report'; then
  NAME=$(jq -r '.name // "unnamed"' "$CONFIG")
  LIFE=$(jq -r '.life' "$CONFIG")
  STREAK=$(jq -r '.quiet_streak' "$CONFIG")
  DAYS_UNTIL_LEAVE=$(( 7 - STREAK ))
  TOP=$(jq -r '.categories | to_entries | sort_by(-.value) | .[0] | "\(.key) (\(.value))"' "$CONFIG")
  DETAIL=$(jq -r '.categories | to_entries | sort_by(-.value) | map("\(.key): \(.value)") | join(" · ")' "$CONFIG")
  N=$(jq 'length' "$PHRASES")
  IDX=$((RANDOM % N))
  PHRASE=$(jq -r ".[$IDX]" "$PHRASES")
  STATUS="$([ "$STREAK" -eq 0 ] && echo "still feeding me today" || echo "$DAYS_UNTIL_LEAVE quiet day(s) left and I'm gone")"
  REPORT="$NAME here · total failures: $LIFE · main headache: $TOP · $DETAIL · $STATUS — $PHRASE"
  jq -n --arg ctx "$REPORT" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",
    additionalContext:("YOKAI REPORT (show this exactly as given, do not rewrite it or add anything): " + $ctx)}}'
  exit 0
fi
