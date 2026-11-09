#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test --no-pub integration_test/app_test.dart -d macos
