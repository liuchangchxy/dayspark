#!/bin/bash
# com.dayspark.app 的 release 产物必须由正式证书签名。
#
#   tool/check_apk_signer.sh <path/to/app-release.apk>
#   tool/check_apk_signer.sh --selftest
#
# `apksigner verify` 只证明「签名有效」——debug key 签的包同样有效，装到已装正式
# 版的手机上才会报签名冲突。所以这里比对证书 SHA-256 指纹，身份不对就红。
#
# 指纹不是秘密，就钉在 android/expected-signer.sha256。

set -euo pipefail

# apksigner 的输出格式随版本而异（`Signer #1 certificate DN: …` 与
# `Signer #1: certificate DN: …` 都出现过），所以取最后一个匹配冒号之后的内容。
parse_sha256() {
  sed -n 's/.*SHA-256 digest: *//p' | head -1 | tr -d '[:space:]'
}

parse_dn() {
  sed -n 's/.*certificate DN: *//p' | head -1
}

if [ "${1:-}" = "--selftest" ]; then
  want="409e139b75fa21d4d4199eafb9bd23c9fec57fbc88b9da8b70f40a832fe9bbf4"
  fail=0
  for sample in \
    "Signer #1 certificate SHA-256 digest: $want" \
    "Signer #1: certificate SHA-256 digest: $want" \
    "Signer #1 certificate SHA-256 digest:   $want  "; do
    got="$(printf '%s\n' "$sample" | parse_sha256)"
    if [ "$got" != "$want" ]; then
      echo "SELFTEST FAIL: parsed '$got' from '$sample'"
      fail=1
    fi
  done
  dn="$(printf '%s\n' "Signer #1: certificate DN: CN=DaySpark, O=DaySpark, C=CN" | parse_dn)"
  if [ "$dn" != "CN=DaySpark, O=DaySpark, C=CN" ]; then
    echo "SELFTEST FAIL: parsed DN '$dn'"
    fail=1
  fi
  if [ "$fail" -eq 1 ]; then
    exit 1
  fi
  echo "SELFTEST OK: parses both apksigner output shapes"
  exit 0
fi

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

certs="$("$apksigner_bin" verify --print-certs "$apk" 2>/dev/null)"
actual="$(printf '%s\n' "$certs" | parse_sha256)"
if [ -z "$actual" ]; then
  echo "FAIL: could not read the signer certificate from $apk"
  exit 1
fi

dn="$(printf '%s\n' "$certs" | parse_dn)"

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
