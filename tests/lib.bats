#!/usr/bin/env bats
# JSON helpers in yokai-lib.sh

load test_helper

setup() {
  # shellcheck source=../src/hooks/yokai-lib.sh
  . "$REPO_ROOT/src/hooks/yokai-lib.sh"
}

@test "json_str decodes escapes" {
  YOKAI_INPUT='{"a":"say \"hi\"\nnext\ttab a\/b C:\\dir \\n \\\" end"}'
  json_str a
  [ "$JSON_STR" = "say \"hi\""$'\n'"next"$'\t'"tab a/b C:\\dir \\n \\\" end" ]
}

@test "json_str tolerates spaces around the colon" {
  YOKAI_INPUT='{ "a" : "x" }'
  json_str a
  [ "$JSON_STR" = x ]
}

@test "json_str returns 1 for a missing key" {
  YOKAI_INPUT='{"a":"x"}'
  run json_str b
  [ "$status" -eq 1 ]
}

@test "json_str ignores keys that only appear escaped inside other strings" {
  YOKAI_INPUT='{"out":"{\"cwd\":\"/fake\"}","cwd":"/real"}'
  json_str cwd
  [ "$JSON_STR" = /real ]
}

@test "json_raw returns everything after the key" {
  YOKAI_INPUT='{"a":1,"error":"boom","z":2}'
  json_raw error
  [ "$JSON_RAW" = ':"boom","z":2}' ]
}

@test "json_esc escapes quotes and backslashes" {
  json_esc 'a"b\c'
  [ "$JSON_ESC" = 'a\"b\\c' ]
}

@test "yokai_read_input keeps everything past the 64 KB read" {
  big=$(head -c 100000 /dev/zero | tr '\0' 'a')
  yokai_read_input < <(printf '{"x":"%s","end":"yes"}' "$big")
  [ "${#YOKAI_INPUT}" -eq 100020 ]
  json_str end
  [ "$JSON_STR" = yes ]
}

@test "days_from_civil matches known day numbers" {
  while read -r d want; do
    days_from_civil "$d"
    if [ "$DAYS" != "$want" ]; then
      echo "$d: got $DAYS, want $want"
      return 1
    fi
  done <<'EOF'
1970-01-01 0
1970-01-02 1
2000-02-29 11016
2000-03-01 11017
2024-02-29 19782
2026-01-01 20454
2099-12-31 47481
EOF
}

@test "days_from_civil agrees with date across 2024-2027" {
  date -u -d 2024-01-01 +%s >/dev/null 2>&1 || skip "needs GNU date"
  start=$(($(date -u -d 2024-01-01 +%s) / 86400))
  for ((i = 0; i < 1461; i += 13)); do
    d=$(date -u -d "@$(((start + i) * 86400))" +%Y-%m-%d)
    days_from_civil "$d"
    [ "$DAYS" -eq $((start + i)) ] || { echo "$d: got $DAYS"; return 1; }
  done
}

@test "days_from_civil rejects non-dates" {
  run days_from_civil "not-a-date"
  [ "$status" -eq 1 ]
}

@test "config_save and config_load round-trip" {
  CONFIG="$BATS_TEST_TMPDIR/config.json"
  BIRTH=2026-01-01 LIFE=7 HUNGER=2 DATE=2026-01-02 STREAK=1
  EMOJI="🕷️" NAME='Odd "name" \ here'
  CAT_KEYS=(git other) CAT_VALS=(5 2)
  config_save
  BIRTH="" LIFE="" NAME="" CAT_KEYS=() CAT_VALS=()
  config_load
  [ "$BIRTH" = 2026-01-01 ]
  [ "$LIFE" = 7 ] && [ "$HUNGER" = 2 ] && [ "$STREAK" = 1 ]
  [ "$DATE" = 2026-01-02 ]
  [ "$EMOJI" = "🕷️" ]
  [ "$NAME" = 'Odd "name" \ here' ]
  [ "${CAT_KEYS[*]}" = "git other" ]
  [ "${CAT_VALS[*]}" = "5 2" ]
  assert_valid_json "$CONFIG"
}

@test "config_save writes an empty categories object as {}" {
  CONFIG="$BATS_TEST_TMPDIR/config.json"
  BIRTH=2026-01-01 LIFE=0 HUNGER=0 DATE=2026-01-01 STREAK=0 EMOJI=x NAME=""
  CAT_KEYS=() CAT_VALS=()
  config_save
  grep -qF '"categories": {},' "$CONFIG"
  ! grep -q '"name"' "$CONFIG"
  config_load
  [ "${#CAT_KEYS[@]}" -eq 0 ]
  assert_valid_json "$CONFIG"
}
