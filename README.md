# Parcel

Parcel is a small browser HTTP client for SwiftWASM with pluggable typed body codecs. It defaults to JSON for `Encodable` request bodies and `Decodable` responses.

## Usage

```swift
struct Request: Encodable {}
struct Response: Decodable {}

let client = Client()

let accepted = try await client.send(
    .post(
        URL(string: "https://example.com/api/generate")!,
        body: Request()
    ),
    as: Response.self
)
```

Typed decode consumes the response body once. `Client.Response` preserves the decoded value, the response head, and the final URL, but it does not retain raw response bytes after decoding. `HTTPBody.text()` buffers in memory and defaults to a 2 MiB cap. Raise that limit explicitly when you expect larger bodies.

### Raw Requests

If you need to drop to a raw request, use `Client.raw(_:, body:timeout:)`. Raw calls do not apply codec-specific `Accept` or `Content-Type` defaults. Raw responses may carry 4xx or 5xx status codes; typed `Client.send` calls treat non-2xx responses as failures and throw `ClientError.unsuccessfulStatusCode` before decoding.
```swift
let request = HTTPRequest(method: .get, url: URL(string: "https://example.com/api/generate")!)
let response = try await client.raw(request)

let statusCode = response.response.status.code
let bodyText = try await response.body?.text()
```

### EmptyResponse

For successful responses with no body, use `EmptyResponse`:
```swift
let deleteURL = URL(string: "https://example.com/api/delete")!
let response = try await client.send(
    .delete(deleteURL),
    as: EmptyResponse.self
)
```

### Custom Encoders
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

### Codecs

Parcel includes additional built-in codecs for common wire formats: ` .formURLEncoded()`, `.plainText()`, `.rawData()`.

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

`BrowserTransport` is likewise only available on those `wasm32` builds. It installs the JavaScriptKit executor when it initializes in a supported runtime.

Browser transport responses stream lazily from `ReadableStream` through `HTTPBody`. Outgoing request bodies are still buffered before Parcel passes them to `fetch`, with a 2 MiB default cap configurable via `BrowserTransport(maximumBufferedRequestBodyBytes:)`.
