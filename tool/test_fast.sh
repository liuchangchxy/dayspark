#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test --no-pub test/domain test/ui/journeys_test.dart test/ui/pages/home/master_detail_test.dart
