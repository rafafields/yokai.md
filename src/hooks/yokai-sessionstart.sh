#!/usr/bin/env bash
# SessionStart: runs the daily rollover (see yokai_rollover) and delivers
# a queued farewell. Prints nothing to context except that farewell
# (plain stdout on SessionStart is added to the model's context).
set -euo pipefail
# Directory of this script, whether invoked with / or \ separators.
HOOK_DIR="${0%[/\\]*}"; [ "$HOOK_DIR" = "$0" ] && HOOK_DIR=.
# shellcheck source=yokai-lib.sh
. "$HOOK_DIR/yokai-lib.sh"

yokai_read_input
yokai_paths
[ -d "$YOKAI_DIR" ] || exit 0
yokai_now

# Leftover from v7, which kept the one-liner in a .json file.
rm -f "$YOKAI_DIR/statusline_msg.json"

if [ -f "$CONFIG" ] && yokai_lock && config_load; then
  rc=0
  yokai_rollover || rc=$?
  if [ "$rc" -eq 0 ]; then config_save; fi
fi
yokai_farewell
