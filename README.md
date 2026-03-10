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

let accepted: AcceptedResponse = try await client.post(
    GenerateRequest(pagePath: "/posts/example"),
    to: URL(string: "https://example.com/api/generate")!
)
```

If you need response metadata like headers or the final URL:

```swift
let accepted = try await client.postResponse(
    GenerateRequest(pagePath: "/posts/example"),
    to: generateURL,
    expecting: AcceptedResponse.self
)

let statusCode = accepted.response.status.code
let etag = accepted.response.headerFields[.eTag]
let finalURL = accepted.url
let value = accepted.value
```

Typed decode consumes the response body once. `DecodedResponse` preserves the decoded value, the response head, and the final URL, but it does not retain raw response bytes after decoding.

If you work directly with raw requests through `Client.send(_:, body:timeout:)`, or with a custom `Transport`, you may receive `TransportResponse` values with 4xx or 5xx status codes. Parcel's typed `Client` APIs treat non-2xx responses as failures and throw `ClientError.unsuccessfulStatusCode` before decoding.

```swift
let request = HTTPRequest(method: .get, url: generateURL)
let response = try await client.send(request)

let statusCode = response.response.status.code
let bodyText = try await response.body?.text()
```

`HTTPBody.text()` buffers in memory and defaults to a 2 MiB cap. Raise that limit explicitly when you expect larger bodies.

On the browser transport path, `ReadableStreamDefaultReader.read()` failures surface as `ClientError.responseBodyFailure`, while Swift task cancellation throws `CancellationError`.

For successful responses with no body, use `EmptyResponse`:

```swift
let deleteURL = URL(string: "https://example.com/api/delete")!
let _: EmptyResponse = try await client.delete(from: deleteURL)
```

Typed requests use the configured body-coding defaults for `Accept` and, when Parcel encodes the request body, `Content-Type`. The default configuration uses JSON and sets both to `application/json`. Parcel also applies a default request timeout of 90 seconds unless you override it per call or set `defaultTimeout` to `nil`. Buffered response decoding and error-body reads use a 2 MiB default cap, configurable via `ClientConfiguration(maximumBufferedBodyBytes:)`.

If you need custom `JSONEncoder` / `JSONDecoder` behavior, configure the default `JSONBodyCodec` through `ClientConfiguration`:

```swift
let client = Client(
    configuration: ClientConfiguration(
        defaultTimeout: .seconds(30),
        bodyCoding: .json(
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

Parcel also includes built-in helpers for a few common non-JSON wire formats:

```swift
let formClient = Client(
    configuration: ClientConfiguration(bodyCoding: .formURLEncoded())
)

let textClient = Client(
    configuration: ClientConfiguration(bodyCoding: .plainText())
)

let binaryClient = Client(
    configuration: ClientConfiguration(bodyCoding: .rawData())
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
        bodyCoding: .init(
            codec: CustomCodec(),
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
