#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../app"
python3 ../tooling/test_word_material.py
python3 ../tooling/prepare_kokoro.py
flutter pub get
flutter analyze
flutter test
dart run tooling/check_core.dart
flutter build apk --release --split-per-abi --target-platform android-arm64
