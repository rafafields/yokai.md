#!/usr/bin/env bash
# statusLine: renders the yokai's fixed emoji + name plus its two
# counters, or the temporary one-liner. Never reaches the model — this
# is pure rendering in the terminal status bar.
# Directory of this script, whether invoked with / or \ separators.
HOOK_DIR="${0%[/\\]*}"; [ "$HOOK_DIR" = "$0" ] && HOOK_DIR=.
# shellcheck source=yokai-lib.sh
. "$HOOK_DIR/yokai-lib.sh"

yokai_read_input
yokai_paths
[ -f "$CONFIG" ] || exit 0

STATE="$YOKAI_DIR/statusline_msg.txt"
if [ -f "$STATE" ]; then
  TS="" MSG=""
  { IFS= read -r TS; IFS= read -r MSG; } < "$STATE" || true
  yokai_now
  if [[ $TS =~ ^[0-9]+$ ]] && [ $((NOW - TS)) -lt 15 ]; then
    printf '%s\n' "$MSG"
    exit 0
  fi
  rm -f "$STATE"
fi

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

config_load || exit 0
# The statusline never writes the config (it runs every few seconds);
# a count from a previous day just displays as today's 0 until a hook
# rolls it over.
yokai_now
[ "$DATE" = "$TODAY" ] || HUNGER=0
format_count "$LIFE"

# Yokais summoned before v7 have no name: plain emoji+counters line.
if [ -n "$NAME" ]; then
  echo "$EMOJI $NAME  Console fails: $HUNGER · Yokai HP: $COUNT"
else
  echo "$EMOJI  Console fails: $HUNGER · Yokai HP: $COUNT"
fi
