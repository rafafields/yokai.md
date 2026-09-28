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
