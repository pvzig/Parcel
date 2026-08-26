import HTTPAPIs
import HTTPTypes

#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

#if arch(wasm32) && canImport(FetchHTTPClient) && canImport(JavaScriptEventLoop)
  import FetchHTTPClient
  import JavaScriptEventLoop

  typealias DefaultExecutorFactory = JavaScriptEventLoop
#endif

/// Sends typed Parcel requests through the browser Fetch API.
public struct Client: Sendable {
  private struct BufferedHTTPResponse: Sendable {
    let response: HTTPResponse
    let body: Data?
  }

  private typealias PerformRequest =
    @Sendable (HTTPRequest, Data?, Int) async throws -> BufferedHTTPResponse

  /// The configuration used to prepare requests and decode responses.
  public let configuration: ClientConfiguration
  private let performRequest: PerformRequest

  #if arch(wasm32) && canImport(FetchHTTPClient) && canImport(JavaScriptEventLoop)
    /// Creates a client backed by the browser Fetch API through `FetchHTTPClient`.
    public init(configuration: ClientConfiguration = .init()) {
      JavaScriptEventLoop.installGlobalExecutor()
      self.init(
        configuration: configuration,
        httpClient: FetchHTTPClient()
      )
    }
  #else
    @available(
      *,
      unavailable,
      message: "Client requires a browser-capable Wasm build with HTTP_API_ENABLE_WASM=1."
    )
    /// Creates a client backed by the browser Fetch API through `FetchHTTPClient`.
    public init(configuration: ClientConfiguration = .init()) {
      fatalError("Client() is unavailable on this platform")
    }
  #endif

  /// Internal transport seam used by the Fetch-backed initializer and deterministic host tests.
  ///
  /// The underlying client is captured directly and may service concurrent Parcel calls. Its
  /// `HTTPClient` conformance is therefore responsible for synchronizing any mutable shared state.
  @available(anyAppleOS 26.0, *)
  init(
    configuration: ClientConfiguration = .init(),
    httpClient: some HTTPAPIs.HTTPClient & AnyObject
  ) {
    self.configuration = configuration
    self.performRequest = { request, body, maximumBufferedBodyBytes in
      var httpClient = httpClient
      let options = httpClient.defaultRequestOptions
      return try await httpClient.perform(
        request: request,
        body: body.map { .data($0) },
        options: options
      ) { response, reader in
        BufferedHTTPResponse(
          response: response,
          body: try await Self.collectBody(
            reader,
            upTo: maximumBufferedBodyBytes
          )
        )
      }
    }
  }

  /// Sends an operation and returns its decoded output.
  public func send<Output: Decodable>(
    _ request: Request<Output>
  ) async throws -> Output {
    try await response(request).value
  }

  /// Sends an operation and returns its decoded output with the HTTP response metadata.
  public func response<Output: Decodable>(
    _ request: Request<Output>
  ) async throws -> Response<Output> {
    let bodyCoding = effectiveBodyCoding(request.bodyCoding)
    try validateRequestURL(request.url)
    try request.method.validateBodyAllowed(hasBody: request.hasBody)

    let response = try await performRequest(
      makeRequest(from: request, bodyCoding: bodyCoding),
      try request.encodedBody(using: bodyCoding),
      configuration.maximumBufferedBodyBytes
    )
    return try decode(
      response,
      as: Output.self,
      using: bodyCoding
    )
  }

  /// Sends a raw request and buffers its response body inside the HTTP client's response handler.
  public func raw(
    _ request: HTTPRequest,
    body: Data? = nil
  ) async throws -> RawResponse {
    try request.method.validateBodyAllowed(hasBody: body != nil)
    let response = try await performRequest(
      prepare(request),
      body,
      configuration.maximumBufferedBodyBytes
    )
    guard let body = response.body else {
      throw ClientError.responseBodyTooLarge(
        maximumBytes: configuration.maximumBufferedBodyBytes
      )
    }

    return RawResponse(response: response.response, body: body)
  }

  private func decode<Value: Decodable>(
    _ response: BufferedHTTPResponse,
    as responseType: Value.Type,
    using bodyCoding: BodyCoding
  ) throws -> Response<Value> {
    try validateSuccessfulStatus(response)
    guard let body = response.body else {
      throw ClientError.responseBodyTooLarge(
        maximumBytes: configuration.maximumBufferedBodyBytes
      )
    }
    let value = try decodeBody(body, as: responseType, using: bodyCoding)

    return Response(
      value: value,
      response: response.response
    )
  }

  private func validateSuccessfulStatus(_ response: BufferedHTTPResponse) throws {
    guard (200..<300).contains(response.response.status.code) else {
      throw ClientError.unsuccessfulStatusCode(
        response.response.status.code,
        body: response.body.map { String(decoding: $0, as: UTF8.self) }
      )
    }
  }

  private func decodeBody<Value: Decodable>(
    _ body: Data,
    as responseType: Value.Type,
    using bodyCoding: BodyCoding
  ) throws -> Value {
    if body.isEmpty == false {
      return try bodyCoding.decode(responseType, from: body)
    }
    if responseType == EmptyResponse.self,
      let emptyResponse = EmptyResponse() as? Value
    {
      return emptyResponse
    }
    guard bodyCoding.responseDecoder.decodesEmptyResponseBodies else {
      throw ClientError.emptyResponseBody
    }
    return try bodyCoding.decode(responseType, from: body)
  }

  /// Rejects URLs that `HTTPRequest` cannot represent as an absolute request target.
  ///
  /// A schemeless URL traps inside `HTTPRequest`'s initializer, and a URL with a scheme but no
  /// authority (`mailto:someone@example.com`, `file:///tmp/x`) silently produces an `HTTPRequest`
  /// whose `url` is `nil`, which HTTP clients can only report as a late, unrelated failure.
  private func validateRequestURL(_ url: URL) throws {
    guard url.scheme != nil, url.host() != nil else {
      throw ClientError.invalidRequestURL(url.absoluteString)
    }
  }

  private func mergedHeaders(additionalHeaders: HTTPFields) -> HTTPFields {
    guard additionalHeaders.isEmpty == false else {
      return configuration.defaultHeaders
    }

    let overriddenNames = Set(additionalHeaders.map(\.name))
    var headers = HTTPFields()
    for field in configuration.defaultHeaders
    where overriddenNames.contains(field.name) == false {
      headers.append(field)
    }
    headers.append(contentsOf: additionalHeaders)
    return headers
  }

  private func effectiveBodyCoding(_ bodyCoding: BodyCoding?) -> BodyCoding {
    bodyCoding ?? configuration.defaultBodyCoding
  }

  private func makeRequest<Output: Decodable>(
    from request: Request<Output>,
    bodyCoding: BodyCoding
  ) -> HTTPRequest {
    var headers = mergedHeaders(additionalHeaders: request.headers)
    applyBodyCodingHeaders(
      to: &headers,
      hasRequestBody: request.hasBody,
      bodyCoding: bodyCoding
    )

    return HTTPRequest(
      method: request.method,
      url: request.url,
      headerFields: headers
    )
  }

  private func prepare(_ request: HTTPRequest) -> HTTPRequest {
    var request = request
    request.headerFields = mergedHeaders(additionalHeaders: request.headerFields)
    return request
  }

  private func applyBodyCodingHeaders(
    to headers: inout HTTPFields,
    hasRequestBody: Bool,
    bodyCoding: BodyCoding
  ) {
    if hasRequestBody,
      headers[.contentType] == nil,
      let requestContentType = bodyCoding.requestContentType
    {
      headers.append(.init(name: .contentType, value: requestContentType))
    }

    if headers[.accept] == nil {
      for value in bodyCoding.accept {
        headers.append(.init(name: .accept, value: value))
      }
    }
  }

  /// Consumes the scoped response reader completely. `nil` records that the body exceeded the
  /// configured cap while still draining the reader to its terminal state.
  private static func collectBody<Reader: AsyncReader & ~Copyable>(
    _ reader: consuming Reader,
    upTo maximumBytes: Int
  ) async throws -> Data?
  where Reader.ReadElement == UInt8, Reader.FinalElement == HTTPFields? {
    var body = Data()
    var exceededLimit = false

    do {
      _ = try await reader.forEachBuffer { buffer async throws(Never) in
        var consumer = buffer.consumeAll()
        while let byte = consumer.next() {
          guard exceededLimit == false else {
            continue
          }

          let (newCount, overflow) = body.count.addingReportingOverflow(1)
          guard overflow == false, newCount <= maximumBytes else {
            body.removeAll(keepingCapacity: false)
            exceededLimit = true
            continue
          }
          body.append(byte)
        }
      }
    } catch let error {
      try error.unwrap()
    }

    return exceededLimit ? nil : body
  }
}
