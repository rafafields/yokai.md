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
