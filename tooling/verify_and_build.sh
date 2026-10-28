#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../app"
flutter pub get
flutter analyze
flutter test
dart run tooling/check_core.dart
flutter build apk --release --split-per-abi --target-platform android-arm64
