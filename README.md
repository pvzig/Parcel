# Parcel

Parcel is a small browser HTTP client for SwiftWASM with pluggable typed body codecs. It defaults to JSON for `Encodable` request bodies and `Decodable` responses.

## Usage

```swift
import Foundation
import HTTPTypes
import Parcel

struct GenerateRequest: Encodable {
    let pagePath: String
}

struct AcceptedResponse: Decodable {
    let statusURL: URL

    private enum CodingKeys: String, CodingKey {
        case statusURL = "statusUrl"
    }
}
```

```swift
let client = Client()

let accepted = try await client.send(
    .post(
        URL(string: "https://example.com/api/generate")!,
        body: GenerateRequest(pagePath: "/posts/example")
    ),
    as: AcceptedResponse.self
)

// response metadata
let statusCode = accepted.response.status.code
let etag = accepted.response.headerFields[.eTag]
let finalURL = accepted.url
let value = accepted.value
```

Typed decode consumes the response body once. `Client.Response` preserves the decoded value, the response head, and the final URL, but it does not retain raw response bytes after decoding.

If you need to drop to a raw request, use `Client.raw(_:, body:timeout:)`. Raw calls do not apply codec-specific `Accept` or `Content-Type` defaults. Raw responses may carry 4xx or 5xx status codes; typed `Client.send` calls treat non-2xx responses as failures and throw `ClientError.unsuccessfulStatusCode` before decoding.

```swift
let request = HTTPRequest(method: .get, url: generateURL)
let response = try await client.raw(request)

let statusCode = response.response.status.code
let bodyText = try await response.body?.text()
```

`HTTPBody.text()` buffers in memory and defaults to a 2 MiB cap. Raise that limit explicitly when you expect larger bodies.

On the browser transport path, `ReadableStreamDefaultReader.read()` failures surface as `ClientError.responseBodyFailure`, while Swift task cancellation throws `CancellationError`.

For successful responses with no body, use `EmptyResponse`:

```swift
let deleteURL = URL(string: "https://example.com/api/delete")!
let response = try await client.send(
    .delete(deleteURL),
    as: EmptyResponse.self
)
```

Typed requests use the selected codec's defaults for `Accept` and, when Parcel encodes the request body, `Content-Type`. The default codec uses JSON and sets both to `application/json`. Parcel also applies a default request timeout of 90 seconds unless you override it per call or set `defaultTimeout` to `nil`. Buffered response decoding and error-body reads use a 2 MiB default cap, configurable via `ClientConfiguration(maximumBufferedBodyBytes:)`.

If you need custom `JSONEncoder` / `JSONDecoder` behavior, configure the default codec through `ClientConfiguration`:

```swift
let client = Client(
    configuration: ClientConfiguration(
        defaultTimeout: .seconds(30),
        defaultCodec: .json(
            codec: JSONBodyCodec(
                makeDecoder: {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    return decoder
                }
            )
        )
    )
)
```

Parcel also includes built-in per-call helpers for a few common non-JSON wire formats:

```swift
let formResponse = try await client.send(
    .post(generateURL, body: payload),
    as: TokenExchangePayload.self,
    codec: .formURLEncoded()
)

let textResponse = try await client.send(
    .post(generateURL, body: "publish"),
    as: String.self,
    codec: .plainText()
)

let binaryResponse = try await client.send(
    .post(generateURL, body: Data([0x00, 0x01])),
    as: Data.self,
    codec: .rawData()
)
```

`FormURLEncodedBodyCodec` supports flat keyed payloads and repeated keys for array values. Nested keyed containers are not supported.

If you need a different typed wire format entirely, provide a custom `BodyCodec`:

```swift
enum CustomCodecError: Error {
    case unsupported
}

struct CustomCodec: BodyCodec {
    func encode<Request: Encodable>(_ value: Request) throws -> Data {
        throw CustomCodecError.unsupported
    }

    func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        throw CustomCodecError.unsupported
    }
}

let client = Client(
    configuration: ClientConfiguration(
        defaultCodec: .custom(
            CustomCodec(),
            requestContentType: "application/custom",
            accept: ["application/custom"]
        )
    )
)
```

## Runtime

Parcel is browser-oriented. `Client()` is only compiled on `wasm32` builds that include Parcel's browser transport dependencies. Host builds must inject a custom `Transport`, which is how Parcel's native unit tests exercise the higher-level client behavior. On `wasm32`, the built-in transport supports both window-style and worker-style globals; unsupported JavaScript runtimes fail requests with `ClientError.unsupportedPlatform`.

`BrowserTransport` is likewise only available on those `wasm32` builds. It installs the JavaScriptKit executor when it initializes in a supported runtime. If your app uses JavaScriptKit async APIs outside Parcel, install the executor during app startup:

```swift
import JavaScriptEventLoop

JavaScriptEventLoop.installGlobalExecutor()
```

Browser transport responses stream lazily from `ReadableStream` through `HTTPBody`. Outgoing request bodies are still buffered before Parcel passes them to `fetch`, with a 2 MiB default cap configurable via `BrowserTransport(maximumBufferedRequestBodyBytes:)`.

## Validation

Parcel follows the same broad validation split as JavaScriptKit:

- A host build lane verifies the package compiles natively without Wasm-only browser tests.
- Wasm/JS tests are the primary runtime validation lane.
- Host tests validate pure Swift request/response logic separately.
- The Wasm-only browser suite is only included when the Wasm test script opts into it.

Run the host build lane with:

```sh
./skills/swift-build/scripts/run-swift-build.sh
```

Run the formatter with:

```sh
./skills/swift-format/scripts/run-swift-format.sh
```

Run the full test flow with:

```sh
./skills/swift-test/scripts/run-swift-tests.sh
```

Run only the Wasm test lane with:

```sh
./skills/swift-test/scripts/run-wasm-tests.sh
```

Run only the host test lane with:

```sh
./skills/swift-test/scripts/run-host-tests.sh
```

The Wasm lane uses `swift package --swift-sdk ... js test` with the Node prelude in [`Tests/prelude.mjs`](Tests/prelude.mjs). By default it expects the `swift-6.2.4-RELEASE_wasm` SDK; override that with `PARCEL_SWIFT_SDK` when needed.
