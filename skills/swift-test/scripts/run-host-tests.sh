#!/usr/bin/env bash
set -euo pipefail

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Error: xcrun is not available on PATH." >&2
  exit 1
fi

export PARCEL_INCLUDE_WASM_TESTS=0

xcrun swift test --parallel --scratch-path .build-xcode-tests "$@"
