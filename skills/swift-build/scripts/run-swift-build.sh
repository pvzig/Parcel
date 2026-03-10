#!/usr/bin/env bash
set -euo pipefail

build_scratch_path="${PARCEL_BUILD_SCRATCH_PATH:-.build-xcode-build}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Error: xcrun is not available on PATH." >&2
  exit 1
fi

export PARCEL_INCLUDE_WASM_TESTS=0

xcrun swift build --scratch-path "$build_scratch_path" "$@"
