#!/usr/bin/env bats
# Failure detection and categorization (yokai-posttooluse.sh)

load test_helper

@test "does nothing without a yokai" {
  run bash_failure 'git push' 'rejected'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$CONFIG" ]
}

@test "a PostToolUseFailure counts toward life, hunger and its category" {
  summon
  run bash_failure 'git push' 'error: failed to push some refs\nhint: Updates were rejected'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cfg life)" = 1 ]
  [ "$(cfg hunger_today)" = 1 ]
  [ "$(cfg git)" = 1 ]
  assert_valid_json "$CONFIG"
}

@test "still counts after the agent cd's into a subdirectory (Y-04)" {
  summon
  bash_failure 'ls' 'ls: cannot access: No such file or directory' "$PROJECT/sub/dir"
  [ "$(cfg life)" = 1 ]
}

@test "falls back to cwd when CLAUDE_PROJECT_DIR isn't set" {
  summon
  unset CLAUDE_PROJECT_DIR
  bash_failure 'ls' 'nope'
  [ "$(cfg life)" = 1 ]
}

@test "PostToolUse counts a non-zero exit_code" {
  summon
  bash_result 'npm install' '' 'npm ERR! code ERESOLVE' 1
  [ "$(cfg life)" = 1 ]
  [ "$(cfg dependencies)" = 1 ]
}

@test "PostToolUse counts a negative exit_code" {
  summon
  bash_result 'x' '' '' -1
  [ "$(cfg life)" = 1 ]
}

@test "PostToolUse ignores exit_code 0" {
  summon
  bash_result 'git status' 'nothing to commit' '' 0
  [ "$(cfg life)" = 0 ]
}

@test "PostToolUse ignores a fake exit_code inside stdout" {
  summon
  bash_result 'cat r.json' '{\"exit_code\": 1, \"success\": false}' '' 0
  [ "$(cfg life)" = 0 ]
}

@test "PostToolUse counts success: false" {
  summon
  fixture posttooluse-bash "COMMAND=x" "STDOUT=" "STDERR=" "EXIT=0" "CWD=$PROJECT" "TOOLID=t9" \
    | sed 's/"interrupted":false/"success":false/' | hook posttooluse
  [ "$(cfg life)" = 1 ]
}

@test "ignores tools other than Bash" {
  summon
  fixture posttoolusefailure-read | hook posttooluse
  [ "$(cfg life)" = 0 ]
}

# categorize COMMAND ERROR: prints the category the failure landed in.
categorize() {
  rm -f "$CONFIG"
  summon
  bash_failure "$1" "$2"
  local c
  for c in git dependencies permissions network syntax tests filesystem other; do
    [ "$(cfg "$c")" = 1 ] && echo "$c"
  done
}

@test "categorization follows errors.txt" {
  while IFS='|' read -r cmd err want; do
    run categorize "$cmd" "$err"
    if [ "$output" != "$want" ]; then
      echo "'$cmd' / '$err': want $want, got $output"
      return 1
    fi
  done <<'EOF'
git push|remote: rejected|git
make|fatal: not a git repository|git
npm install|npm ERR! code ERESOLVE|dependencies
pip3 install foo|ERROR: No matching distribution found for foo|dependencies
./run.sh|bash: ./run.sh: Permission denied|permissions
curl https://x.test|curl: (6) Could not resolve host: x.test|network
node app.js|SyntaxError: Unexpected token '}'|syntax
rustc main.rs|error[E0308]: mismatched types|syntax
pytest|E   AssertionError: 1 != 2|tests
npx jest|FAIL src/a.test.js|tests
cat missing.txt|cat: missing.txt: No such file or directory|filesystem
make|something went sideways|other
EOF
}

@test "keyword matching is case-insensitive" {
  run categorize 'cat x' 'cat: x: NO SUCH FILE OR DIRECTORY'
  [ "$output" = filesystem ]
}

@test "the first matching catalog line wins" {
  run categorize 'git checkout nope' "error: pathspec 'nope' does not exist"
  [ "$output" = git ]
}

@test "keywords match literally, never as regex" {
  printf 'custom|a.c|\n' >> "$YOKAI/errors.txt"
  run categorize 'x' 'abc'
  [ "$output" = other ]
}

@test "escaped quotes and backslashes in the command don't break parsing" {
  summon
  bash_failure 'git commit -m \"fix \\\"x\\\"\" C:\\temp' 'rejected'
  [ "$(cfg git)" = 1 ]
  assert_valid_json "$CONFIG"
}

@test "a category added after summon is created on first match (Y-10)" {
  summon
  printf 'docker|cannot connect to the docker daemon|\n' > "$YOKAI/errors.txt.new"
  cat "$YOKAI/errors.txt" >> "$YOKAI/errors.txt.new"
  mv "$YOKAI/errors.txt.new" "$YOKAI/errors.txt"
  bash_failure 'docker ps' 'Cannot connect to the Docker daemon'
  [ "$(cfg docker)" = 1 ]
  [ "$(cfg life)" = 1 ]
  assert_valid_json "$CONFIG"
}

@test "a v7 config keeps its values and layout" {
  v7_config 1499 3 "$TODAY" 2
  bash_failure 'git push' 'rejected'
  [ "$(cfg life)" = 1500 ]
  [ "$(cfg hunger_today)" = 4 ]
  [ "$(cfg quiet_streak)" = 2 ]
  [ "$(cfg git)" = 8 ]
  [ "$(cfg tests)" = 3 ]
  [ "$(cfg name)" = "Kage no Ame" ]
  [ "$(cfg emoji)" = "👻" ]
  [ "$(cfg birth)" = 2026-01-01 ]
  # Same keys, same order as jq wrote them.
  diff <(grep -o '^ *"[a-z_]*"' "$CONFIG") <(fixture config-v7 | grep -o '^ *"[a-z_]*"')
}

@test "a config it doesn't recognize is left untouched" {
  printf '{"life":5}' > "$CONFIG"
  bash_failure 'git push' 'rejected'
  [ "$(cat "$CONFIG")" = '{"life":5}' ]
}

@test "every 10th failure leaves a one-liner for the statusline" {
  v7_config 8 0 "$TODAY" 0
  bash_failure 'x' 'y'
  [ ! -f "$YOKAI/statusline_msg.txt" ]
  bash_failure 'x' 'y'
  [ -f "$YOKAI/statusline_msg.txt" ]
  in_file "$(sed -n 2p "$YOKAI/statusline_msg.txt")" "$YOKAI/phrases.txt"
}

@test "a failure delivered by both events counts once (Y-08)" {
  summon
  TOOLID=toolu_same bash_failure 'npm test' 'tests failed'
  TOOLID=toolu_same bash_result 'npm test' '' 'tests failed' 1
  [ "$(cfg life)" = 1 ]
  TOOLID=toolu_other bash_failure 'npm test' 'tests failed'
  [ "$(cfg life)" = 2 ]
}

@test "remembers only the last 50 tool_use_ids" {
  summon
  for i in $(seq 1 60); do echo "toolu_old$i"; done > "$YOKAI/seen_ids"
  TOOLID=toolu_new bash_failure 'x' 'y'
  [ "$(wc -l < "$YOKAI/seen_ids" | tr -d ' ')" = 50 ]
  [ "$(tail -1 "$YOKAI/seen_ids")" = toolu_new ]
}

@test "parallel failures don't lose counts (Y-09)" {
  summon
  for i in $(seq 1 12); do
    bash_failure 'git push' 'Updates were rejected' &
  done
  wait
  [ "$(cfg life)" = 12 ]
  [ "$(cfg hunger_today)" = 12 ]
  [ ! -d "$YOKAI/.lock" ]
  assert_valid_json "$CONFIG"
}

@test "a stale lock left by a killed hook is taken over" {
  summon
  mkdir "$YOKAI/.lock"
  echo 1000 > "$YOKAI/.lock/ts"
  bash_failure 'x' 'y'
  [ "$(cfg life)" = 1 ]
  [ ! -d "$YOKAI/.lock" ]
}

@test "300 KB of output is categorized well within the 10 s hook timeout" {
  summon
  big=$(head -c 300000 /dev/zero | tr '\0' 'a')
  start=$(date +%s)
  bash_result 'pytest' "$big" 'tests failed' 1
  elapsed=$(($(date +%s) - start))
  echo "took ${elapsed}s"
  [ "$(cfg tests)" = 1 ]
  [ "$elapsed" -lt 8 ]
}
