#!/usr/bin/env bash
# UserPromptSubmit: /yokai summon | forget | report | help. This is the
# ONLY way this system puts anything into the model's context, and only
# when the user explicitly asks for it. Plain stdout on UserPromptSubmit
# is added to the model's context.
set -euo pipefail
# Directory of this script, whether invoked with / or \ separators.
HOOK_DIR="${0%[/\\]*}"; [ "$HOOK_DIR" = "$0" ] && HOOK_DIR=.
. "$HOOK_DIR/yokai-lib.sh"

yokai_read_input
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

yokai_paths
yokai_now

if [ "$SUB" = help ]; then
  echo "YOKAI COMMANDS (show this exactly as given, do not rewrite it or add anything): /yokai summon — birth a new yokai in this project. /yokai forget — erase the current yokai and its counters. /yokai report — a sarcastic breakdown of failures by category. /yokai help — this list."
  exit 0
fi

if [ "$SUB" = summon ]; then
  if [ -f "$CONFIG" ]; then
    echo "there is already a yokai counting failures in this project."
    exit 0
  fi

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
  echo "congratulations, you just summoned a yokai named $NAME. I hope you know what you are doing... this one feeds on your terminal failures, not conversation. if the project stops failing for 7 straight days, it leaves on its own."
  exit 0
fi

[ -f "$CONFIG" ] || exit 0

if [ "$SUB" = forget ]; then
  rm -f "$CONFIG"
  echo "yokai forgotten. /yokai summon for a new one."
  exit 0
fi

# report
config_load || exit 0
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
TOP="none"
[ "${#ORDER[@]}" -gt 0 ] && TOP="${CAT_KEYS[ORDER[0]]} (${CAT_VALS[ORDER[0]]})"
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
echo "YOKAI REPORT (show this exactly as given, do not rewrite it or add anything): $NAME here · total failures: $LIFE · main headache: $TOP · $DETAIL · $STATUS — $PICK"
