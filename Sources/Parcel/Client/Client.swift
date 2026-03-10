import Foundation
import HTTPTypes

public struct Client: Sendable {
  public let configuration: ClientConfiguration
  private let transport: any Transport

  #if arch(wasm32) && canImport(JavaScriptEventLoop) && canImport(JavaScriptKit)
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
    public init(configuration: ClientConfiguration = .init()) {
      fatalError("Client() is unavailable on this platform")
    }
  #endif

  public init(
    configuration: ClientConfiguration = .init(),
    transport: any Transport
  ) {
    self.configuration = configuration
    self.transport = transport
  }

  public func get<Response: Decodable>(
    from url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .get,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    ).value
  }

  public func head<Response: Decodable>(
    from url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .head,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    ).value
  }

  public func delete<Response: Decodable>(
    from url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .delete,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    ).value
  }

  public func post<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .post,
      body: body,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    ).value
  }

  public func put<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .put,
      body: body,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    ).value
  }

  public func patch<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .patch,
      body: body,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    ).value
  }

  public func getResponse<Response: Decodable>(
    from url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .get,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    )
  }

  public func headResponse<Response: Decodable>(
    from url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .head,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    )
  }

  public func deleteResponse<Response: Decodable>(
    from url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .delete,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    )
  }

  public func postResponse<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .post,
      body: body,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    )
  }

  public func putResponse<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .put,
      body: body,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    )
  }

  public func patchResponse<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .patch,
      body: body,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    )
  }

  public func send(
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

  public func sendResponse<Response: Decodable>(
    _ request: HTTPRequest,
    body: HTTPBody? = nil,
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await execute(
      prepare(request, includeRequestContentType: false, includeAccept: true),
      body: body,
      timeout: timeout,
      expecting: responseType
    )
  }

  public func send<Response: Decodable>(
    _ method: HTTPRequest.Method,
    to url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      method,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    ).value
  }

  public func sendResponse<Response: Decodable>(
    _ method: HTTPRequest.Method,
    to url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await execute(
      makeRequest(
        method: method,
        url: url,
        headers: headers,
        includeRequestContentType: false,
        includeAccept: true
      ),
      body: nil,
      timeout: timeout,
      expecting: responseType
    )
  }

  public func send<Request: Encodable, Response: Decodable>(
    _ method: HTTPRequest.Method,
    body: Request,
    to url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      method,
      body: body,
      to: url,
      headers: headers,
      timeout: timeout,
      expecting: responseType
    ).value
  }

  public func sendResponse<Request: Encodable, Response: Decodable>(
    _ method: HTTPRequest.Method,
    body: Request,
    to url: URL,
    headers: HTTPFields = [:],
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    return try await execute(
      makeRequest(
        method: method,
        url: url,
        headers: headers,
        includeRequestContentType: true,
        includeAccept: true
      ),
      body: HTTPBody(try configuration.bodyCoding.codec.encode(body)),
      timeout: timeout,
      expecting: responseType
    )
  }

  private func execute<Response: Decodable>(
    _ request: HTTPRequest,
    body: HTTPBody?,
    timeout: Duration?,
    expecting responseType: Response.Type
  ) async throws -> DecodedResponse<Response> {
    let response = try await transport.send(
      request,
      body: body,
      timeout: effectiveTimeout(timeout)
    )
    return try await decode(response, as: responseType)
  }

  private func decode<Response: Decodable>(
    _ response: TransportResponse,
    as responseType: Response.Type
  ) async throws -> DecodedResponse<Response> {
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
        let value = try configuration.bodyCoding.codec.decode(responseType, from: bufferedBody)
        return DecodedResponse(
          value: value,
          response: response.response,
          url: response.url
        )
      }
    }

    if responseType == EmptyResponse.self,
      let emptyResponse = EmptyResponse() as? Response
    {
      return DecodedResponse(
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

  private func makeRequest(
    method: HTTPRequest.Method,
    url: URL,
    headers: HTTPFields,
    includeRequestContentType: Bool,
    includeAccept: Bool
  ) -> HTTPRequest {
    var headers = mergedHeaders(additionalHeaders: headers)
    applyBodyCodingHeaders(
      to: &headers,
      includeRequestContentType: includeRequestContentType,
      includeAccept: includeAccept
    )

    return HTTPRequest(
      method: method,
      url: url,
      headerFields: headers
    )
  }

  private func prepare(
    _ request: HTTPRequest,
    includeRequestContentType: Bool = false,
    includeAccept: Bool = false
  ) -> HTTPRequest {
    var request = request
    request.headerFields = mergedHeaders(additionalHeaders: request.headerFields)
    applyBodyCodingHeaders(
      to: &request.headerFields,
      includeRequestContentType: includeRequestContentType,
      includeAccept: includeAccept
    )
    return request
  }

  private func applyBodyCodingHeaders(
    to headers: inout HTTPFields,
    includeRequestContentType: Bool,
    includeAccept: Bool
  ) {
    if includeRequestContentType,
      headers[.contentType] == nil,
      let requestContentType = configuration.bodyCoding.requestContentType
    {
      headers.append(.init(name: .contentType, value: requestContentType))
    }

    if includeAccept,
      headers[.accept] == nil
    {
      for value in configuration.bodyCoding.accept {
        headers.append(.init(name: .accept, value: value))
      }
    }
  }
}
