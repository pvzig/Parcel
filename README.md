# Parcel

Parcel is a typed HTTP client for Swift Wasm. It layers request encoders and response decoders over
the Swift HTTP API proposal and uses its `FetchHTTPClient` implementation in browser-capable Wasm
runtimes.

Parcel currently requires Swift 6.4 and a matching Swift Wasm SDK. Because the HTTP API proposal is
still experimental, Parcel pins a tested upstream revision. Set `HTTP_API_ENABLE_WASM=1` whenever a
Wasm build resolves or builds the package so SwiftPM exposes `FetchHTTPClient`.

## Usage

```swift
struct GenerateRequest: Encodable, Sendable {
    let pagePath: String
}

struct GenerateResponse: Decodable {
    let id: String
}

let generateURL = URL(string: "https://example.com/api/generate")!
let client = Client()

extension Client.Request where Output == GenerateResponse {
    static func generate(_ body: GenerateRequest) -> Self {
        .post(generateURL, body: body)
    }
}

let accepted = try await client.send(
    .generate(GenerateRequest(pagePath: "/posts/example"))
)
```

`Client.send` validates that the URL is absolute, prepares the request headers and body, and returns
the decoded output. For an ad-hoc request, the assignment provides the output type:

```swift
let generated: GenerateResponse = try await client.send(.get(generateURL))
```

Use `Client.response(_:)` when you also need the `HTTPResponse` head. The typed operation continues
to provide the output type:

```swift
let response = try await client.response(
    .generate(GenerateRequest(pagePath: "/posts/example"))
)
```

Parcel consumes the response body inside the underlying HTTP client's scoped response handler, so
scoped response readers and their buffers never escape.

### Raw requests

Use `Client.raw(_:, body:)` when you need direct `HTTPRequest` access. Raw request and response
bodies are `Data`; raw calls do not add body-coding-specific `Accept` or `Content-Type` headers.
Raw responses return non-2xx statuses unchanged.

```swift
let request = HTTPRequest(method: .get, url: generateURL)
let response = try await client.raw(request)

let statusCode = response.response.status.code
let bodyText = String(decoding: response.body, as: UTF8.self)
```

Both typed and raw responses are buffered up to
`ClientConfiguration.maximumBufferedBodyBytes`, which defaults to 2 MiB.

### Empty responses

Use `EmptyResponse` for successful responses that intentionally carry no body:

```swift
let empty = try await client.send(
    Client.Request<EmptyResponse>.delete(deleteURL)
)
```

### Body coding

JSON is the default. Parcel also includes `.formURLEncoded()`, `.plainText()`, and `.rawData()`.
An operation-specific value takes precedence over `ClientConfiguration.defaultBodyCoding`.

```swift
let request = Client.Request<TokenResponse>.post(
    tokenURL,
    body: credentials,
    bodyCoding: .formURLEncoded()
)
let token = try await client.send(request)
```

Form URL encoding is request-only by default: it sends
`application/x-www-form-urlencoded` and decodes the endpoint's response as JSON. Plain-text and
raw-data body coding accept and decode empty response bodies.

For custom JSON behavior, configure factories that create a fresh Foundation coder per operation:

```swift
let client = Client(
    configuration: ClientConfiguration(
        defaultBodyCoding: .json(
            decoder: JSONBodyDecoder(
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

Custom wire formats can implement `RequestBodyEncoder`, `ResponseBodyDecoder`, or both. Each
component declares the media-type defaults it owns, and `BodyCoding` combines them.

## HTTP client model

`Client(configuration:)` is available on browser-capable Wasm builds with
`HTTP_API_ENABLE_WASM=1`. It installs JavaScriptKit's event-loop executor and owns the upstream
`FetchHTTPClient`; Parcel does not expose a transport-injection API. Parcel consumes response bytes
inside the upstream client's scoped handler and ends that scope immediately when the configured
buffer limit is exceeded.

The pinned `FetchHTTPClient` currently buffers outgoing request bodies and does not yet expose
per-request Fetch options, timeouts, AbortController cancellation propagation, or the final redirect
URL. Parcel intentionally does not recreate those browser features in a second transport layer.

## Errors

Typed requests turn non-2xx responses into `ClientError.unsuccessfulStatusCode`; raw requests return
those statuses. Parcel also reports invalid absolute URLs, disallowed `GET` or `HEAD` bodies, empty
typed responses, and responses larger than the configured buffer. Encoding, decoding, cancellation,
network, and reader failures surface from the body coder or upstream Fetch client without being
re-wrapped as Parcel transport errors.
