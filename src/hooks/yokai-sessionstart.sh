#!/usr/bin/env bash
# SessionStart: only handles the daily rollover and the final departure.
# Prints nothing to context except the one farewell message (plain
# stdout on SessionStart is added to the model's context).
set -euo pipefail
# Directory of this script, whether invoked with / or \ separators.
HOOK_DIR="${0%[/\\]*}"; [ "$HOOK_DIR" = "$0" ] && HOOK_DIR=.
# shellcheck source=yokai-lib.sh
. "$HOOK_DIR/yokai-lib.sh"

yokai_read_input
yokai_paths
[ -f "$CONFIG" ] || exit 0
config_load || exit 0
yokai_now

# Leftover from v7, which kept the one-liner in a .json file.
rm -f "$YOKAI_DIR/statusline_msg.json"

if [ "$TODAY" != "$DATE" ]; then
  THRESHOLD=20
  if [ "$HUNGER" -lt "$THRESHOLD" ]; then
    STREAK=$((STREAK + 1))
  else
    STREAK=0
  fi

  if [ "$STREAK" -ge 7 ]; then
    rm -f "$CONFIG"
    echo "you have gone 7 days without feeding me properly. I am leaving — nobody needs this anymore. /yokai summon if the chaos ever comes back."
    exit 0
  fi

  DATE="$TODAY"
  HUNGER=0
  config_save
fi
