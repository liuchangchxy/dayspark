#!/usr/bin/env bash
# Version drift guard: every human-synced copy of the project version must match
# pubspec.yaml (the single source of truth).
#
# Gated markers — all four files are updated together by the "docs: vX 文档与版本"
# commit (CLAUDE.md workflow step 6):
#   CLAUDE.md           - Current version
#   docs/changelog.md   - 最新版本 / Latest, top "## v" section, 上一版本 / Previous
#   docs/ROADMAP.md     - 最后更新 / Last updated, 当前版本 / Current, Version row
#
# Deliberately NOT gated, because both are refreshed out of band (a correct
# release commit would otherwise be flagged red):
#   README.md           - status badge is re-cut in a later docs pass
#   docs/START_HERE.md  - "当前版本 + tag URL" is written after the release is published
#
# Usage:
#   tool/check_version_consistency.sh                  check this repo
#   tool/check_version_consistency.sh --tag v0.25.0    also require the tag to match
#   tool/check_version_consistency.sh --root DIR       check another tree
#   tool/check_version_consistency.sh --selftest       prove the guard can actually fail

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
root="$repo_root"
tag=""
selftest=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift 2 ;;
    --tag) tag="${2:-}"; shift 2 ;;
    --selftest) selftest=1; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  tool/check_version_consistency.sh                  check this repo
  tool/check_version_consistency.sh --tag v0.25.0    also require the tag to match
  tool/check_version_consistency.sh --root DIR       check another tree
  tool/check_version_consistency.sh --selftest       prove the guard can actually fail
USAGE
      exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

full=""
semver=""
build=""
fail=0
passed=0

note_ok() { passed=$((passed + 1)); printf '  [ok]   %-20s %s\n' "$1" "$2"; }
note_fail() {
  fail=$((fail + 1))
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::error file=%s::%s\n' "$1" "$2"
  fi
  printf '  [FAIL] %-20s %s\n' "$1" "$2"
}

extract() { sed -n "$2" "$root/$1" 2>/dev/null | head -n 1; }

expect() { # expect <file> <label> <sed-expr> <expected>
  if [ ! -f "$root/$1" ]; then
    note_fail "$1" "$2: file not found"
    return 0
  fi
  local found
  found="$(extract "$1" "$3")"
  if [ -z "$found" ]; then
    note_fail "$1" "$2: marker missing (expected '$4') - was the line reworded?"
  elif [ "$found" != "$4" ]; then
    note_fail "$1" "$2: '$found' != '$4' (pubspec.yaml)"
  else
    note_ok "$1" "$found"
  fi
}

read_version() {
  local pubspec="$root/pubspec.yaml"
  if [ ! -f "$pubspec" ]; then
    echo "FATAL: $pubspec not found" >&2
    exit 2
  fi
  full="$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*$/\1/p' "$pubspec" | head -n 1)"
  if [ -z "$full" ]; then
    echo "FATAL: no version: key in $pubspec" >&2
    exit 2
  fi
  if ! printf '%s' "$full" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$'; then
    echo "FATAL: pubspec version '$full' is not <major>.<minor>.<patch>+<build>" >&2
    exit 2
  fi
  semver="${full%%+*}"
  build="${full##*+}"
}

run_checks() {
  printf 'version guard - pubspec.yaml = %s (semver %s, build %s)\n' "$full" "$semver" "$build"

  case "$full" in
    0.*) note_ok "pubspec.yaml" "major 0.x (pre-1.0 rule)" ;;
    *) note_fail "pubspec.yaml" "'$full' - v1.0.0+ is forbidden before 1.0 (CLAUDE.md)" ;;
  esac

  expect CLAUDE.md "Current version" \
    's/^- Current version: `\([^`]*\)`.*$/\1/p' "$full"

  expect docs/changelog.md "Latest" \
    's/^- 最新版本 \/ Latest: \*\*v\([^*]*\)\*\*.*$/\1/p' "$full"

  expect docs/changelog.md "top section" \
    's/^## v\([^ ]*\) .*$/\1/p' "$full"

  local prev_section prev_marker
  prev_section="$(sed -n 's/^## v\([^ ]*\) .*$/\1/p' "$root/docs/changelog.md" 2>/dev/null | sed -n '2p')"
  prev_marker="$(extract docs/changelog.md 's/^- 上一版本 \/ Previous: \*\*v\([^*]*\)\*\*.*$/\1/p')"
  if [ -z "$prev_section" ] || [ -z "$prev_marker" ]; then
    note_fail docs/changelog.md "Previous: cannot derive (2nd section '$prev_section', marker '$prev_marker')"
  elif [ "$prev_marker" != "$prev_section" ]; then
    note_fail docs/changelog.md "Previous: '$prev_marker' != '$prev_section' (2nd '## v' section)"
  else
    note_ok docs/changelog.md "Previous: $prev_marker"
  fi

  expect docs/ROADMAP.md "Last updated" \
    's/^> Last updated \/ 最后更新: v\([^ ]*\) .*$/\1/p' "$full"

  expect docs/ROADMAP.md "Current" \
    's/^- 当前版本 \/ Current: \*\*v\([^*]*\)\*\*.*$/\1/p' "$full"

  expect docs/ROADMAP.md "Version row" \
    's/^| Version \/ 版本 | v\([^ ]*\) .*$/\1/p' "$full"

  if [ -n "$tag" ]; then
    if [ "$tag" = "v$semver" ]; then
      note_ok "release tag" "$tag"
    else
      note_fail "pubspec.yaml" "tag '$tag' != 'v$semver' - release would ship mislabelled artifacts"
    fi
  fi
}

escape_re() { printf '%s' "$1" | sed 's/\./\\./g; s/\+/\\+/g'; }

mutate() { # mutate <file> <sed-expr>
  local f="$1" expr="$2"
  sed "$expr" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

build_fixture() { # build_fixture <dir>
  rm -rf "$1"
  mkdir -p "$1/docs"
  local f real_full real_semver
  for f in pubspec.yaml CLAUDE.md docs/changelog.md docs/ROADMAP.md; do
    cp "$repo_root/$f" "$1/$f"
  done
  real_full="$(sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*$/\1/p' "$repo_root/pubspec.yaml" | head -n 1)"
  real_semver="${real_full%%+*}"
  # Neutralise the real version literals so the fixture stays valid across releases.
  for f in pubspec.yaml CLAUDE.md docs/changelog.md docs/ROADMAP.md; do
    sed -e "s/$(escape_re "$real_full")/0.99.9+9/g" \
        -e "s/$(escape_re "$real_semver")/0.99.9/g" "$1/$f" > "$1/$f.tmp"
    mv "$1/$f.tmp" "$1/$f"
  done
}

bump_fixture() { # bump_fixture <dir> - replay a correct release bump on the normalised fixture
  local fx="$1"
  mutate "$fx/pubspec.yaml" 's/^version: .*/version: 0.100.0+10/'
  mutate "$fx/CLAUDE.md" 's/`0.99.9+9`/`0.100.0+10`/'
  mutate "$fx/docs/changelog.md" 's/\*\*v0.99.9+9\*\*/**v0.100.0+10**/'
  mutate "$fx/docs/changelog.md" 's/^- 上一版本 \/ Previous: \*\*v[^*]*\*\*/- 上一版本 \/ Previous: **v0.99.9+9**/'
  mutate "$fx/docs/ROADMAP.md" 's/v0.99.9+9/v0.100.0+10/g'
  awk '{ if (!done && index($0, "## v0.99.9+9") == 1) { print "## v0.100.0+10 - Bump / 升版"; done = 1 } print }' \
    "$fx/docs/changelog.md" > "$fx/docs/changelog.md.tmp"
  mv "$fx/docs/changelog.md.tmp" "$fx/docs/changelog.md"
}

last_out=""
st_pass=0
st_fail=0

assert_guard() { # assert_guard <pass|fail> <desc> <root> [extra args...]
  local want="$1" desc="$2"
  shift 2
  local fx="$1"
  shift
  local rc out
  set +e
  out="$("$0" --root "$fx" "$@" 2>&1)"
  rc=$?
  set -e
  last_out="$out"
  if { [ "$want" = pass ] && [ "$rc" -eq 0 ]; } || { [ "$want" = fail ] && [ "$rc" -ne 0 ]; }; then
    st_pass=$((st_pass + 1))
    printf '  [ok]   selftest: %s\n' "$desc"
    return 0
  fi
  st_fail=$((st_fail + 1))
  printf '  [FAIL] selftest: %s - exit %s, wanted %s\n' "$desc" "$rc" "$want"
  printf '%s\n' "$out" | sed 's/^/           | /'
}

assert_mentions() {
  if printf '%s' "$last_out" | grep -q -- "$1"; then
    st_pass=$((st_pass + 1))
    printf '  [ok]   selftest: failure names %s\n' "$1"
  else
    st_fail=$((st_fail + 1))
    printf '  [FAIL] selftest: failure does not name %s\n' "$1"
    printf '%s\n' "$last_out" | sed 's/^/           | /'
  fi
}

run_selftest() {
  tmp="$(mktemp -d)"
  trap '[ -n "$tmp" ] && rm -rf "$tmp"' EXIT
  printf 'version guard selftest\n'

  build_fixture "$tmp/fx"
  assert_guard pass "consistent tree" "$tmp/fx"

  build_fixture "$tmp/fx"
  mutate "$tmp/fx/pubspec.yaml" 's/^version: .*/version: 0.99.0+99/'
  assert_guard fail "pubspec bumped, docs stale" "$tmp/fx"
  assert_mentions "CLAUDE.md"
  assert_mentions "docs/ROADMAP.md"
  assert_mentions "docs/changelog.md"

  build_fixture "$tmp/fx"
  mutate "$tmp/fx/CLAUDE.md" 's/^- Current version:/- Project version:/'
  assert_guard fail "CLAUDE.md marker reworded" "$tmp/fx"
  assert_mentions "marker missing"

  build_fixture "$tmp/fx"
  mutate "$tmp/fx/docs/changelog.md" 's/最新版本 \/ Latest:/最新版 \/ Latest:/'
  assert_guard fail "changelog Latest marker reworded" "$tmp/fx"

  build_fixture "$tmp/fx"
  mutate "$tmp/fx/docs/ROADMAP.md" 's/^- 当前版本 \/ Current:/- 版本 \/ Current:/'
  assert_guard fail "ROADMAP Current marker reworded" "$tmp/fx"

  build_fixture "$tmp/fx"
  mutate "$tmp/fx/docs/changelog.md" 's/^- 上一版本 \/ Previous: \*\*v[^*]*\*\*/- 上一版本 \/ Previous: **v0.0.1+1**/'
  assert_guard fail "changelog Previous out of step" "$tmp/fx"
  assert_mentions "Previous"

  build_fixture "$tmp/fx"
  mutate "$tmp/fx/pubspec.yaml" 's/^version: .*/version: 1.0.0+25/'
  assert_guard fail "1.0.0 rejected before 1.0" "$tmp/fx"

  build_fixture "$tmp/fx"
  bump_fixture "$tmp/fx"
  assert_guard pass "correctly bumped release commit" "$tmp/fx" --tag v0.100.0

  build_fixture "$tmp/fx"
  assert_guard pass "matching release tag" "$tmp/fx" --tag v0.99.9
  assert_guard fail "mismatched release tag" "$tmp/fx" --tag v0.99.8

  if [ "$st_fail" -ne 0 ]; then
    printf '\n❌ selftest FAILED - %s passed, %s failed\n' "$st_pass" "$st_fail"
    return 1
  fi
  printf '\n✅ selftest passed - %s case(s), guard is live\n' "$st_pass"
  return 0
}

if [ "$selftest" -eq 1 ]; then
  run_selftest
  exit $?
fi

read_version
run_checks

if [ "$fail" -ne 0 ]; then
  printf '\n❌ version guard FAILED - %s issue(s), %s ok\n' "$fail" "$passed"
  exit 1
fi
printf '\n✅ version guard passed - %s marker(s) match pubspec.yaml\n' "$passed"
