#!/usr/bin/env bats
# /yokai summon | forget | report | help (yokai-userprompt.sh)

load test_helper

@test "help works without a yokai and asks to be shown verbatim" {
  run prompt '/yokai help'
  [ "$status" -eq 0 ]
  [[ $output == "YOKAI COMMANDS (show this exactly as given"* ]]
  [[ $output == *"/yokai summon"*"/yokai forget"*"/yokai report"*"/yokai help"* ]]
}

@test "prompts that aren't /yokai commands stay silent" {
  for p in 'hello' 'please /yokai summon' '/yokai' '/yokai dance' '/yokaisummon'; do
    run prompt "$p"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  [ ! -f "$CONFIG" ]
}

@test "summon creates a config with every catalog category at 0" {
  run prompt '/yokai summon'
  [ "$status" -eq 0 ]
  [[ $output == "congratulations, you just summoned a yokai named "*". I hope you know what you are doing"* ]]
  assert_valid_json "$CONFIG"
  [ "$(cfg birth)" = "$TODAY" ]
  [ "$(cfg date)" = "$TODAY" ]
  [ "$(cfg life)" = 0 ]
  [ "$(cfg hunger_today)" = 0 ]
  [ "$(cfg quiet_streak)" = 0 ]
  run grep -c '^    "[a-z]*": 0,\{0,1\}$' "$CONFIG"
  [ "$output" = 8 ]
}

@test "summon names the yokai in the birth message and config" {
  run prompt '/yokai summon'
  name="${output#*named }"
  name="${name%%. I hope*}"
  [ -n "$name" ]
  [ "$(cfg name)" = "$name" ]
}

@test "summon picks the emoji from the catalog" {
  summon
  in_file "$(cfg emoji)" "$YOKAI/emoji.txt"
}

@test "summoned names take one of the three documented shapes" {
  words=$(grep '^word|' "$YOKAI/names.txt" | cut -d'|' -f2)
  suffixes=$(grep '^suffix|' "$YOKAI/names.txt" | cut -d'|' -f2)
  famous=$(grep '^famous|' "$YOKAI/names.txt" | cut -d'|' -f2)
  for _ in 1 2 3 4 5 6 7 8; do
    rm -f "$CONFIG"
    summon
    name=$(cfg name)
    if grep -qxF "$name" <<< "$famous"; then continue; fi
    if [[ $name == *" no "* ]]; then
      grep -qxF "${name%% no *}" <<< "$words"
      grep -qxF "${name#* no }" <<< "$words"
      [ "${name%% no *}" != "${name#* no }" ]
    else
      grep -qxF "${name%-*}" <<< "$words"
      grep -qxF "${name##*-}" <<< "$suffixes"
    fi
  done
}

@test "summon is case-insensitive" {
  run prompt '/YOKAI Summon'
  [[ $output == "congratulations"* ]]
  [ -f "$CONFIG" ]
}

@test "summon refuses when a yokai already exists and leaves it alone" {
  v7_config 42 3 "$TODAY" 0
  before=$(cat "$CONFIG")
  run prompt '/yokai summon'
  [ "$output" = "there is already a yokai counting failures in this project." ]
  [ "$(cat "$CONFIG")" = "$before" ]
}

@test "forget deletes the yokai" {
  summon
  run prompt '/yokai forget'
  [ "$output" = "yokai forgotten. /yokai summon for a new one." ]
  [ ! -f "$CONFIG" ]
}

@test "report lists categories by count, ties in catalog order" {
  v7_config 12 3 "$TODAY" 0
  run prompt '/yokai report'
  [ "$status" -eq 0 ]
  [[ $output == "YOKAI REPORT (show this exactly as given, do not rewrite it or add anything): Kage no Ame here · total failures: 12 · main headache: git (7) · git: 7 · tests: 3 · other: 2 · dependencies: 0 · permissions: 0 · network: 0 · syntax: 0 · filesystem: 0 · still feeding me today — "* ]]
  phrase="${output##* — }"
  in_file "$phrase" "$YOKAI/phrases.txt"
}

@test "report counts down the quiet days" {
  v7_config 12 3 "$TODAY" 4
  run prompt '/yokai report'
  [[ $output == *" · 3 quiet day(s) left and I'm gone — "* ]]
}

@test "report on a yokai without a name says unnamed" {
  v7_config 1 1 "$TODAY" 0
  grep -v '"name"' "$CONFIG" | sed 's/"emoji": "👻",/"emoji": "👻"/' > "$CONFIG.new"
  mv "$CONFIG.new" "$CONFIG"
  run prompt '/yokai report'
  [[ $output == *": unnamed here · "* ]]
}

@test "report and forget without a yokai stay silent (Y-12, not fixed yet)" {
  run prompt '/yokai report'
  [ -z "$output" ]
  run prompt '/yokai forget'
  [ -z "$output" ]
}
