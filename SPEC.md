# Parcel Spec

## Objective

Parcel is a small browser HTTP client for SwiftWASM that wraps the browser Fetch API with a Swift `Codable` interface.

## Public API

Parcel exposes:

- `Client`
- `ClientConfiguration`
- `JSONCodingConfiguration`
- `HTTPHeaders`
- `HTTPMethod`
- `HTTPRequest`
- `HTTPRequestOptions`
- `HTTPResponse`
- `DecodedResponse`
- `EmptyResponse`
- `Transport`
- `BrowserTransport`
- `ClientError`

## Behavior

- `Client` provides `get`, `head`, `delete`, `post`, `put`, `patch`, and generic `send` entry points.
- `Client` also provides `getResponse`, `headResponse`, `deleteResponse`, `postResponse`, `putResponse`, `patchResponse`, and `sendResponse` entry points that preserve response metadata.
- `Client.send(_ request: HTTPRequest)` exposes raw request execution while merging configured default headers without auto-injecting JSON request headers.
- `Client.sendResponse(_ request: HTTPRequest, expecting:)` decodes a caller-provided raw request while preserving the same default-header merge behavior as raw sends.
- Request bodies are encoded with `JSONEncoder`.
- Response bodies are decoded with `JSONDecoder`.
- `Client` does not inject `Accept` or `Content-Type` defaults for typed requests; callers must supply any content-negotiation headers explicitly.
- `HTTPHeaders` preserves repeated header values and resolves lookups case-insensitively.
- Per-call headers override default headers case-insensitively while preserving repeated values supplied by the call site.
- Typed `Client` entry points throw `ClientError.unsuccessfulStatusCode` for non-2xx responses before decoding.
- Empty successful responses can be decoded as `EmptyResponse`.
- `ClientConfiguration` allows callers to supply custom `JSONEncoder` / `JSONDecoder` factories.
- `Client` always decodes response bytes with the configured `JSONDecoder`.
- Successful typed responses preserve the raw `HTTPResponse.body` bytes while decoding from that same buffered body.
- Browser response-body promise rejections surface as `ClientError.responseBodyFailure`, preserving JavaScript error metadata for byte and text body reads.
- Browser request or response-body cancellation throws `CancellationError`.
- Browser request and response-body timeouts throw `ClientError.timedOut`.

## Transport Model

- Core request/response logic is transport-driven via `Transport`.
- `Transport.send(_:)` returns raw `HTTPResponse` values regardless of the HTTP status code.
- The default transport is `BrowserTransport` only on `wasm32` builds with a browser-capable JavaScript runtime.
- `BrowserTransport` uses the browser `fetch` API.
- `BrowserTransport.isSupportedRuntime` accepts both window and worker-style JavaScript global scopes when `fetch`, `AbortController`, `Object`, and `Uint8Array` are available.
- `BrowserTransport` installs JavaScriptKit's global event-loop executor when initialized in a supported runtime.
- `HTTPRequestOptions` carries browser fetch options for timeout, mode, credentials, and cache behavior.
- `BrowserTransport` maps `HTTPRequestOptions.mode`, `HTTPRequestOptions.credentials`, and `HTTPRequestOptions.cache` onto the browser fetch init object when present.
- `BrowserTransport` enforces `HTTPRequestOptions.timeout` with `AbortController` plus `setTimeout`.
- Because `BrowserTransport` buffers raw byte bodies, the generic client decode path handles empty-response and malformed-JSON behavior consistently for browser requests.
- Raw transport responses remain available as byte bodies via `arrayBuffer()`.
- `BrowserTransport` binds JavaScript instance method calls through JavaScriptKit member-call helpers so browser methods receive the correct `this` value.
- `BrowserTransport` threads an `AbortController` signal through `fetch` and response-body reads so Swift task cancellation aborts the browser request and body consumption.
- `BrowserTransport` currently buffers raw bodies with `arrayBuffer()` and does not yet expose streaming `ReadableStream` access.
- `BrowserTransport` does not retain temporary `JSClosure` bridges beyond synchronous JavaScript header iteration, using explicit release on JavaScriptKit no-weakrefs builds.
- `BrowserTransport` keeps the same raw API surface on unsupported builds, but all methods throw `ClientError.unsupportedPlatform`.
- `HTTPResponse` preserves status code, headers, final response URL, and optional byte body.

## Validation Model

- Host builds validate that Parcel compiles natively with `PARCEL_INCLUDE_WASM_TESTS=0 xcrun swift build --scratch-path .build-xcode-build`.
- Swift formatting runs through `swift-format format ... --recursive --parallel -i`.
- Host-side tests validate core `Client` behavior using injected mock transports.
- Wasm/JS tests validate `BrowserTransport` behavior through `swift package --swift-sdk ... js test`.
- Wasm tests run in Node with a repository prelude that provides a deterministic `fetch` shim for browser-oriented transport tests.
- The Wasm-only browser test target is only included when the Wasm validation script opts into it, so host `swift test` runs stay native-only.
- Full test validation runs the Wasm lane first, then the host lane.
