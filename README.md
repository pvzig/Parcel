# Parcel

Parcel is a small browser HTTP client for SwiftWASM that encodes request bodies from `Encodable` models and decodes responses into `Decodable` models.

## Usage

```swift
import Foundation

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

let statusCode = accepted.response.statusCode
let etag = accepted.response.headers["etag"]
let finalURL = accepted.response.url
let value = accepted.value
```

If you work directly with a `Transport`, `send(_:)` is a raw operation and may return `HTTPResponse` values with 4xx or 5xx status codes. Parcel's typed `Client` APIs treat non-2xx responses as failures and throw `ClientError.unsuccessfulStatusCode` before decoding.

On the browser transport path, `response.json()`, `response.text()`, and `response.arrayBuffer()` promise rejections surface as `ClientError.responseBodyFailure`, while Swift task cancellation throws `CancellationError`.

For successful responses with no body, use `EmptyResponse`:

```swift
let deleteURL = URL(string: "https://example.com/api/delete")!
let _: EmptyResponse = try await client.delete(from: deleteURL)
```

If you need custom `JSONEncoder` / `JSONDecoder` behavior, configure it through `ClientConfiguration`:

```swift
let client = Client(
    configuration: ClientConfiguration(
        jsonCoding: JSONCodingConfiguration(
            makeDecoder: {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return decoder
            }
        )
    )
)
```

## Runtime

Parcel is browser-oriented. `Client()` only picks the built-in browser transport on `wasm32` builds running in a browser-capable JavaScript runtime, including worker-style globals that expose `self`.

`BrowserTransport` installs the JavaScriptKit executor when it initializes in a supported runtime. If your app uses JavaScriptKit async APIs outside Parcel, install the executor during app startup:

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
