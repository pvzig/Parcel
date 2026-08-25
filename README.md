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

The encoder and decoder factories run for each encode or decode operation. This keeps mutable Foundation coders isolated between concurrent requests.

### Codecs

Parcel includes additional built-in codecs for common wire formats: `.formURLEncoded()`, `.plainText()`, `.rawData()`.

If you need a different typed wire format entirely, provide a custom `BodyCodec`. Declare the codec's media types on the codec itself so every way of constructing a `Client.Codec` from it sends the right `Content-Type` and `Accept` headers:

```swift
enum CustomCodecError: Error {
    case unsupported
}

struct CustomCodec: BodyCodec {
    var defaultRequestContentType: String? { "application/custom" }
    var defaultAccept: [String] { ["application/custom"] }

    func encode<Request: Encodable>(_ value: Request) throws -> Data {
        throw CustomCodecError.unsupported
    }

    func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        throw CustomCodecError.unsupported
    }
}

let client = Client(
    configuration: ClientConfiguration(
        defaultCodec: Client.Codec(bodyCodec: CustomCodec())
    )
)
```

## Runtime

Parcel is browser-oriented. `Client()` is only compiled on `wasm32` builds that include Parcel's browser transport dependencies. Host builds must inject a custom `Transport`, which is how Parcel's native unit tests exercise the higher-level client behavior. On `wasm32`, `Client()` constructs a `BrowserTransport`; requests made in an unsupported JavaScript runtime fail with `ClientError.unsupportedPlatform`.

`BrowserTransport` is likewise only available on those `wasm32` builds. It installs the JavaScriptKit executor when it initializes in a supported runtime.

Browser transport responses stream lazily from `ReadableStream` through `HTTPBody`. Outgoing request bodies are still buffered before Parcel passes them to `fetch`, with a 2 MiB default cap configurable through `BrowserTransport(maximumBufferedRequestBodyBytes:)`. Inject that transport into `Client` when you need a different cap.

A timeout covers the fetch *and* the consumption of the response body, because the transport clears its abort timer only once the body reaches end-of-stream. With the 90 second default, a `Client.raw` caller streaming a long-lived response (server-sent events, a slow download) sees the request aborted with `ClientError.timedOut` mid-stream. Use a client configured with `ClientConfiguration(defaultTimeout: nil)` for those calls; a per-call `timeout: nil` selects the configured default rather than disabling it.

### Fetch Options

`fetch` defaults to `credentials: "same-origin"`, so cross-origin requests do not carry cookies unless you ask for them. Configure the Fetch `credentials`, `mode`, `cache`, and `redirect` options on an injected `BrowserTransport`:

```swift
let client = Client(
    transport: BrowserTransport(
        requestOptions: BrowserRequestOptions(
            credentials: .include,
            mode: .cors
        )
    )
)
```

Options left `nil` are omitted from the Fetch init dictionary entirely, so the browser applies its own default. Plain `Client()` uses `BrowserTransport`'s default options.

## Errors

Typed requests turn non-2xx responses into `ClientError.unsuccessfulStatusCode`; raw requests return those response statuses unchanged. Both paths can throw `ClientError` for transport and validation failures: network-level Fetch failures (offline, DNS, CORS) use `.fetchFailure` with the underlying JavaScript metadata, unsupported runtimes use `.unsupportedPlatform`, browser globals that disappear after transport initialization use `.invalidJavaScriptContext`, timeouts use `.timedOut`, typed-request URLs that are not absolute — no scheme, or a scheme with no host such as `mailto:` — use `.invalidRequestURL`, and `GET`/`HEAD` requests with bodies use `.requestBodyNotAllowed`. Swift task cancellation remains `CancellationError`.

When upgrading code that exhaustively switches over `ClientError`, account for the newer Fetch, timeout, URL-validation, response-body, and request-body cases.
