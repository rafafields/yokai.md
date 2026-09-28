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
