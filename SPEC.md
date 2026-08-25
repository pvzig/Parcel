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
- `BrowserRequestOptions`
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
- Typed response handling keeps status validation, bounded body collection, and value decoding as distinct stages. Successful response bodies are collected up to `maximumBufferedBodyBytes` and the resulting bytes pass through the selected `Client.Codec`.
- `Client.send` validates the request URL before constructing the HTTP request and throws `ClientError.invalidRequestURL` for URLs that are not absolute request targets: schemeless (relative) URLs, which would otherwise trap inside `HTTPRequest`, and URLs with a scheme but no host (`mailto:`, `file:///`), which would otherwise reach the transport as an `HTTPRequest` whose `url` is `nil`.
- `Client.send` and `Client.raw` throw `ClientError.requestBodyNotAllowed` for `GET` and `HEAD` requests that carry a body, matching the Fetch specification.
- `Client.Codec` wraps a `BodyCodec` plus optional default `Content-Type` and `Accept` header values for typed requests. Initializers that omit those arguments adopt the body codec's `defaultRequestContentType` / `defaultAccept` declarations, while initializers that explicitly pass `nil` or `[]` preserve those exact values so callers can suppress either header.
- `BodyCodec` requires each conformer to declare `defaultRequestContentType` and `defaultAccept`; `nil` and `[]` explicitly mean the codec has no safe media-type defaults. `decodesEmptyResponseBodies` retains a conservative `false` protocol-extension default.
- `Client.Codec` provides convenience factories for JSON, form URL-encoded, plain-text, and raw-data body coding. Those factories always adopt the corresponding `BodyCodec`'s media-type declarations, keeping each built-in codec's declarations as the single source of truth. Exact media-type overrides and custom `BodyCodec` values use `Client.Codec`'s initializers directly.
- `ClientConfiguration` is immutable after initialization and contains only client-wide request and response defaults. Browser-specific behavior belongs to an injected `BrowserTransport`.
- `ClientConfiguration` also carries an optional `defaultTimeout`, which defaults to 90 seconds. A per-call `timeout: nil` selects that configured default; disabling timeouts requires configuring `defaultTimeout` as `nil`.
- `ClientConfiguration` also carries `maximumBufferedBodyBytes`, which defaults to 2 MiB and is used when Parcel must buffer response bytes in memory for decoding or error reporting.
- `ClientConfiguration` carries a default `Client.Codec`; `Client.Codec.json()` is the default implementation.
- Typed requests append the selected codec's `Accept` header values only when the merged client-default and per-request headers do not already provide `Accept`.
- Typed requests append the selected codec's `Content-Type` header only when Parcel encodes the request body and the merged client-default and per-request headers do not already provide `Content-Type`.
- Parcel uses `swift-http-types` for HTTP method, status, request-head, response-head, and header
  field semantics instead of maintaining custom protocol primitives.
- `HTTPFields` preserves repeated header values and resolves lookups case-insensitively according to `swift-http-types`.
- Per-call header fields replace configured default header fields with the same field name; defaults for other names are preserved ahead of the per-call fields. Repeated values supplied within a single layer are preserved.
- Typed `Client.send` throws `ClientError.unsuccessfulStatusCode` for non-2xx responses before decoding; if reading the error body itself fails (for example it exceeds `maximumBufferedBodyBytes`), the status-code error is still thrown with a `nil` body instead of being replaced by the read failure. Cancellation and timeout errors remain observable and are never downgraded to a status-code error.
- Empty successful responses can be decoded as `EmptyResponse`; codecs whose `decodesEmptyResponseBodies` is `true` (plain-text and raw-data) decode zero-length bodies as empty values, and all other types throw `ClientError.emptyResponseBody`.
- `JSONBodyCodec` allows callers to supply and replace custom `JSONEncoder` / `JSONDecoder` factories; each factory runs once per encode or decode operation so mutable Foundation coders are not shared between concurrent requests.
- `FormURLEncodedBodyCodec` supports flat top-level keyed payloads and repeated keys for array values, but does not support nested keyed containers. Nested keyed values, nested arrays (including empty ones), and `nil` array elements throw `EncodingError.invalidValue` at encode time instead of silently corrupting the payload. Empty top-level field arrays round-trip by decoding missing array fields as empty arrays, while other missing required values continue to throw `DecodingError.keyNotFound`.
- Form decoding skips empty field sequences, so a trailing or doubled `&` does not contribute a field named `""`.
- Form encoding follows the HTML form percent-encode set: spaces become `+`, `*` remains unescaped, `~` becomes `%7E`, and all other non-safe UTF-8 bytes use uppercase percent escapes.
- `PlainTextBodyCodec` encodes and decodes UTF-8 `String` values and throws `DecodingError.dataCorrupted` for response bytes that are not valid UTF-8.
- `RawDataBodyCodec` encodes and decodes raw `Data` values.
- Successful typed responses preserve the final response `URL?` on `Client.Response`, but typed decoding consumes the response body and does not preserve raw response bytes afterward.
- Browser response-body promise rejections from streamed byte reads surface as `ClientError.responseBodyFailure`, preserving JavaScript error metadata.
- Browser fetch promise rejections that are not aborts (network failures, CORS blocks, invalid URLs) surface as `ClientError.fetchFailure`, preserving JavaScript error metadata.
- Browser request or response-body cancellation throws `CancellationError`.
- Browser request and response-body timeouts throw `ClientError.timedOut`, including while Parcel buffers a caller-supplied request-body stream before calling `fetch`.
- Request-body buffering uses a hard timeout race, so a custom iterator that ignores task cancellation cannot delay the caller's timeout result. Such an iterator may retain its cancelled collection task until it eventually resumes.

## Transport Model

- Core request/response logic is transport-driven via `Transport`.
- `Transport.send(_:, body:timeout:)` returns `TransportResponse`, which contains a raw `HTTPResponse`, an optional `HTTPBody`, and the final response `URL?`, regardless of the HTTP status code.
- `Client(configuration:)` is only available on `wasm32` builds that include Parcel's browser transport dependencies; host builds must inject an explicit `Transport`.
- `BrowserTransport` is only exposed on `wasm32` builds with Parcel's browser transport dependencies available.
- On `wasm32`, `Client(configuration:)` constructs `BrowserTransport` directly. Runtime capability is checked when a request is sent so constructing a client remains safe in unsupported JavaScript contexts.
- `BrowserTransport` uses the browser `fetch` API.
- `BrowserTransport.isSupportedRuntime` accepts both window and worker-style JavaScript global scopes when `fetch`, `AbortController`, `Object`, `Array`, `Promise`, `setTimeout`, `clearTimeout`, and `Uint8Array` are available. It gates every global the transport later looks up, so `BrowserTransport` reports an unsupported runtime up front rather than partway through a request.
- `BrowserTransport` installs JavaScriptKit's global event-loop executor when initialized in a supported runtime.
- `BrowserTransport` confines JavaScript objects, response readers, and timers to actors backed by their owning JavaScript event-loop executor; cancellation handlers enqueue owner-isolated cleanup instead of touching JavaScript from an arbitrary thread.
- `BrowserTransport` accepts an optional per-request timeout and enforces it with `AbortController` plus `setTimeout`. The abort timer is cleared only when the response body reaches end-of-stream, is cancelled, or fails, so the deadline spans the fetch and the whole consumption of the response body.
- `BrowserTransport` accepts immutable `BrowserRequestOptions` and applies the Fetch `credentials`, script-constructible `mode` (`cors`, `no-cors`, or `same-origin`), `cache`, and `redirect` options it declares. The script-forbidden `navigate` mode is not exposed. Options left `nil` are omitted from the Fetch init dictionary rather than sent as an explicit default.
- `BrowserTransport` passes outgoing headers to `fetch` as an ordered header-entry list so repeated field names preserve their semantics instead of collapsing to the last value.
- `BrowserTransport` converts HTTP field values through their ISO-8859-1 byte representation in both directions so non-UTF-8 field bytes are not replaced at the Swift/JavaScript boundary.
- Because typed decoding collects response bytes from `HTTPBody`, the generic client decode path handles empty-response and malformed-payload behavior consistently for browser requests regardless of the configured codec.
- Raw transport responses remain available as `HTTPBody?`, which may be single-iteration depending on the transport.
- `BrowserTransport` binds JavaScript instance method calls through JavaScriptKit member-call helpers so browser methods receive the correct `this` value.
- `BrowserTransport` threads an `AbortController` signal through `fetch` and response-body reads so Swift task cancellation aborts the browser request and body consumption.
- `BrowserTransport` exposes response bodies lazily as single-iteration `HTTPBody` values backed by `ReadableStream.getReader()`.
- `BrowserTransport` preserves `Response.body == null` as `TransportResponse.body == nil`.
- `BrowserTransport` preserves an explicitly present zero-length request body instead of treating it as an absent body.
- `BrowserTransport` cancels abandoned or failed `ReadableStream` readers when a streamed response body does not reach end-of-stream, observes cancellation-promise failures, and releases the reader lock after cancellation settles.
- `BrowserTransport` currently buffers outgoing request bodies before passing them to `fetch`; streaming uploads are not yet exposed, and the buffer is capped by `maximumBufferedRequestBodyBytes` (2 MiB by default).
- `BrowserTransport` does not retain temporary `JSClosure` bridges beyond synchronous JavaScript header iteration, using explicit release on JavaScriptKit no-weakrefs builds.
- `ClientError.unsupportedPlatform` reports a request made where no browser-capable JavaScript runtime was available when `BrowserTransport` initialized. `ClientError.invalidJavaScriptContext` reports required browser globals disappearing after a supported transport initialized.

## Validation

Parcel follows the same broad validation split as JavaScriptKit:

- Both lanes run in GitHub Actions via [`.github/workflows/ci.yml`](.github/workflows/ci.yml). The
  host job runs unconditionally; the Wasm job runs once the `WASM_SDK_URL` and
  `WASM_SDK_CHECKSUM` repository variables point at a swiftwasm SDK bundle, and is skipped rather
  than reported as passing until then.
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
- Wasm tests run in Node with the repository prelude in [`Tests/prelude.mjs`](Tests/prelude.mjs), which provides a deterministic `fetch` shim and awaitable request-lifecycle states for browser-oriented transport tests.
- Wasm test packaging points JavaScriptKit's PackageToJS template at
  [`Vendor/browser_wasi_shim`](Vendor/browser_wasi_shim) so validation does not depend on
  `registry.npmjs.org` being reachable for `@bjorn3/browser_wasi_shim`.
- Parcel targets Swift 6.3.0 for host builds and SwiftPM uses `swift-tools-version: 6.3`.
- Parcel requires macOS 15 or newer for host builds so the shared body iteration
  guard can use Swift's `Synchronization.Mutex` instead of Foundation locking.
- Parcel depends on `swift-http-types` `1.6.0` or newer and relies on its default-enabled
  `FoundationURL` trait for the URL-based `HTTPRequest` APIs used by Parcel.
- Parcel depends on JavaScriptKit `0.58.0` or newer for Swift 6.3-compatible
  JavaScript event-loop executor support.
- By default, the Wasm lane expects the `swift-6.3-RELEASE_wasm` SDK; override that with `PARCEL_SWIFT_SDK` when needed.
- Both lanes must pass before a change is considered validated. Record per-review test counts in commit messages rather than here, so this document does not carry results that silently go stale.

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
chmod u+w "$template_path"
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
