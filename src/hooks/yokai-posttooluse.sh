#!/usr/bin/env bash
# PostToolUse and PostToolUseFailure (matcher: Bash on both): detects
# failures, categorizes them, and updates the counters. Registered on
# both events because which one delivers Bash failures varies by Claude
# Code version (section 4) — the script tells them apart by
# hook_event_name and never counts the same failure twice.
set -euo pipefail
jq() { command jq -b "$@"; }

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name')
[ "$TOOL" = "Bash" ] || exit 0

YOKAI_DIR="$CWD/.claude/yokai"
CONFIG="$YOKAI_DIR/config.json"
[ -f "$CONFIG" ] || exit 0

if [ "$EVENT" = "PostToolUseFailure" ]; then
  # In this event the failure is guaranteed (the event itself says so),
  # and the error text lives in .error, not .tool_response — confirmed
  # in practice on at least one Claude Code version. If your .error is
  # an object instead of a string, adjust the jq filter below.
  TEXT=$(echo "$INPUT" | jq -r '((.tool_input.command // "") + " " + (.error // "")) | ascii_downcase')
else
  # The exact tool_response schema varies by version/platform. Confirmed
  # in practice with success/exit_code — if your install uses a
  # different field (e.g. is_error), adjust this line.
  RESPONSE=$(echo "$INPUT" | jq -c '.tool_response')
  IS_FAILURE=$(echo "$RESPONSE" | jq -r 'if (.success == false) or ((.exit_code? // 0) != 0) then "1" else "" end')
  [ -z "$IS_FAILURE" ] && exit 0
  TEXT=$(echo "$INPUT" | jq -r '((.tool_input.command // "") + " " + (.tool_response.stderr // "") + (.tool_response.stdout // "")) | ascii_downcase')
fi

ERRORS="$YOKAI_DIR/errors.json"
# Single jq call, plain text (never regex) — avoids a keyword like
# "error[E" being read as a pattern and breaking the match.
CATEGORY=$(jq -r --arg t "$TEXT" '
  to_entries
  | map(select(.key | startswith("_") | not))
  | map(select(.value.keywords | any(. as $k | $t | contains($k | ascii_downcase))))
  | (.[0].key // "other")
' "$ERRORS")

LIFE=$(( $(jq -r '.life' "$CONFIG") + 1 ))
HUNGER=$(( $(jq -r '.hunger_today' "$CONFIG") + 1 ))
CATEGORY_COUNT=$(( $(jq -r --arg c "$CATEGORY" '.categories[$c]' "$CONFIG") + 1 ))
jq --argjson l "$LIFE" --argjson h "$HUNGER" --arg c "$CATEGORY" --argjson cc "$CATEGORY_COUNT" \
  '.life=$l | .hunger_today=$h | .categories[$c]=$cc' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"

# Every 10 total failures, a random one-liner for the statusline.
if [ $(( LIFE % 10 )) -eq 0 ]; then
  PHRASES="$YOKAI_DIR/phrases.json"
  N=$(jq 'length' "$PHRASES")
  IDX=$((RANDOM % N))
  MSG=$(jq -r ".[$IDX]" "$PHRASES")
  jq -n --arg m "$MSG" --arg t "$(date +%s)" '{msg:$m, ts:($t|tonumber)}' > "$YOKAI_DIR/statusline_msg.json"
fi
exit 0
