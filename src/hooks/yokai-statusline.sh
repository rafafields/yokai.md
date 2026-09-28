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
