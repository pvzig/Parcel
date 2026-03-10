# Parcel Spec

## Objective

Parcel is a small browser HTTP client for SwiftWASM that wraps the browser Fetch API with a Swift `Codable` interface.

## Public API

Parcel exposes:

- `Client`
- `ClientConfiguration`
- `JSONCodingConfiguration`
- `HTTPMethod`
- `HTTPRequest`
- `HTTPResponse`
- `DecodedResponse`
- `EmptyResponse`
- `Transport`
- `BrowserTransport`
- `ClientError`

## Behavior

- `Client` provides `get`, `delete`, `post`, `put`, `patch`, and generic `send` entry points.
- `Client` also provides `getResponse`, `deleteResponse`, `postResponse`, `putResponse`, `patchResponse`, and `sendResponse` entry points that preserve response metadata.
- Request bodies are encoded with `JSONEncoder`.
- Response bodies are decoded with `JSONDecoder`.
- `Accept: application/json` is added automatically unless the caller already supplies an `Accept` header.
- `Content-Type: application/json` is added automatically for requests with encoded JSON bodies unless the caller already supplies a `Content-Type` header.
- Per-call headers override default headers case-insensitively.
- Typed `Client` entry points throw `ClientError.unsuccessfulStatusCode` for non-2xx responses before decoding.
- Empty successful responses can be decoded as `EmptyResponse`.
- `ClientConfiguration` allows callers to supply custom `JSONEncoder` / `JSONDecoder` factories.
- When `prefersTransportSpecificResponseDecoding` is `true` and the active transport supports it, `Client` uses the transport's typed decode path instead of round-tripping successful JSON through `Data`.
- When `prefersTransportSpecificResponseDecoding` is `false`, `Client` always decodes response bytes with the configured `JSONDecoder`.
- Browser response-body promise rejections surface as `ClientError.responseBodyFailure`, preserving JavaScript error metadata for body reads and `response.json()`.
- Browser request or response-body cancellation throws `CancellationError`.

## Transport Model

- Core request/response logic is transport-driven via `Transport`.
- `Transport.send(_:)` returns raw `HTTPResponse` values regardless of the HTTP status code.
- The default transport is `BrowserTransport` only on `wasm32` builds with a browser-capable JavaScript runtime.
- `BrowserTransport` uses the browser `fetch` API.
- `BrowserTransport.isSupportedRuntime` accepts both window and worker-style JavaScript global scopes when `fetch`, `AbortController`, `Object`, and `Uint8Array` are available.
- `BrowserTransport` installs JavaScriptKit's global event-loop executor when initialized in a supported runtime.
- For typed client requests, `BrowserTransport` decodes successful JSON responses via `response.json()` and `JSValueDecoder`.
- Raw transport responses remain available as byte bodies via `arrayBuffer()`.
- `BrowserTransport` binds JavaScript instance method calls through JavaScriptKit member-call helpers so browser methods receive the correct `this` value.
- `BrowserTransport` threads an `AbortController` signal through `fetch` and response-body reads so Swift task cancellation aborts the browser request and body consumption.
- `BrowserTransport` currently buffers raw bodies with `arrayBuffer()` and does not yet expose streaming `ReadableStream` access.
- `BrowserTransport` does not retain temporary `JSClosure` bridges beyond synchronous JavaScript header iteration, using explicit release on JavaScriptKit no-weakrefs builds.
- `BrowserTransport` keeps the same typed API surface on unsupported builds, but all methods throw `ClientError.unsupportedPlatform`.
- `HTTPResponse` preserves status code, headers, final response URL, and optional byte body.

## Validation Model

- Host builds validate that Parcel compiles natively with `PARCEL_INCLUDE_WASM_TESTS=0 xcrun swift build --scratch-path .build-xcode-build`.
- Swift formatting runs through `swift-format format ... --recursive --parallel -i`.
- Host-side tests validate core `Client` behavior using injected mock transports.
- Wasm/JS tests validate `BrowserTransport` behavior through `swift package --swift-sdk ... js test`.
- Wasm tests run in Node with a repository prelude that provides a deterministic `fetch` shim for browser-oriented transport tests.
- The Wasm-only browser test target is only included when the Wasm validation script opts into it, so host `swift test` runs stay native-only.
- Full test validation runs the Wasm lane first, then the host lane.
