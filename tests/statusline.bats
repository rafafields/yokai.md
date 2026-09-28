#!/usr/bin/env bats
# Status bar rendering (yokai-statusline.sh)

load test_helper

@test "prints nothing without a yokai" {
  run statusline
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "shows emoji, name and both counters" {
  v7_config 42 5 "$TODAY" 0
  run statusline
  [ "$output" = "👻 Kage no Ame  Console fails: 5 · Yokai HP: 42" ]
}

@test "Yokai HP switches to K notation from 1000" {
  while read -r life want; do
    v7_config "$life" 0 "$TODAY" 0
    run statusline
    if [ "$output" != "👻 Kage no Ame  Console fails: 0 · Yokai HP: $want" ]; then
      echo "life $life: got '$output', want $want"
      return 1
    fi
  done <<'EOF'
999 999
1000 1K
1049 1K
1050 1.1K
1500 1.5K
1950 2K
2000 2K
12345 12.3K
EOF
}

@test "a yokai from before names existed shows emoji and counters only" {
  v7_config 3 1 "$TODAY" 0
  grep -v '"name"' "$CONFIG" | sed 's/"emoji": "👻",/"emoji": "👻"/' > "$CONFIG.new"
  mv "$CONFIG.new" "$CONFIG"
  run statusline
  [ "$output" = "👻  Console fails: 1 · Yokai HP: 3" ]
}

@test "a fresh one-liner replaces the counters" {
  v7_config 10 10 "$TODAY" 0
  printf '%s\n%s\n' "$(date +%s)" "well, there it is again." > "$YOKAI/statusline_msg.txt"
  run statusline
  [ "$output" = "well, there it is again." ]
}

@test "an expired one-liner is removed and the counters come back" {
  v7_config 10 10 "$TODAY" 0
  printf '%s\n%s\n' "$(($(date +%s) - 20))" "old news" > "$YOKAI/statusline_msg.txt"
  run statusline
  [ "$output" = "👻 Kage no Ame  Console fails: 10 · Yokai HP: 10" ]
  [ ! -f "$YOKAI/statusline_msg.txt" ]
}

@test "finds the project through workspace.project_dir after a cd (Y-04)" {
  v7_config 1 1 "$TODAY" 0
  unset CLAUDE_PROJECT_DIR
  run statusline "$PROJECT/sub/dir"
  [ "$output" = "👻 Kage no Ame  Console fails: 1 · Yokai HP: 1" ]
}

@test "works when invoked through a Windows backslash path" {
  command -v cygpath >/dev/null || skip "Windows only"
  v7_config 1 1 "$TODAY" 0
  run "$YOKAI_BASH" "$(cygpath -w "$HOOKS")\\yokai-statusline.sh" < <(fixture statusline "CWD=$PROJECT")
  [ "$output" = "👻 Kage no Ame  Console fails: 1 · Yokai HP: 1" ]
}
