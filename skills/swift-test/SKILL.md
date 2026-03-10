---
name: swift-test
description: Run Parcel's validation test lanes. Use when asked to execute project tests, verify implementation changes, or run the Swift test suite before commit.
---

# Swift Test

## Overview

Run Parcel's Wasm-first test suite and its host-only test suite with the repo's bundled scripts.
Use the coordinator script for full validation, or the lane-specific scripts when you need to scope execution.

## Run Tests

1. Run the helper script from the target repository root:
   `./skills/swift-test/scripts/run-swift-tests.sh`
2. Run only the Wasm/JS lane when needed:
   `./skills/swift-test/scripts/run-swift-tests.sh --wasm-only`
3. Run only the host lane or pass host-only `swift test` flags when needed:
   `./skills/swift-test/scripts/run-swift-tests.sh --host-only`
   `./skills/swift-test/scripts/run-swift-tests.sh --filter ParcelHostTests`

## Script Behavior

- Default execution runs:
  `./skills/swift-test/scripts/run-wasm-tests.sh`
  followed by
  `./skills/swift-test/scripts/run-host-tests.sh`
- The Wasm lane uses:
  `PARCEL_INCLUDE_WASM_TESTS=1 swift package --scratch-path .build --swift-sdk "$PARCEL_SWIFT_SDK" js test --prelude ./Tests/prelude.mjs -Xnode --expose-gc`
- The host lane uses:
  `PARCEL_INCLUDE_WASM_TESTS=0 xcrun swift test --parallel --scratch-path .build-xcode-tests`
- Passing plain extra CLI flags to `run-swift-tests.sh` forwards them to the host lane only.
- Override the Wasm SDK with `PARCEL_SWIFT_SDK`; the default is `swift-6.2.4-RELEASE_wasm`.
- Exit with a clear error if the required toolchain pieces or Wasm SDK are unavailable.

## Validate

Run:
`mise x python@3.12 -- python /Users/pvzig/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/swift-test`
