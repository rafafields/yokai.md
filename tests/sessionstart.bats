#!/usr/bin/env bats
# Daily rollover, quiet streak and departure (yokai-sessionstart.sh and
# yokai_rollover, which every hook runs)

load test_helper

FAREWELL="YOKAI FAREWELL (show this exactly as given, do not rewrite it or add anything): you have gone 7 days without feeding me properly. I am leaving — nobody needs this anymore. /yokai summon if the chaos ever comes back."

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

@test "the day after a busy one: streak resets, hunger resets" {
  v7_config 30 25 "$(days_ago 1)" 3
  run sessionstart
  [ -z "$output" ]
  [ "$(cfg quiet_streak)" = 0 ]
  [ "$(cfg hunger_today)" = 0 ]
  [ "$(cfg date)" = "$TODAY" ]
  [ "$(cfg life)" = 30 ]
  assert_valid_json "$CONFIG"
}

@test "the day after a quiet one: streak goes up by one" {
  v7_config 30 19 "$(days_ago 1)" 3
  sessionstart
  [ "$(cfg quiet_streak)" = 4 ]
  [ "$(cfg hunger_today)" = 0 ]
}

@test "exactly 20 failures is not a quiet day" {
  v7_config 30 20 "$(days_ago 1)" 3
  sessionstart
  [ "$(cfg quiet_streak)" = 0 ]
}

@test "days without a session count as quiet (Y-07)" {
  v7_config 30 5 "$(days_ago 3)" 1
  sessionstart
  [ "$(cfg quiet_streak)" = 4 ]
}

@test "days without a session after a busy day start a new streak (Y-07)" {
  v7_config 30 25 "$(days_ago 3)" 5
  sessionstart
  [ "$(cfg quiet_streak)" = 2 ]
}

@test "the 7th quiet day says goodbye and deletes the yokai" {
  v7_config 30 0 "$(days_ago 1)" 6
  run sessionstart
  [ "$output" = "$FAREWELL" ]
  [ ! -f "$CONFIG" ]
  [ ! -f "$YOKAI/farewell.txt" ]
}

@test "a week away is 7 quiet days: the yokai is gone on return" {
  v7_config 30 50 "$(days_ago 9)" 0
  run sessionstart
  [ "$output" = "$FAREWELL" ]
  [ ! -f "$CONFIG" ]
}

@test "a date in the future (clock went back) is left alone" {
  v7_config 30 5 2999-01-01 2
  before=$(cat "$CONFIG")
  sessionstart
  [ "$(cat "$CONFIG")" = "$before" ]
}

@test "cleans up the v7 statusline_msg.json" {
  v7_config 1 1 "$TODAY" 0
  echo '{"msg":"x","ts":0}' > "$YOKAI/statusline_msg.json"
  sessionstart
  [ ! -f "$YOKAI/statusline_msg.json" ]
}

@test "a failure after midnight rolls over before counting (Y-06)" {
  v7_config 30 25 "$(days_ago 1)" 3
  bash_failure 'git push' 'Updates were rejected'
  [ "$(cfg date)" = "$TODAY" ]
  [ "$(cfg hunger_today)" = 1 ]
  [ "$(cfg quiet_streak)" = 0 ]
  [ "$(cfg life)" = 31 ]
}

@test "a departure noticed by the failure hook is announced at the next prompt" {
  v7_config 30 0 "$(days_ago 1)" 6
  bash_failure 'git push' 'Updates were rejected'
  [ ! -f "$CONFIG" ]
  [ -f "$YOKAI/farewell.txt" ]
  run prompt 'fix the tests please'
  [ "$output" = "$FAREWELL" ]
  run prompt 'anything else'
  [ -z "$output" ]
}

@test "report rolls over before reporting the streak" {
  v7_config 30 0 "$(days_ago 2)" 1
  run prompt '/yokai report'
  [[ $output == *" · 4 quiet day(s) left and I'm gone — "* ]]
  [ "$(cfg quiet_streak)" = 3 ]
}

@test "the statusline shows a previous day's hunger as 0 without writing" {
  v7_config 30 25 "$(days_ago 1)" 0
  before=$(cat "$CONFIG")
  run statusline
  [ "$output" = "👻 Kage no Ame  Console fails: 0 · Yokai HP: 30" ]
  [ "$(cat "$CONFIG")" = "$before" ]
}
