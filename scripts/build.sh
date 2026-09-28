#!/usr/bin/env bash
# Assembles dist/yokai.md from template/yokai.md.tmpl, replacing each
# "<!-- @include PATH -->" line with the contents of PATH (repo-relative).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/yokai.md}"
mkdir -p "$(dirname "$OUT")"

awk -v root="$ROOT" '
/^<!-- @include .* -->$/ {
  path = $3
  file = root "/" path
  if ((getline line < file) <= 0) { print "build: missing or empty " path > "/dev/stderr"; exit 1 }
  do { print line } while ((getline line < file) > 0)
  close(file)
  next
}
{ print }
' "$ROOT/template/yokai.md.tmpl" > "$OUT"
echo "built $OUT"
