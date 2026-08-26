# Parcel Spec

## Objective

Parcel is a typed Swift Wasm HTTP client. It owns request/response body coding and client-wide
defaults while delegating HTTP execution to the Swift HTTP API proposal. Browser-capable Wasm builds
use upstream `FetchHTTPClient`; Parcel does not maintain a parallel browser transport.

## Public API

Parcel exposes:

- `Client`
- `ClientConfiguration`
- `Client.Request<Output>`
- `Client.Response<Value>`
- `Client.RawResponse`
- `Client.BodyCoding`
- `RequestBodyEncoder`
- `ResponseBodyDecoder`
- `JSONBodyEncoder` and `JSONBodyDecoder`
- `FormURLEncodedBodyEncoder`
- `PlainTextBodyEncoder` and `PlainTextBodyDecoder`
- `RawDataBodyEncoder` and `RawDataBodyDecoder`
- `EmptyResponse`
- `ClientError`
- `swift-http-types` message-head types used by its signatures, including `HTTPField`, `HTTPFields`,
  `HTTPRequest`, and `HTTPResponse`

## Toolchain and dependencies

- The package uses `swift-tools-version: 6.4` and is pinned by `.swift-version` to the
  `6.4.x-snapshot-2026-08-14` toolchain.
- Wasm validation uses the matching
  `swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_wasm` Swift SDK.
- Parcel depends on `swift-http-api-proposal` revision
  `5a0eb4340a4f0875a59a5aef9e4fe6c307fbd1e7`, the exact head of upstream PR #183. That revision
  removes FetchHTTPClient's direct Foundation dependency and makes the upstream Wasm client
  Embedded-Swift-buildable; both properties are required to keep FetchHTTPClient's linked Wasm
  footprint appropriate for Parcel. The proposal has no stable release suitable for a
  semantic-version requirement yet.
- Parcel depends directly on `swift-http-types` 1.6.0 or newer, `swift-collections` 1.6.0 or newer
  for the host HTTP-client test fixture, and JavaScriptKit 0.58.0 or newer.
- The package requires macOS 26 or newer for host builds because the pinned HTTP API proposal marks
  its public client API with the corresponding Apple-platform availability.
- Upstream exposes `FetchHTTPClient` only when `HTTP_API_ENABLE_WASM` exists in the environment.
  Parcel requires that variable whenever `PARCEL_INCLUDE_WASM_TESTS=1` and fails manifest loading
  otherwise.

## Client behavior

- `Client.send(_:)` returns the decoded `Output` inferred from `Client.Request<Output>`.
- `Client.response(_:)` sends the same typed request and returns `Client.Response<Output>` when
  callers need the decoded value together with the `HTTPResponse` head. Named operations provide
  their output type directly; an explicit `Client.Response<Output>` assignment can provide type
  context for an ad-hoc request.
- `Client.raw(_:, body:)` accepts an `HTTPRequest` and optional `Data`, then returns
  `Client.RawResponse` with the `HTTPResponse` head and buffered `Data` body.
- `Client.Request<Output>` is a `Sendable` typed operation containing the output type, method, URL,
  headers, optional `Encodable & Sendable` body, and optional per-operation body coding.
- Convenience factories cover `get`, `head`, `delete`, `post`, `put`, and `patch`. Constrained
  extensions may define named operations that preserve output inference.
- Typed request bodies are encoded to `Data` with the effective body coding. Operation-specific
  body coding takes precedence over `ClientConfiguration.defaultBodyCoding`.
- Raw calls merge configured default headers but do not add body-coding-specific `Accept` or
  `Content-Type` fields.
- Typed calls add the effective body coding's `Accept` values only when merged headers do not
  already contain `Accept`. They add its `Content-Type` only when the request has a body and merged
  headers do not already contain `Content-Type`.
- Per-request fields replace configured default fields with the same case-insensitive name;
  defaults for other names remain ahead of per-request fields. Repeated values within one layer are
  preserved.
- Typed sends validate the URL before constructing `HTTPRequest`. Relative URLs and schemes without
  an authority, such as `mailto:` and `file:`, throw `ClientError.invalidRequestURL`.
- Typed sends and `Client.raw` reject `GET` and `HEAD` bodies with
  `ClientError.requestBodyNotAllowed`.
- Typed success is any 2xx status. Non-2xx typed responses throw
  `ClientError.unsuccessfulStatusCode` before decoding; raw responses return any status unchanged.
- `Client.Response`, returned only by `Client.response`, preserves the decoded value and response
  head. It does not preserve raw bytes or the final response URL.
- `ClientConfiguration` is immutable and contains default headers, default body coding, and
  `maximumBufferedBodyBytes`. The buffer limit defaults to 2 MiB and must be nonnegative.
- Parcel buffers successful, error, and raw response bodies inside the scoped HTTP response handler.
  Success and raw responses exceeding the limit throw
  `ClientError.responseBodyTooLarge(maximumBytes:)`.
- Parcel continues draining an oversized reader to its terminal state. For non-2xx typed responses,
  an oversized body produces `ClientError.unsuccessfulStatusCode` with a `nil` text body, preserving
  the more useful status failure.
- Empty successful responses decode as `EmptyResponse`. Decoders declaring
  `decodesEmptyResponseBodies == true`, currently plain text and raw data, receive zero bytes. Other
  output types throw `ClientError.emptyResponseBody`.
- Encoding and decoding errors pass through unchanged. HTTP client request, network, cancellation,
  and reader errors also pass through unchanged.

## Body coding

- `Client.BodyCoding` combines a `RequestBodyEncoder`, a `ResponseBodyDecoder`, and the optional
  default `Content-Type` and `Accept` values they own.
- Initializers that omit media-type arguments adopt the components' declarations. Initializers that
  explicitly pass `nil` or `[]` preserve those values, allowing either automatic header to be
  suppressed.
- `ResponseBodyDecoder.decodesEmptyResponseBodies` has a conservative `false` protocol-extension
  default.
- Built-in factories cover JSON, form URL-encoded requests with JSON responses, plain text, and raw
  data.
- `JSONBodyEncoder` and `JSONBodyDecoder` are immutable, `Sendable` descriptions with coder
  factories. Each factory runs once per operation so mutable Foundation coders are never shared
  between concurrent calls.
- `FormURLEncodedBodyEncoder` supports flat top-level keyed payloads and repeated keys for arrays.
  Nested keyed values, nested arrays including empty ones, and `nil` array elements throw
  `EncodingError.invalidValue` instead of silently changing shape.
- Form encoding follows HTML form rules: spaces become `+`, `*` stays unescaped, `~` becomes `%7E`,
  and other non-safe UTF-8 bytes use uppercase percent escapes.
- `.formURLEncoded()` sends `application/x-www-form-urlencoded` and accepts JSON by default. Callers
  may supply another response decoder.
- `PlainTextBodyEncoder` accepts `String` and writes UTF-8. `PlainTextBodyDecoder` returns `String`
  and throws `DecodingError.dataCorrupted` for invalid UTF-8.
- Raw-data components accept and return `Data` unchanged.

## HTTP client model

- Public construction is limited to `Client(configuration:)` on browser-capable Wasm builds with
  `HTTP_API_ENABLE_WASM=1`. It installs JavaScriptKit's global executor and owns
  `FetchHTTPClient()`.
- Parcel does not expose `HTTPAPIs.HTTPClient` injection as public API. The internal initializer
  converts a concrete, reference-semantic HTTP client into a private `@Sendable` request closure so
  the Fetch-backed initializer and deterministic host tests share the same request path.
- The internal initializer accepts `some HTTPClient & AnyObject`. The concrete client is captured
  directly and may receive concurrent calls, so its conformance owns synchronization for mutable
  state.
- Parcel supplies `httpClient.defaultRequestOptions` and converts optional request `Data` to
  `HTTPClientRequestBody<Writer>.data`.
- Response collection, status validation inputs, and response decoding bytes are obtained during
  `HTTPClient.perform`'s scoped response handler. Neither the `AsyncReader` nor its buffers escape.
- Reader collection handles `EitherError<Reader.ReadFailure, Never>` by unwrapping the reader-side
  failure after the infallible buffer callback.
- Host builds cannot publicly construct `Client`; native compilation exists to exercise Parcel's
  core behavior through the internal transport seam.

## Upstream Fetch boundary

- `FetchHTTPClient` owns all JavaScript Fetch bridging, request-header conversion, response-header
  conversion, and `ReadableStream` access.
- Its current request writer buffers the complete upload before invoking `fetch`; Parcel adds no
  second request-body limit.
- The pinned upstream implementation currently uses only its empty request-options type. It does not
  expose Fetch credentials/mode/cache/redirect options, per-request timeouts, AbortController task
  cancellation propagation, or the final redirect URL.
- The pinned implementation assumes `Response.body` is non-null. Wasm fixtures therefore return an
  empty `ReadableStream` for zero-byte responses instead of `null`.
- These are upstream capability boundaries. Parcel does not emulate them with another browser
  transport or advertise guarantees that the underlying client does not provide.

## Validation

Run the Wasm lane first, then the host lane, format, and check the diff.

The Wasm-only test target is included only when `PARCEL_INCLUDE_WASM_TESTS=1`; the host test target is
included otherwise. The browser target names `FetchHTTPClient` directly so PackageToJS discovers and
links its BridgeJS skeleton, and it links `JavaScriptEventLoopTestSupport` so async tests start on the
JavaScript event-loop executor. `Tests/prelude.mjs` provides deterministic `fetch`, response headers,
and `ReadableStream` fixtures. PackageToJS uses the vendored `Vendor/browser_wasi_shim` package.

CI pins the host and Wasm jobs to the exact Swift 6.4 snapshot container digest. The matching Wasm
SDK ID, official download URL, and SHA-256 checksum are checked into the workflow rather than stored
as independently mutable repository variables. A Swift upgrade must update that compiler/SDK
contract together.

```sh
export HTTP_API_ENABLE_WASM=1
export PARCEL_INCLUDE_WASM_TESTS=1

swift package --scratch-path .build resolve

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

swift package --scratch-path .build \
  --swift-sdk "${PARCEL_SWIFT_SDK:-swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a_wasm}" \
  js test --default-platform node --prelude ./Tests/prelude.mjs -Xnode --expose-gc
```

```sh
PARCEL_INCLUDE_WASM_TESTS=0 swift build --scratch-path .build-xcode-build
PARCEL_INCLUDE_WASM_TESTS=0 swift test --parallel --scratch-path .build-xcode-tests
swift-format format . --recursive --parallel -i
git diff --check
```
