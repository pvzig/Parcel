# Parcel Spec

## Objective

Parcel is a typed Swift Wasm HTTP client. It owns request construction, body coding, response
buffering, and client defaults while upstream `FetchHTTPClient` owns browser HTTP execution.

## Package

- Parcel uses Swift 6.4 and the matching Wasm SDK pinned by `.swift-version` and CI.
- `swift-http-api-proposal` is pinned to the revision in `Package.swift` because no suitable stable
  release includes the required Wasm `FetchHTTPClient` changes.
- Browser builds require `HTTP_API_ENABLE_WASM=1`. Wasm tests additionally require
  `PARCEL_INCLUDE_WASM_TESTS=1`; host tests use `PARCEL_INCLUDE_WASM_TESTS=0`.
- Public `Client` construction is available only to browser-capable Wasm builds. Host builds exist
  to test Parcel through an internal `HTTPAPIs.HTTPClient` seam.

## Requests and responses

- `Client.send(_:)` returns the output inferred from `Client.Request<Output>`.
  `Client.response(_:)` also returns the `HTTPResponse` head, while `Client.raw(_:, body:)` accepts
  an `HTTPRequest` and returns its response head and buffered `Data` body.
- Typed request factories cover `GET`, `HEAD`, `DELETE`, `POST`, `PUT`, and `PATCH`. Constrained
  extensions may add named operations while preserving output inference.
- A request's body coding overrides `ClientConfiguration.defaultBodyCoding`. Typed calls add its
  `Accept` and, for requests with bodies, `Content-Type` only when the merged headers omit them.
  Raw calls do not add body-coding headers.
- Request headers replace configured defaults with the same case-insensitive name. Other defaults
  stay ahead of request headers, and repeated fields within either layer are preserved.
- `Client` requires typed requests to use an absolute URL with an authority and rejects bodies on
  typed and raw `GET` and `HEAD` requests with `ClientError.requestBodyNotAllowed`.
- Typed requests accept any 2xx status and reject other statuses before decoding. Raw requests
  return every status unchanged.
- `ClientConfiguration` contains immutable default headers, default body coding, and a nonnegative
  `maximumBufferedBodyBytes`, which defaults to 2 MiB.
- Parcel buffers response bodies within the HTTP client's scoped response handler. It stops reading
  at the first byte over the configured limit. Oversized success and raw bodies throw
  `ClientError.responseBodyTooLarge`; oversized non-2xx bodies preserve the status error with no
  text body.
- Empty successful bodies decode as `EmptyResponse`. Decoders that opt into empty bodies receive
  zero bytes; other output types throw `ClientError.emptyResponseBody`.
- Codec, transport, cancellation, and reader errors pass through unchanged.

## Body coding

- `BodyCoding` combines a `RequestBodyEncoder`, a `ResponseBodyDecoder`, and their optional
  default media types. Explicit `nil` or empty media-type arguments suppress automatic headers.
- Built-in coding supports JSON, form URL-encoded requests with JSON responses, plain text, and raw
  data.
- JSON coder factories run once per operation so mutable Foundation coders are not shared across
  concurrent calls.
- Form encoding supports flat keyed payloads and repeated keys for arrays. Nested keyed values,
  nested arrays, and `nil` array elements throw `EncodingError.invalidValue`.
- Form values follow HTML rules: spaces use `+`, `*` remains unescaped, `~` becomes `%7E`, and other
  non-safe UTF-8 bytes use uppercase percent escapes.
- Plain text uses strict UTF-8. Raw-data coding passes `Data` through unchanged.

## HTTP client boundary

- `Client(configuration:)` installs JavaScriptKit's global executor and owns an upstream
  `FetchHTTPClient`; Parcel does not expose bring-your-own-client construction.
- The response reader and its buffers never escape `HTTPClient.perform`'s response handler.
- Upstream buffers each request body before calling `fetch`; Parcel adds no upload-body limit.
- Parcel does not wrap `FetchHTTPClient` with a second browser transport or claim browser features
  that upstream does not expose.

## Validation

Run the Wasm lane first, then the host lane, formatting, and the diff check. The Wasm test target
uses `Tests/prelude.mjs` for deterministic Fetch fixtures and the vendored
`Vendor/browser_wasi_shim` package.

```sh
export HTTP_API_ENABLE_WASM=1
export PARCEL_INCLUDE_WASM_TESTS=1

swift_toolchain="$(TOOLCHAINS=org.swift.64202608141a xcrun --find swift)"
swift_sdk="${PARCEL_SWIFT_SDK:-swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_wasm}"
"$swift_toolchain" --version
"$swift_toolchain" sdk list | rg --fixed-strings --line-regexp "$swift_sdk"

"$swift_toolchain" package --scratch-path .build resolve

template_path=".build/checkouts/JavaScriptKit/Plugins/PackageToJS/Templates/package.json"
browser_wasi_shim_path="${PARCEL_BROWSER_WASI_SHIM_PATH:-$PWD/Vendor/browser_wasi_shim}"
chmod u+w "$template_path"
PACKAGE_TO_JS_TEMPLATE_PATH="$template_path" \
BROWSER_WASI_SHIM_PATH="$browser_wasi_shim_path" \
ruby -rjson -e '
  file_name = ENV.fetch("PACKAGE_TO_JS_TEMPLATE_PATH")
  package = JSON.parse(File.read(file_name))
  package.fetch("dependencies")["@bjorn3/browser_wasi_shim"] = "file:#{ENV.fetch("BROWSER_WASI_SHIM_PATH")}"
  File.write(file_name, JSON.pretty_generate(package) + "\n")
'

"$swift_toolchain" package --scratch-path .build \
  --swift-sdk "$swift_sdk" \
  js test --default-platform node --prelude ./Tests/prelude.mjs -Xnode --expose-gc
```

```sh
PARCEL_INCLUDE_WASM_TESTS=0 swift build --scratch-path .build-xcode-build
PARCEL_INCLUDE_WASM_TESTS=0 swift test --parallel --scratch-path .build-xcode-tests
/opt/homebrew/bin/swift-format format . --recursive --parallel -i
git diff --check
```
