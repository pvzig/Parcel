---
name: swift-build
description: Build Parcel's host Swift package with the repo's standard scratch path and native-only target selection. Use when asked to build the package, verify it compiles, or run the host build lane before testing.
---

# Swift Build

## Overview

Run Parcel's host build lane with the bundled helper script.
Use this to confirm the package compiles natively without including the Wasm-only browser test target.

## Run Build

1. Run the helper script from the repository root:
   `./skills/swift-build/scripts/run-swift-build.sh`
2. Pass additional `swift build` flags when needed:
   `./skills/swift-build/scripts/run-swift-build.sh -c release`

## Script Behavior

- Executes:
  `PARCEL_INCLUDE_WASM_TESTS=0 xcrun swift build --scratch-path "$PARCEL_BUILD_SCRATCH_PATH"`
- Defaults `PARCEL_BUILD_SCRATCH_PATH` to `.build-xcode-build`.
- Forwards any extra CLI arguments to `swift build`.
- Exits with a clear error if `xcrun` is unavailable.

## Validate

Run:
`mise x python@3.12 -- python /Users/pvzig/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/swift-build`
