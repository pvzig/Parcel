# Parcel Spec

## Objective

Parcel is a browser HTTP client for SwiftWASM that wraps the browser Fetch API with typed request and response codecs.

## Public API

Parcel exposes:

- `Client`
- `ClientConfiguration`
- `Client.Request`
- `Client.Response`
- `Client.Codec`
- `BodyCodec`
- `JSONBodyCodec`
- `FormURLEncodedBodyCodec`
- `PlainTextBodyCodec`
- `RawDataBodyCodec`
- `HTTPBody`
- `swift-http-types` message-head types used directly by Parcel's public API, including
  `HTTPField`, `HTTPFields`, `HTTPRequest`, and `HTTPResponse`
- `TransportResponse`
- `EmptyResponse`
- `Transport`
- `BrowserTransport` on `wasm32` builds that include Parcel's browser transport
- `ClientError`

## Behavior

- `Client.send(_:, as:codec:timeout:)` is Parcel's single typed request entry point.
- `Client.raw(_:, body:timeout:)` is Parcel's raw escape hatch for direct `HTTPRequest` execution.
- `Client.Request` models typed requests through an explicit method, URL, headers, and optional typed body.
- `Client.Request` provides convenience factories for `get`, `head`, `delete`, `post`, `put`, and `patch`.
- `Client.Response<Value>` preserves the decoded value, response head, and final response URL.
- `HTTPBody` is Parcel's async byte-stream abstraction for request and response bodies, with optional known length, iteration behavior, and helper collection APIs.
- `HTTPBody.collect(upTo:)` and `HTTPBody.text(upTo:)` default to a 2 MiB in-memory collection limit; callers can raise that limit or opt into `.max` explicitly.
- `Client.raw(_:, body:timeout:)` appends configured default header fields without auto-injecting codec-specific request headers.
- Raw request and response bodies travel separately from `swift-http-types` heads as `HTTPBody?`.
- Typed request bodies are encoded with the selected `Client.Codec` and wrapped in `HTTPBody`.
- Typed response bodies are decoded by collecting the response `HTTPBody` up to `maximumBufferedBodyBytes` and passing the resulting bytes through the selected `Client.Codec`.
- `Client.Codec` wraps a `BodyCodec` plus optional default `Content-Type` and `Accept` header values for typed requests.
- `Client.Codec` provides convenience factories for JSON, form URL-encoded, plain-text, raw-data, and custom body coding.
- `ClientConfiguration` also carries an optional `defaultTimeout`, which defaults to 90 seconds and is used whenever a per-call timeout is omitted.
- `ClientConfiguration` also carries `maximumBufferedBodyBytes`, which defaults to 2 MiB and is used when Parcel must buffer response bytes in memory for decoding or error reporting.
- `ClientConfiguration` carries a default `Client.Codec`; `Client.Codec.json()` is the default implementation.
- Typed requests append the selected codec's `Accept` header values only when the merged client-default and per-request headers do not already provide `Accept`.
- Typed requests append the selected codec's `Content-Type` header only when Parcel encodes the request body and the merged client-default and per-request headers do not already provide `Content-Type`.
- Parcel uses `swift-http-types` for HTTP method, status, request-head, response-head, and header
  field semantics instead of maintaining custom protocol primitives.
- `HTTPFields` preserves repeated header values and resolves lookups case-insensitively according to `swift-http-types`.
- Configured default header fields are appended ahead of per-call header fields without custom override logic.
- Typed `Client.send` throws `ClientError.unsuccessfulStatusCode` for non-2xx responses before decoding.
- Empty successful responses can be decoded as `EmptyResponse`.
- `JSONBodyCodec` allows callers to supply custom `JSONEncoder` / `JSONDecoder` factories.
- `FormURLEncodedBodyCodec` supports flat top-level keyed payloads and repeated keys for array values, but does not support nested keyed containers.
- `PlainTextBodyCodec` encodes and decodes UTF-8 `String` values.
- `RawDataBodyCodec` encodes and decodes raw `Data` values.
- Successful typed responses preserve the final response `URL?` on `Client.Response`, but typed decoding consumes the response body and does not preserve raw response bytes afterward.
- Browser response-body promise rejections from streamed byte reads surface as `ClientError.responseBodyFailure`, preserving JavaScript error metadata with the `.bytes` operation.
- Browser request or response-body cancellation throws `CancellationError`.
- Browser request and response-body timeouts throw `ClientError.timedOut`.

## Transport Model

- Core request/response logic is transport-driven via `Transport`.
- `Transport.send(_:, body:timeout:)` returns `TransportResponse`, which contains a raw `HTTPResponse`, an optional `HTTPBody`, and the final response `URL?`, regardless of the HTTP status code.
- `Client(configuration:)` is only available on `wasm32` builds that include Parcel's browser transport dependencies; host builds must inject an explicit `Transport`.
- `BrowserTransport` is only exposed on `wasm32` builds with Parcel's browser transport dependencies available.
- The default transport is `BrowserTransport` only on `wasm32` builds with a browser-capable JavaScript runtime.
- `BrowserTransport` uses the browser `fetch` API.
- `BrowserTransport.isSupportedRuntime` accepts both window and worker-style JavaScript global scopes when `fetch`, `AbortController`, `Object`, and `Uint8Array` are available.
- `BrowserTransport` installs JavaScriptKit's global event-loop executor when initialized in a supported runtime.
- `BrowserTransport` accepts an optional per-request timeout and enforces it with `AbortController` plus `setTimeout`.
- `BrowserTransport` passes outgoing headers to `fetch` as an ordered header-entry list so repeated field names preserve their semantics instead of collapsing to the last value.
- Because typed decoding collects response bytes from `HTTPBody`, the generic client decode path handles empty-response and malformed-payload behavior consistently for browser requests regardless of the configured codec.
- Raw transport responses remain available as `HTTPBody?`, which may be single-iteration depending on the transport.
- `BrowserTransport` binds JavaScript instance method calls through JavaScriptKit member-call helpers so browser methods receive the correct `this` value.
- `BrowserTransport` threads an `AbortController` signal through `fetch` and response-body reads so Swift task cancellation aborts the browser request and body consumption.
- `BrowserTransport` exposes response bodies lazily as single-iteration `HTTPBody` values backed by `ReadableStream.getReader()`.
- `BrowserTransport` preserves `Response.body == null` as `TransportResponse.body == nil`.
- `BrowserTransport` cancels abandoned `ReadableStream` readers when a streamed response body is dropped before it reaches end-of-stream.
- `BrowserTransport` currently buffers outgoing request bodies before passing them to `fetch`; streaming uploads are not yet exposed, and the buffer is capped by `maximumBufferedRequestBodyBytes` (2 MiB by default).
- `BrowserTransport` does not retain temporary `JSClosure` bridges beyond synchronous JavaScript header iteration, using explicit release on JavaScriptKit no-weakrefs builds.
- `ClientError.unsupportedPlatform` remains reserved for `wasm32` builds where Parcel can compile but no browser-capable JavaScript runtime is available.

## Validation

Parcel follows the same broad validation split as JavaScriptKit:

- A host build lane verifies that Parcel compiles natively without Wasm-only browser tests.
- Swift formatting is part of validation and runs through the global Codex `swift-format`
  skill.
- Wasm/JS tests are the primary runtime validation lane for `BrowserTransport`.
- Host-side tests validate core `Client` behavior using injected mock transports.
- The Wasm-only browser test target is only included when the Wasm validation lane opts into
  it, so host `swift test` runs stay native-only.
- Full test validation runs the Wasm lane first, then the host lane.
- The host build and host test lanes set `PARCEL_INCLUDE_WASM_TESTS=0`.
- The Wasm lane sets `PARCEL_INCLUDE_WASM_TESTS=1` and uses `swift package --swift-sdk ... js test`.
- Wasm tests run in Node with the repository prelude in [`Tests/prelude.mjs`](Tests/prelude.mjs), which provides a deterministic `fetch` shim for browser-oriented transport tests.
- Wasm test packaging points JavaScriptKit's PackageToJS template at
  [`Vendor/browser_wasi_shim`](Vendor/browser_wasi_shim) so validation does not depend on
  `registry.npmjs.org` being reachable for `@bjorn3/browser_wasi_shim`.
- Parcel targets Swift 6.3.0 for host builds and SwiftPM uses `swift-tools-version: 6.3`.
- Parcel depends on JavaScriptKit `0.50.2` or newer for Swift 6.3-compatible
  JavaScript event-loop executor support.
- By default, the Wasm lane expects the `swift-6.3-RELEASE_wasm` SDK; override that with `PARCEL_SWIFT_SDK` when needed.

Codex agents should use globally installed Codex skills rather than repo-local `./skills`
scripts:

- Run the host build lane with the global Codex `swift-build` skill when it is
  available. Outside Codex, or when that skill is unavailable, run:

```sh
PARCEL_INCLUDE_WASM_TESTS=0 swift build --scratch-path .build-xcode-build
```

- Run the formatter with the global Codex `swift-format` skill. Outside Codex, run:

```sh
swift-format format . --recursive --parallel -i
```

- Run the full test flow by running the Wasm lane first and then the host lane.

```sh
# Run the Wasm lane below first, then:
PARCEL_INCLUDE_WASM_TESTS=0 swift test --parallel --scratch-path .build-xcode-tests
```

- Run only the Wasm test lane with:

```sh
export PARCEL_INCLUDE_WASM_TESTS=1

swift package --scratch-path .build resolve

template_path=".build/checkouts/JavaScriptKit/Plugins/PackageToJS/Templates/package.json"
browser_wasi_shim_path="${PARCEL_BROWSER_WASI_SHIM_PATH:-$PWD/Vendor/browser_wasi_shim}"
PACKAGE_TO_JS_TEMPLATE_PATH="$template_path" \
BROWSER_WASI_SHIM_PATH="$browser_wasi_shim_path" \
ruby -rjson -e '
  path = ENV.fetch("PACKAGE_TO_JS_TEMPLATE_PATH")
  package = JSON.parse(File.read(path))
  package.fetch("dependencies")["@bjorn3/browser_wasi_shim"] = "file:#{ENV.fetch("BROWSER_WASI_SHIM_PATH")}"
  File.write(path, JSON.pretty_generate(package) + "\n")
'

rm -rf \
  .build/plugins/PackageToJS/outputs/PackageTests \
  .build/plugins/PackageToJS/outputs/PackageTests.tmp

PARCEL_INCLUDE_WASM_TESTS=1 swift package --scratch-path .build --swift-sdk "${PARCEL_SWIFT_SDK:-swift-6.3-RELEASE_wasm}" js test --default-platform node --prelude ./Tests/prelude.mjs -Xnode --expose-gc
```

- Run only the host test lane with the global Codex `swift-test` skill after setting
  `PARCEL_INCLUDE_WASM_TESTS=0`. Outside Codex, run:

```sh
PARCEL_INCLUDE_WASM_TESTS=0 swift test --parallel --scratch-path .build-xcode-tests
```
