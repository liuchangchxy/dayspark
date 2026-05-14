#!/bin/bash
# Checks that Linux build bundle doesn't require GLIBC > 2.35.
# Usage: tool/check_glibc_version.sh [path/to/bundle]
# Default bundle path: build/linux/x64/debug/bundle/

set -euo pipefail

bundle_dir="${1:-build/linux/x64/debug/bundle}"
max_ver="2.35"
fail=0

if ! command -v readelf &>/dev/null; then
  echo "SKIP: readelf not found (install binutils)"
  exit 0
fi

if [ ! -d "$bundle_dir" ]; then
  echo "SKIP: bundle dir not found: $bundle_dir"
  exit 0
fi

echo "::group::GLIBC version check"
echo "Bundle:  $bundle_dir"
echo "Max GLIBC: $max_ver"
echo ""

while IFS= read -r -d '' f; do
  readelf -h "$f" &>/dev/null || continue
  while IFS= read -r ver; do
    higher=$(printf '%s\n' "$ver" "$max_ver" | sort -V | tail -n1)
    if [ "$higher" = "$ver" ] && [ "$ver" != "$max_ver" ]; then
      echo "FAIL: $(basename "$f") requires GLIBC_$ver (max: $max_ver)"
      fail=1
    fi
  done < <(readelf -V "$f" 2>/dev/null | grep -oP 'GLIBC_\K[0-9]+\.[0-9]+' | sort -Vu)
done < <(find "$bundle_dir" -type f \( -name '*.so' -o -executable \) -print0 2>/dev/null)

echo ""
if [ "$fail" -eq 1 ]; then
  echo "❌ FAILED — some files exceed GLIBC_$max_ver"
  echo "::endgroup::"
  exit 1
fi
echo "✅ All GLIBC requirements ≤ $max_ver"
echo "::endgroup::"
