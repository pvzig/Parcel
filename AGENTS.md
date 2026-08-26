# AGENTS.md

Instructions for coding agents working on this repo.

## Orientation

[`SPEC.md`](SPEC.md) is the source of truth for Parcel's public API, behavior, and HTTP client
model. It is maintained as a description of what the code actually does, not as a wish list —
when you change behavior, update the matching SPEC bullet in the same change.

## Validation

Every change must pass both lanes. Run the Wasm lane first, then the host lane.

Inside Codex, prefer the globally installed `swift-build`, `swift-format`, and `swift-test`
skills. Everywhere else, run the commands below directly.

### Host lane

```sh
PARCEL_INCLUDE_WASM_TESTS=0 swift build --scratch-path .build-xcode-build
PARCEL_INCLUDE_WASM_TESTS=0 swift test --parallel --scratch-path .build-xcode-tests
```

### Wasm lane

The Wasm test target is only compiled when `PARCEL_INCLUDE_WASM_TESTS=1`, so host runs stay
native-only. The lane points JavaScriptKit's PackageToJS template at the vendored
[`Vendor/browser_wasi_shim`](Vendor/browser_wasi_shim) so validation does not need
`registry.npmjs.org`. The full command sequence is in
[SPEC.md](SPEC.md#validation) — run it verbatim.

### Formatting

```sh
swift-format format . --recursive --parallel -i
```

Formatting is part of validation. Also confirm `git diff --check` is clean.

## House rules

- Do not commit unless the human explicitly asks. Leave changes staged or in the working tree.
- Add tests with behavior changes: host tests for `Client` and body-coding logic using an injected
  `HTTPAPIs.HTTPClient`, Wasm tests for anything touching `FetchHTTPClient`. The JavaScript `fetch`
  shim the Wasm tests drive lives in [`Tests/prelude.mjs`](Tests/prelude.mjs).
- Keep `README.md` aimed at library users and `SPEC.md` aimed at implementers.
