#!/bin/bash
# com.dayspark.app 的 release 产物必须由正式证书签名。
#
#   tool/check_apk_signer.sh <path/to/app-release.apk>
#
# `apksigner verify` 只证明「签名有效」——debug key 签的包同样有效，装到已装正式
# 版的手机上才会报签名冲突。所以这里比对证书 SHA-256 指纹，身份不对就红。
#
# 指纹不是秘密，就钉在 android/expected-signer.sha256。

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apk="${1:-$root/build/app/outputs/flutter-apk/app-release.apk}"
expected_file="$root/android/expected-signer.sha256"

if [ ! -f "$apk" ]; then
  echo "FAIL: APK not found: $apk"
  exit 1
fi
if [ ! -f "$expected_file" ]; then
  echo "FAIL: expected signer file not found: $expected_file"
  exit 1
fi

expected="$(tr -d '[:space:]' < "$expected_file")"
if [ -z "$expected" ]; then
  echo "FAIL: $expected_file is empty"
  exit 1
fi

apksigner_bin="$(command -v apksigner || true)"
if [ -z "$apksigner_bin" ]; then
  apksigner_bin="$(command -v apksigner.bat || true)"
fi
if [ -z "$apksigner_bin" ]; then
  for candidate in "${ANDROID_HOME:-}/build-tools" "${ANDROID_SDK_ROOT:-}/build-tools"; do
    [ -d "$candidate" ] || continue
    newest="$(ls -1 "$candidate" | sort -V | tail -n1)"
    for exe in apksigner apksigner.bat; do
      if [ -n "$newest" ] && [ -f "$candidate/$newest/$exe" ]; then
        apksigner_bin="$candidate/$newest/$exe"
        break 2
      fi
    done
  done
fi
if [ -z "$apksigner_bin" ]; then
  echo "FAIL: apksigner not found (install Android build-tools)"
  exit 1
fi

if ! "$apksigner_bin" verify "$apk" >/dev/null 2>&1; then
  echo "FAIL: APK signature is missing or invalid: $apk"
  echo "A release APK must be signed at build time by Gradle, never re-signed afterwards."
  exit 1
fi

actual="$(echo | "$apksigner_bin" verify --print-certs "$apk" 2>/dev/null \
  | awk -F': ' '/certificate SHA-256 digest/ {print $2; exit}' | tr -d '[:space:]')"
if [ -z "$actual" ]; then
  echo "FAIL: could not read the signer certificate from $apk"
  exit 1
fi

dn="$(echo | "$apksigner_bin" verify --print-certs "$apk" 2>/dev/null \
  | awk -F': ' '/certificate DN/ {print $2; exit}')"

echo "APK:      $apk"
echo "Signer:   ${dn:-unknown}"
echo "SHA-256:  $actual"
echo "Expected: $expected"

if [ "$actual" != "$expected" ]; then
  echo ""
  echo "FAIL: wrong signing identity for com.dayspark.app."
  echo "A build signed with any other key (including the debug key) installs over the"
  echo "production app only after uninstalling it, which wipes local data."
  exit 1
fi

echo ""
echo "OK: signed by the production DaySpark certificate"
