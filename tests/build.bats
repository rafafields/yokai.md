#!/usr/bin/env bats
# scripts/build.sh and the template

load test_helper

@test "build resolves every include" {
  run "$REPO_ROOT/scripts/build.sh" "$BATS_TEST_TMPDIR/yokai.md"
  [ "$status" -eq 0 ]
  ! grep -q '@include' "$BATS_TEST_TMPDIR/yokai.md"
}

@test "build fails on a missing include" {
  mkdir -p "$BATS_TEST_TMPDIR/repo/scripts" "$BATS_TEST_TMPDIR/repo/template"
  cp "$REPO_ROOT/scripts/build.sh" "$BATS_TEST_TMPDIR/repo/scripts/"
  printf '<!-- @include src/nope.sh -->\n' > "$BATS_TEST_TMPDIR/repo/template/yokai.md.tmpl"
  run "$BATS_TEST_TMPDIR/repo/scripts/build.sh"
  [ "$status" -ne 0 ]
}

@test "every file in src/ is embedded in the protocol" {
  cd "$REPO_ROOT"
  for f in $(find src -type f | sort); do
    grep -qxF "<!-- @include $f -->" template/yokai.md.tmpl || { echo "not embedded: $f"; return 1; }
  done
}

@test "every embedded file is one the installer creates" {
  cd "$REPO_ROOT"
  for f in $(find src/hooks src/yokai src/commands -type f | sort); do
    installed=".claude/${f#src/}"
    grep -qF "\`$installed\`" template/yokai.md.tmpl || { echo "installer never mentions $installed"; return 1; }
  done
}

@test "dist/yokai.md is up to date" {
  "$REPO_ROOT/scripts/build.sh" "$BATS_TEST_TMPDIR/yokai.md"
  diff "$REPO_ROOT/dist/yokai.md" "$BATS_TEST_TMPDIR/yokai.md"
}

@test "the hook commands in settings.json run from any directory" {
  cp "$REPO_ROOT/src/settings.json" "$BATS_TEST_TMPDIR/settings.json"
  roots=("$PROJECT") ran=0
  if command -v cygpath >/dev/null; then roots+=("$(cygpath -w "$PROJECT")"); fi
  while IFS= read -r cmd; do
    cmd="${cmd//\\\"/\"}"
    for root in "${roots[@]}"; do
      run env CLAUDE_PROJECT_DIR="$root" bash -c "cd / && $cmd" < <(fixture sessionstart)
      [ "$status" -eq 0 ] || { echo "failed: $cmd (root $root): $output"; return 1; }
      ran=$((ran + 1))
    done
  done < <(grep -o '"command": "[^,]*/yokai-[a-z]*\.sh"' "$BATS_TEST_TMPDIR/settings.json" | grep CLAUDE_PROJECT_DIR | sed 's/^"command": "//; s/"$//')
  [ "$ran" -eq $((4 * ${#roots[@]})) ]
}

@test "YOKAI_VERSION matches the protocol version the installer announces" {
  lib=$(grep -o '^YOKAI_VERSION=[0-9]*' "$REPO_ROOT/src/hooks/yokai-lib.sh")
  proto=$(grep -o 'This file is protocol \*\*v[0-9]*\*\*' "$REPO_ROOT/template/yokai.md.tmpl")
  [ -n "$lib" ] && [ -n "$proto" ]
  [ "${lib#YOKAI_VERSION=}" = "$(echo "$proto" | tr -dc '0-9')" ]
  grep -q "^- \*\*v${lib#YOKAI_VERSION=}\*\* (current)" "$REPO_ROOT/template/yokai.md.tmpl"
}
