#!/usr/bin/env bats
# Daily rollover, quiet streak and departure (yokai-sessionstart.sh)

load test_helper

@test "does nothing without a yokai" {
  run sessionstart
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "same day: nothing changes" {
  v7_config 30 25 "$TODAY" 3
  before=$(cat "$CONFIG")
  run sessionstart
  [ -z "$output" ]
  [ "$(cat "$CONFIG")" = "$before" ]
}

@test "new day after a busy one: streak resets, hunger resets" {
  v7_config 30 25 2026-01-01 3
  run sessionstart
  [ -z "$output" ]
  [ "$(cfg quiet_streak)" = 0 ]
  [ "$(cfg hunger_today)" = 0 ]
  [ "$(cfg date)" = "$TODAY" ]
  [ "$(cfg life)" = 30 ]
  assert_valid_json "$CONFIG"
}

@test "new day after a quiet one: streak goes up by one" {
  v7_config 30 19 2026-01-01 3
  sessionstart
  [ "$(cfg quiet_streak)" = 4 ]
  [ "$(cfg hunger_today)" = 0 ]
}

@test "exactly 20 failures is not a quiet day" {
  v7_config 30 20 2026-01-01 3
  sessionstart
  [ "$(cfg quiet_streak)" = 0 ]
}

@test "the 7th quiet day says goodbye and deletes the yokai" {
  v7_config 30 0 2026-01-01 6
  run sessionstart
  [ "$output" = "you have gone 7 days without feeding me properly. I am leaving — nobody needs this anymore. /yokai summon if the chaos ever comes back." ]
  [ ! -f "$CONFIG" ]
}

@test "cleans up the v7 statusline_msg.json" {
  v7_config 1 1 "$TODAY" 0
  echo '{"msg":"x","ts":0}' > "$YOKAI/statusline_msg.json"
  sessionstart
  [ ! -f "$YOKAI/statusline_msg.json" ]
}
