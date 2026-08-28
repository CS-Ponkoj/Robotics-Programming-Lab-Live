#!/usr/bin/env bash
set -euo pipefail

: "${API_BASE_URL:?Set API_BASE_URL to the deployed Render HTTPS URL.}"

FLUTTER_VERSION="3.32.8"
FLUTTER_ROOT="${TMPDIR:-/tmp}/flutter-${FLUTTER_VERSION}"

if [[ ! -x "${FLUTTER_ROOT}/bin/flutter" ]]; then
  git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_ROOT}"
fi

export PATH="${FLUTTER_ROOT}/bin:${PATH}"
flutter config --enable-web
pushd frontend >/dev/null
flutter pub get
flutter build web \
  --release \
  --dart-define="API_BASE_URL=${API_BASE_URL}"
popd >/dev/null
