# Parcel

Parcel is a small browser HTTP client for SwiftWASM with pluggable typed body codecs. It
defaults to JSON for `Encodable` request bodies and `Decodable` responses.

Parcel uses Apple's [`swift-http-types`](https://github.com/apple/swift-http-types) directly for
`HTTPRequest`, `HTTPResponse`, and `HTTPFields`. Parcel-specific state like buffered response
bodies, timeouts, and final response URLs travels alongside those message heads instead of inside
custom wrappers.

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
let generateURL = URL(string: "https://example.com/api/generate")!

let accepted: AcceptedResponse = try await client.post(
    GenerateRequest(pagePath: "/posts/example"),
    to: generateURL
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
let rawBody = accepted.body
let value = accepted.value
```

If you work directly with a `Transport`, `send(_:, body:timeout:)` is a raw operation and may
return `HTTPResponse` values with 4xx or 5xx status codes. Parcel's typed `Client` APIs treat
non-2xx responses as failures and throw `ClientError.unsuccessfulStatusCode` before decoding.

On the browser transport path, `response.json()`, `response.text()`, and `response.arrayBuffer()` promise rejections surface as `ClientError.responseBodyFailure`, while Swift task cancellation throws `CancellationError`.

For successful responses with no body, use `EmptyResponse`:

```swift
let deleteURL = URL(string: "https://example.com/api/delete")!
let _: EmptyResponse = try await client.delete(from: deleteURL)
```

Typed requests use the configured body-coding defaults for `Accept` and, when Parcel encodes the
request body, `Content-Type`. The default configuration uses JSON and sets both to
`application/json`. Parcel also applies a default request timeout of 90 seconds unless you override
it per call or set `defaultTimeout` to `nil`.

If you need custom `JSONEncoder` / `JSONDecoder` behavior, configure the default `JSONBodyCodec`
through `ClientConfiguration`:

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

`FormURLEncodedBodyCodec` supports flat keyed payloads and repeated keys for array values. Nested
keyed containers are not supported.

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

Parcel is browser-oriented. `Client()` is only available on `wasm32` builds running in a
browser-capable JavaScript runtime, including worker-style globals that expose `self`. Host builds
must inject a custom `Transport`, which is how Parcel's native unit tests exercise the higher-level
client behavior.

`BrowserTransport` is likewise only available on those `wasm32` browser builds. It installs the
JavaScriptKit executor when it initializes in a supported runtime. If your app uses JavaScriptKit
async APIs outside Parcel, install the executor during app startup:

```swift
import JavaScriptEventLoop

JavaScriptEventLoop.installGlobalExecutor()
```

Raw browser transport responses are still buffered in full via `arrayBuffer()`. Parcel does not yet expose streaming `ReadableStream` response bodies.

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
