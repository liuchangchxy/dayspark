#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tool/check_whitespace.py
python3 tool/scan_hardcoded_paths.py
tool/check_version_consistency.sh
tool/check_version_consistency.sh --selftest
flutter pub get
for package in packages/dayspark_contracts packages/dayspark_recurrence server tool/mcp_stdio_wrapper tool/dayspark_cli; do
  (cd "$package" && dart pub get)
done
for package in packages/dayspark_contracts packages/dayspark_recurrence server; do
  (cd "$package" && dart analyze . && dart test)
done
for package in tool/mcp_stdio_wrapper tool/dayspark_cli; do
  (cd "$package" && dart test)
done
flutter gen-l10n
flutter analyze --no-pub
flutter test --no-pub
tool/test_ui.sh
flutter build macos --release --no-pub
codesign --verify --deep --strict --verbose=2 build/macos/Build/Products/Release/DaySpark.app
