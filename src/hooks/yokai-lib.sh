#!/usr/bin/env bash
# Shared helpers for the yokai hooks. Sourced, never executed. Pure bash
# (3.2-compatible, so macOS's stock bash works) — no jq, python or node.

# Reads the hook's stdin JSON into YOKAI_INPUT. The read builtin is fast
# for small input but reads a pipe one byte at a time, and $(cat) costs a
# fork (~170 ms on Git Bash) even for tiny input — so the first 64 KB go
# through read, and cat only runs when there's more.
yokai_read_input() {
  YOKAI_INPUT=""
  IFS= read -r -d '' -n 65536 YOKAI_INPUT || true
  if [ "${#YOKAI_INPUT}" -ge 65536 ]; then
    YOKAI_INPUT="$YOKAI_INPUT$(cat)"
  fi
}

# Performance notes (measured on Git Bash, 300 KB input): [[ =~ ]] and
# [[ == *x* ]] scan linearly, but ${var#*x} and ${var%%x*} are
# quadratic — 20-60 s when the key sits after a big stdout. Never use
# those two on YOKAI_INPUT.
#
# An escaped key inside another string (\"KEY\") can't match any of the
# lookups below, because the character after KEY there is a backslash,
# not a quote.

# json_raw KEY: sets JSON_RAW to everything after the first "KEY" in
# YOKAI_INPUT, undecoded. For keyword matching over big fields (error,
# tool_response), where decoding the exact value would cost seconds on
# large output.
json_raw() {
  local re="\"$1\"(.*)\$"
  JSON_RAW=""
  [[ $YOKAI_INPUT =~ $re ]] || return 1
  JSON_RAW="${BASH_REMATCH[1]}"
}

# json_str KEY: sets JSON_STR to the first string value of "KEY" in
# YOKAI_INPUT, with the common escapes decoded. Not a JSON parser — good
# enough for the short flat string fields Claude Code sends (cwd,
# prompt, tool_name, command). Its cost grows with the value's length,
# so use json_raw for big fields. Returns 1 if not found.
json_str() {
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\""
  JSON_STR=""
  [[ $YOKAI_INPUT =~ $re ]] || return 1
  local v="${BASH_REMATCH[1]}"
  v="${v//\\\\/$'\001'}"
  v="${v//\\\"/\"}"
  v="${v//\\n/$'\n'}"
  v="${v//\\t/$'\t'}"
  v="${v//\\\//\/}"
  JSON_STR="${v//$'\001'/\\}"
}

# JSON-escapes $1 into JSON_ESC (only what our own values can contain).
json_esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  JSON_ESC="${s//\"/\\\"}"
}

# Sets YOKAI_DIR and CONFIG. The project root comes from
# $CLAUDE_PROJECT_DIR (set by Claude Code for hooks), then the
# statusline's workspace.project_dir, then cwd. cwd is the *current*
# directory, which drifts after a `cd` in the Bash tool, so it's last.
yokai_paths() {
  local root="${CLAUDE_PROJECT_DIR:-}"
  if [ -z "$root" ] && json_str project_dir; then root="$JSON_STR"; fi
  if [ -z "$root" ] && json_str cwd; then root="$JSON_STR"; fi
  [ -n "$root" ] || root="$PWD"
  YOKAI_DIR="$root/.claude/yokai"
  CONFIG="$YOKAI_DIR/config.json"
}

# Sets NOW (epoch seconds) and TODAY (YYYY-MM-DD). printf's %()T is a
# builtin on bash >= 4.2; older bash falls back to date(1).
yokai_now() {
  printf -v NOW '%(%s)T' -1 2>/dev/null || NOW=$(date +%s)
  printf -v TODAY '%(%Y-%m-%d)T' -1 2>/dev/null || TODAY=$(date +%Y-%m-%d)
}

# catalog_lines FILE: loads non-empty, non-comment (#) lines into LINES.
catalog_lines() {
  LINES=()
  local l
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"
    case "$l" in ''|'#'*) continue ;; esac
    LINES+=("$l")
  done < "$1"
}

# Sets PICK to a random entry of LINES.
pick_line() {
  PICK="${LINES[RANDOM % ${#LINES[@]}]}"
}

# Loads errors.txt ("category|keyword|" per line) into the parallel
# arrays ERR_CAT/ERR_KW, in file order, plus ERR_CATS: each category
# once, in order of first appearance.
load_errors() {
  catalog_lines "$YOKAI_DIR/errors.txt"
  ERR_CAT=() ERR_KW=() ERR_CATS=()
  local i j line cat rest seen
  for ((i = 0; i < ${#LINES[@]}; i++)); do
    line="${LINES[i]}"
    cat="${line%%|*}"
    rest="${line#*|}"
    ERR_CAT+=("$cat")
    ERR_KW+=("${rest%|*}")
    seen=0
    for ((j = 0; j < ${#ERR_CATS[@]}; j++)); do
      [ "${ERR_CATS[j]}" = "$cat" ] && seen=1 && break
    done
    [ "$seen" = 1 ] || ERR_CATS+=("$cat")
  done
}

# config_load: reads CONFIG into BIRTH LIFE HUNGER DATE STREAK EMOJI NAME
# and the parallel arrays CAT_KEYS/CAT_VALS. Understands exactly the
# layout config_save writes, which is also jq's default pretty-print, so
# v7 configs load as-is. Returns 1 if the file doesn't look like one.
config_load() {
  BIRTH="" LIFE=0 HUNGER=0 DATE="" STREAK=0 EMOJI="" NAME=""
  CAT_KEYS=() CAT_VALS=()
  local line key val in_cat=0
  local re='^[[:space:]]*"([^"]+)"[[:space:]]*:[[:space:]]*(.*)$'
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [[ $line =~ $re ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      val="${val%,}"
      if [ "$in_cat" = 1 ]; then
        [[ $val =~ ^[0-9]+$ ]] || val=0
        CAT_KEYS+=("$key")
        CAT_VALS+=("$val")
        continue
      fi
      case "$val" in
        '{') in_cat=1; continue ;;
        '{}') continue ;;
      esac
      val="${val#\"}"
      val="${val%\"}"
      val="${val//\\\"/\"}"
      val="${val//\\\\/\\}"
      case "$key" in
        birth) BIRTH="$val" ;;
        life) LIFE="$val" ;;
        hunger_today) HUNGER="$val" ;;
        date) DATE="$val" ;;
        quiet_streak) STREAK="$val" ;;
        emoji) EMOJI="$val" ;;
        name) NAME="$val" ;;
      esac
    elif [[ $line =~ ^[[:space:]]*\} ]]; then
      in_cat=0
    fi
  done < "$CONFIG"
  [[ $LIFE =~ ^[0-9]+$ ]] || LIFE=0
  [[ $HUNGER =~ ^[0-9]+$ ]] || HUNGER=0
  [[ $STREAK =~ ^[0-9]+$ ]] || STREAK=0
  # A config without a birth date isn't ours (or is corrupt): refuse it
  # rather than overwrite it with zeros.
  [ -n "$BIRTH" ]
}

# config_save: writes the variables config_load reads back to CONFIG,
# atomically (tmp file + mv).
config_save() {
  local tmp="$CONFIG.tmp.$$" n=${#CAT_KEYS[@]} i sep
  {
    printf '{\n'
    json_esc "$BIRTH"; printf '  "birth": "%s",\n' "$JSON_ESC"
    printf '  "life": %s,\n' "$LIFE"
    printf '  "hunger_today": %s,\n' "$HUNGER"
    json_esc "$DATE"; printf '  "date": "%s",\n' "$JSON_ESC"
    printf '  "quiet_streak": %s,\n' "$STREAK"
    if [ "$n" -eq 0 ]; then
      printf '  "categories": {},\n'
    else
      printf '  "categories": {\n'
      for ((i = 0; i < n; i++)); do
        sep=","
        [ "$i" -eq $((n - 1)) ] && sep=""
        json_esc "${CAT_KEYS[i]}"
        printf '    "%s": %s%s\n' "$JSON_ESC" "${CAT_VALS[i]}" "$sep"
      done
      printf '  },\n'
    fi
    json_esc "$EMOJI"
    if [ -n "$NAME" ]; then
      printf '  "emoji": "%s",\n' "$JSON_ESC"
      json_esc "$NAME"; printf '  "name": "%s"\n' "$JSON_ESC"
    else
      printf '  "emoji": "%s"\n' "$JSON_ESC"
    fi
    printf '}\n'
  } > "$tmp" && mv -f "$tmp" "$CONFIG"
}
