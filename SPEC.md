# Parcel Spec

## Objective

Parcel is a small browser HTTP client for SwiftWASM that wraps the browser Fetch API with typed request and response codecs.

## Public API

Parcel exposes:

- `Client`
- `ClientConfiguration`
- `BodyCodec`
- `BodyCodingConfiguration`
- `JSONBodyCodec`
- `FormURLEncodedBodyCodec`
- `PlainTextBodyCodec`
- `RawDataBodyCodec`
- `swift-http-types` message-head types used directly by Parcel's public API, including
  `HTTPField`, `HTTPFields`, `HTTPRequest`, and `HTTPResponse`
- `DecodedResponse`
- `EmptyResponse`
- `Transport`
- `BrowserTransport` on `wasm32` builds that include Parcel's browser transport
- `ClientError`

## Behavior

- `Client` provides `get`, `head`, `delete`, `post`, `put`, `patch`, and generic `send` entry points that accept `Foundation.URL` request targets.
- `Client` also provides `getResponse`, `headResponse`, `deleteResponse`, `postResponse`, `putResponse`, `patchResponse`, and `sendResponse` entry points that preserve response metadata.
- `Client.send(_ request: HTTPRequest, body:timeout:)` exposes raw request execution while appending configured default header fields without auto-injecting codec-specific request headers.
- `Client.sendResponse(_ request: HTTPRequest, body:timeout:, expecting:)` decodes a caller-provided raw request while appending the configured default `Accept` header values when the request does not already provide them.
- Typed request bodies are encoded with the configured `BodyCodec`.
- Typed response bodies are decoded with the configured `BodyCodec`.
- `BodyCodingConfiguration` wraps a `BodyCodec` plus optional default `Content-Type` and `Accept` header values for typed requests.
- `BodyCodingConfiguration` provides convenience factories for JSON, form URL-encoded, plain-text, and raw-data body coding.
- `ClientConfiguration` also carries an optional `defaultTimeout`, which defaults to 90 seconds and is used whenever a per-call timeout is omitted.
- Typed `Client` request builders append the configured `Accept` header values when the request does not already provide `Accept`.
- Typed `Client` request builders append the configured `Content-Type` header when Parcel encodes the request body and the request does not already provide `Content-Type`.
- Parcel uses `swift-http-types` for HTTP method, status, request-head, response-head, and header
  field semantics instead of maintaining custom protocol primitives.
- `HTTPFields` preserves repeated header values and resolves lookups case-insensitively according to `swift-http-types`.
- Configured default header fields are appended ahead of per-call header fields without custom override logic.
- Typed `Client` entry points throw `ClientError.unsuccessfulStatusCode` for non-2xx responses before decoding.
- Empty successful responses can be decoded as `EmptyResponse`.
- `ClientConfiguration` allows callers to supply a default `BodyCodingConfiguration`; `BodyCodingConfiguration.json()` is the default implementation.
- `JSONBodyCodec` allows callers to supply custom `JSONEncoder` / `JSONDecoder` factories.
- `FormURLEncodedBodyCodec` supports flat top-level keyed payloads and repeated keys for array values, but does not support nested keyed containers.
- `PlainTextBodyCodec` encodes and decodes UTF-8 `String` values.
- `RawDataBodyCodec` encodes and decodes raw `Data` values.
- Successful typed responses preserve the raw response bytes and final response `URL?` on `DecodedResponse` while decoding from that same buffered body.
- Browser response-body promise rejections surface as `ClientError.responseBodyFailure`, preserving JavaScript error metadata for byte and text body reads.
- Browser request or response-body cancellation throws `CancellationError`.
- Browser request and response-body timeouts throw `ClientError.timedOut`.

## Transport Model

- Core request/response logic is transport-driven via `Transport`.
- `Transport.send(_:, body:timeout:)` returns raw `HTTPResponse` values plus buffered body bytes and the final response `URL?`, regardless of the HTTP status code.
- `Client(configuration:)` is only available when Parcel can select the built-in browser transport; host builds must inject an explicit `Transport`.
- `BrowserTransport` is only exposed on `wasm32` builds with Parcel's browser transport dependencies available.
- The default transport is `BrowserTransport` only on `wasm32` builds with a browser-capable JavaScript runtime.
- `BrowserTransport` uses the browser `fetch` API.
- `BrowserTransport.isSupportedRuntime` accepts both window and worker-style JavaScript global scopes when `fetch`, `AbortController`, `Object`, and `Uint8Array` are available.
- `BrowserTransport` installs JavaScriptKit's global event-loop executor when initialized in a supported runtime.
- `BrowserTransport` accepts an optional per-request timeout and enforces it with `AbortController` plus `setTimeout`.
- `BrowserTransport` passes outgoing headers to `fetch` as an ordered header-entry list so repeated field names preserve their semantics instead of collapsing to the last value.
- Because `BrowserTransport` buffers raw byte bodies, the generic client decode path handles empty-response and malformed-payload behavior consistently for browser requests regardless of the configured codec.
- Raw transport responses remain available as byte bodies via `arrayBuffer()`.
- `BrowserTransport` binds JavaScript instance method calls through JavaScriptKit member-call helpers so browser methods receive the correct `this` value.
- `BrowserTransport` threads an `AbortController` signal through `fetch` and response-body reads so Swift task cancellation aborts the browser request and body consumption.
- `BrowserTransport` currently buffers raw bodies with `arrayBuffer()` and does not yet expose streaming `ReadableStream` access.
- `BrowserTransport` does not retain temporary `JSClosure` bridges beyond synchronous JavaScript header iteration, using explicit release on JavaScriptKit no-weakrefs builds.
- `ClientError.unsupportedPlatform` remains reserved for `wasm32` builds where Parcel can compile but no browser-capable JavaScript runtime is available.

## Validation Model

- Host builds validate that Parcel compiles natively with `PARCEL_INCLUDE_WASM_TESTS=0 xcrun swift build --scratch-path .build-xcode-build`.
- Swift formatting runs through `swift-format format ... --recursive --parallel -i`.
- Host-side tests validate core `Client` behavior using injected mock transports.
- Wasm/JS tests validate `BrowserTransport` behavior through `swift package --swift-sdk ... js test`.
- Wasm tests run in Node with a repository prelude that provides a deterministic `fetch` shim for browser-oriented transport tests.
- The Wasm-only browser test target is only included when the Wasm validation script opts into it, so host `swift test` runs stay native-only.
- Full test validation runs the Wasm lane first, then the host lane.
