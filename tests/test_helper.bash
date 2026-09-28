# Shared setup for the hook tests: a throwaway project with the hooks and
# catalogs installed, plus helpers that feed each hook the JSON Claude
# Code would send (tests/fixtures/*.json).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
# The bash that runs the hooks. Set it to /bin/bash on macOS to cover
# bash 3.2.
YOKAI_BASH="${YOKAI_BASH:-bash}"
# bash 5.2 treats & in ${var//x/y} replacements as the matched text.
shopt -u patsub_replacement 2>/dev/null || true

setup() {
  PROJECT="$BATS_TEST_TMPDIR/project"
  HOOKS="$PROJECT/.claude/hooks"
  YOKAI="$PROJECT/.claude/yokai"
  CONFIG="$YOKAI/config.json"
  mkdir -p "$HOOKS" "$YOKAI" "$PROJECT/sub/dir"
  cp "$REPO_ROOT"/src/hooks/*.sh "$HOOKS/"
  cp "$REPO_ROOT"/src/yokai/*.txt "$YOKAI/"
  export CLAUDE_PROJECT_DIR="$PROJECT"
  TODAY=$(date +%Y-%m-%d)
}

# hook NAME: runs .claude/hooks/yokai-NAME.sh on the caller's stdin.
hook() {
  "$YOKAI_BASH" "$HOOKS/yokai-$1.sh"
}

# fixture NAME [KEY=VALUE...]: prints tests/fixtures/NAME.json with
# __PROJECT__ and each __KEY__ replaced. VALUE goes in as-is, so it must
# already be JSON-escaped.
fixture() {
  local json kv
  json=$(<"$BATS_TEST_DIRNAME/fixtures/$1.json")
  shift
  json="${json//__PROJECT__/$PROJECT}"
  for kv in "$@"; do
    json="${json//__${kv%%=*}__/${kv#*=}}"
  done
  printf '%s' "$json"
}

prompt() {
  fixture userprompt "PROMPT=$1" | hook userprompt
}

# bash_failure COMMAND ERROR [CWD]: a PostToolUseFailure for Bash.
bash_failure() {
  fixture posttoolusefailure-bash "COMMAND=$1" "ERROR=$2" "CWD=${3:-$PROJECT}" | hook posttooluse
}

# bash_result COMMAND STDOUT STDERR EXIT_CODE: a PostToolUse for Bash.
bash_result() {
  fixture posttooluse-bash "COMMAND=$1" "STDOUT=$2" "STDERR=$3" "EXIT=$4" "CWD=$PROJECT" | hook posttooluse
}

statusline() {
  fixture statusline "CWD=${1:-$PROJECT}" | hook statusline
}

sessionstart() {
  fixture sessionstart | hook sessionstart
}

summon() {
  prompt '/yokai summon' >/dev/null
}

# cfg KEY: a value from config.json, read without the code under test.
cfg() {
  grep "\"$1\":" "$CONFIG" | head -1 | sed 's/.*": *//; s/,$//; s/"//g'
}

# set_cfg KEY VALUE: rewrites a numeric or string field in config.json.
set_cfg() {
  local line tmp="$CONFIG.edit"
  : > "$tmp"
  while IFS= read -r line; do
    case "$line" in
      *"\"$1\": \""*) line="${line%%\"$1\"*}\"$1\": \"$2\"${line##*\"}" ;;
      *"\"$1\": "*) line="${line%%\"$1\"*}\"$1\": $2${line##*[0-9]}" ;;
    esac
    printf '%s\n' "$line" >> "$tmp"
  done < "$CONFIG"
  mv "$tmp" "$CONFIG"
}

# v7_config LIFE HUNGER DATE STREAK: a config.json exactly as v7's jq
# wrote it.
v7_config() {
  fixture config-v7 "LIFE=$1" "HUNGER=$2" "DATE=$3" "STREAK=$4" > "$CONFIG"
  printf '\n' >> "$CONFIG"
}

# assert_valid_json FILE: checked with jq when it's installed, since
# the hooks write config.json by hand.
assert_valid_json() {
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$1" >/dev/null
  fi
}

# in_file LINE FILE: whether FILE has LINE exactly. Pure bash: Git Bash's
# grep -xF misses 4-byte UTF-8 characters like emoji.
in_file() {
  local l
  while IFS= read -r l || [ -n "$l" ]; do
    [ "$l" = "$1" ] && return 0
  done < "$2"
  return 1
}
