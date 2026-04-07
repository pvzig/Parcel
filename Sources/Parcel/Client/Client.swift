import Foundation
import HTTPTypes

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
        transport: DefaultTransport.make()
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
    let response = try await transport.send(
      makeRequest(
        from: request,
        includeRequestContentType: request.hasBody,
        includeAccept: true,
        codec: codec
      ),
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
    try await transport.send(
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
    guard (200..<300).contains(response.response.status.code) else {
      throw ClientError.unsuccessfulStatusCode(
        response.response.status.code,
        body: try await response.body?.text(
          upTo: configuration.maximumBufferedBodyBytes
        )
      )
    }

    if let body = response.body {
      let bufferedBody = try await body.collect(
        upTo: configuration.maximumBufferedBodyBytes
      )
      if bufferedBody.isEmpty == false {
        let value = try codec.decode(responseType, from: bufferedBody)
        return Response(
          value: value,
          response: response.response,
          url: response.url
        )
      }
    }

    if responseType == EmptyResponse.self,
      let emptyResponse = EmptyResponse() as? Value
    {
      return Response(
        value: emptyResponse,
        response: response.response,
        url: response.url
      )
    }

    throw ClientError.emptyResponseBody
  }

  private func mergedHeaders(additionalHeaders: HTTPFields) -> HTTPFields {
    var headers = configuration.defaultHeaders
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
    includeRequestContentType: Bool,
    includeAccept: Bool,
    codec: Codec
  ) -> HTTPRequest {
    var headers = mergedHeaders(additionalHeaders: request.headers)
    applyCodecHeaders(
      to: &headers,
      includeRequestContentType: includeRequestContentType,
      includeAccept: includeAccept,
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
    includeRequestContentType: Bool,
    includeAccept: Bool,
    codec: Codec
  ) {
    if includeRequestContentType,
      headers[.contentType] == nil,
      let requestContentType = codec.requestContentType
    {
      headers.append(.init(name: .contentType, value: requestContentType))
    }

    if includeAccept,
      headers[.accept] == nil
    {
      for value in codec.accept {
        headers.append(.init(name: .accept, value: value))
      }
    }
  }
}
