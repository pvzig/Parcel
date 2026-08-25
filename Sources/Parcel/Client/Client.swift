import HTTPTypes

#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// Sends typed Parcel requests through a `Transport` and decodes successful responses using the
/// selected `Codec`.
public struct Client: Sendable {
  /// The configuration used to prepare requests and decode responses.
  public let configuration: ClientConfiguration
  private let transport: any Transport

  #if arch(wasm32) && canImport(JavaScriptEventLoop) && canImport(JavaScriptKit)
    /// Creates a client that uses Parcel's built-in browser transport.
    public init(configuration: ClientConfiguration = .init()) {
      self.init(
        configuration: configuration,
        transport: BrowserTransport()
      )
    }
  #else
    @available(
      *,
      unavailable,
      message:
        "Client() is only available when Parcel can select its built-in browser transport. Inject a Transport on host builds."
    )
    /// Creates a client that uses Parcel's built-in browser transport.
    public init(configuration: ClientConfiguration = .init()) {
      fatalError("Client() is unavailable on this platform")
    }
  #endif

  /// Creates a client with an explicit transport.
  public init(
    configuration: ClientConfiguration = .init(),
    transport: any Transport
  ) {
    self.configuration = configuration
    self.transport = transport
  }

  /// Sends a typed request and decodes the response body as `Value`.
  public func send<Value: Decodable>(
    _ request: Request,
    as responseType: Value.Type = Value.self,
    codec: Codec? = nil,
    timeout: Duration? = nil
  ) async throws -> Response<Value> {
    let codec = effectiveCodec(codec)
    try validateRequestURL(request.url)
    try request.method.validateBodyAllowed(hasBody: request.hasBody)
    let response = try await transport.send(
      makeRequest(from: request, codec: codec),
      body: try request.encodedBody(using: codec),
      timeout: effectiveTimeout(timeout)
    )
    return try await decode(
      response,
      as: responseType,
      using: codec
    )
  }

  /// Sends a raw request without applying codec-specific body encoding or headers.
  public func raw(
    _ request: HTTPRequest,
    body: HTTPBody? = nil,
    timeout: Duration? = nil
  ) async throws -> TransportResponse {
    try request.method.validateBodyAllowed(hasBody: body != nil)
    return try await transport.send(
      prepare(request),
      body: body,
      timeout: effectiveTimeout(timeout)
    )
  }

  private func decode<Value: Decodable>(
    _ response: TransportResponse,
    as responseType: Value.Type,
    using codec: Codec
  ) async throws -> Response<Value> {
    try await validateSuccessfulStatus(response)
    let body = try await collectBody(response.body)
    let value = try decodeBody(body, as: responseType, using: codec)

    return Response(
      value: value,
      response: response.response,
      url: response.url
    )
  }

  private func validateSuccessfulStatus(_ response: TransportResponse) async throws {
    guard (200..<300).contains(response.response.status.code) else {
      throw ClientError.unsuccessfulStatusCode(
        response.response.status.code,
        body: try await readErrorBody(response.body)
      )
    }
  }

  private func readErrorBody(_ body: HTTPBody?) async throws -> String? {
    do {
      return try await body?.text(
        upTo: configuration.maximumBufferedBodyBytes
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch ClientError.timedOut {
      throw ClientError.timedOut
    } catch {
      // A failing error-body read must not replace the status-code error.
      return nil
    }
  }

  private func collectBody(_ body: HTTPBody?) async throws -> Data {
    guard let body else {
      return Data()
    }
    return try await body.collect(
      upTo: configuration.maximumBufferedBodyBytes
    )
  }

  private func decodeBody<Value: Decodable>(
    _ body: Data,
    as responseType: Value.Type,
    using codec: Codec
  ) throws -> Value {
    if body.isEmpty == false {
      return try codec.decode(responseType, from: body)
    }
    if responseType == EmptyResponse.self,
      let emptyResponse = EmptyResponse() as? Value
    {
      return emptyResponse
    }
    guard codec.bodyCodec.decodesEmptyResponseBodies else {
      throw ClientError.emptyResponseBody
    }
    return try codec.decode(responseType, from: body)
  }

  /// Rejects URLs that `HTTPRequest` cannot represent as an absolute request target.
  ///
  /// A schemeless URL traps inside `HTTPRequest`'s initializer, and a URL with a scheme but no
  /// authority (`mailto:someone@example.com`, `file:///tmp/x`) silently produces an `HTTPRequest`
  /// whose `url` is `nil`, which transports can only report as a late, unrelated failure.
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

  private func effectiveTimeout(_ timeout: Duration?) -> Duration? {
    timeout ?? configuration.defaultTimeout
  }

  private func effectiveCodec(_ codec: Codec?) -> Codec {
    codec ?? configuration.defaultCodec
  }

  private func makeRequest(
    from request: Request,
    codec: Codec
  ) -> HTTPRequest {
    var headers = mergedHeaders(additionalHeaders: request.headers)
    applyCodecHeaders(
      to: &headers,
      hasRequestBody: request.hasBody,
      codec: codec
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

  private func applyCodecHeaders(
    to headers: inout HTTPFields,
    hasRequestBody: Bool,
    codec: Codec
  ) {
    if hasRequestBody,
      headers[.contentType] == nil,
      let requestContentType = codec.requestContentType
    {
      headers.append(.init(name: .contentType, value: requestContentType))
    }

    if headers[.accept] == nil {
      for value in codec.accept {
        headers.append(.init(name: .accept, value: value))
      }
    }
  }
}
