#!/usr/bin/env bash
set -euo pipefail

swift_sdk="${PARCEL_SWIFT_SDK:-swift-6.2.4-RELEASE_wasm}"
scratch_path=".build"
browser_wasi_shim_path="${PARCEL_BROWSER_WASI_SHIM_PATH:-$PWD/Vendor/browser_wasi_shim}"

export PARCEL_INCLUDE_WASM_TESTS=1

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: swift is not available on PATH." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Error: node is not available on PATH." >&2
  exit 1
fi

available_sdks="$(swift sdk list 2>/dev/null || true)"
if [[ -z "$available_sdks" ]] || ! printf '%s\n' "$available_sdks" | grep -Fxq "$swift_sdk"; then
  echo "Error: Swift SDK '$swift_sdk' is not installed." >&2
  if [[ -n "$available_sdks" ]]; then
    echo "Available Swift SDKs:" >&2
    echo "$available_sdks" >&2
  fi
  exit 1
fi

template_path="$scratch_path/checkouts/JavaScriptKit/Plugins/PackageToJS/Templates/package.json"
if [[ ! -f "$template_path" ]]; then
  swift package --scratch-path "$scratch_path" resolve >/dev/null
fi

swift package --scratch-path "$scratch_path" clean >/dev/null

rm -rf \
  "$scratch_path/plugins/PackageToJS/outputs/PackageTests" \
  "$scratch_path/plugins/PackageToJS/outputs/PackageTests.tmp"

chmod u+w "$template_path"
npm_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/parcel-npm-cache.XXXXXX")"

# JavaScriptKit's PackageToJS template hardcodes the browser_wasi_shim npm registry
# dependency. Point it at a repo-local compatibility shim so Wasm tests do not
# depend on registry.npmjs.org being reachable on the local network.
PACKAGE_TO_JS_TEMPLATE_PATH="$template_path" \
BROWSER_WASI_SHIM_PATH="$browser_wasi_shim_path" \
ruby -rjson -e '
  path = ENV.fetch("PACKAGE_TO_JS_TEMPLATE_PATH")
  package = JSON.parse(File.read(path))
  package.fetch("dependencies")["@bjorn3/browser_wasi_shim"] = "file:#{ENV.fetch("BROWSER_WASI_SHIM_PATH")}"
  File.write(path, JSON.pretty_generate(package) + "\n")
'

NPM_CONFIG_CACHE="$npm_cache_dir" \
swift package \
  --scratch-path "$scratch_path" \
  --swift-sdk "$swift_sdk" \
  js test \
  --default-platform node \
  --prelude ./Tests/prelude.mjs \
  -Xnode \
  --expose-gc \
  "$@"
