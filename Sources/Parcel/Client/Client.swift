import Foundation
import HTTPTypes

public struct Client: Sendable {
  public let configuration: ClientConfiguration
  private let transport: any Transport

  public init(configuration: ClientConfiguration = .init()) {
    self.init(
      configuration: configuration,
      transport: DefaultTransport.make()
    )
  }

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
    body: Data? = nil,
    timeout: Duration? = nil
  ) async throws -> (response: HTTPResponse, body: Data?, url: URL?) {
    try await transport.send(
      prepare(request),
      body: body,
      timeout: timeout
    )
  }

  public func sendResponse<Response: Decodable>(
    _ request: HTTPRequest,
    body: Data? = nil,
    timeout: Duration? = nil,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await execute(
      prepare(request),
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
        headers: headers
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
    let encoder = configuration.jsonCoding.makeEncoder()
    return try await execute(
      makeRequest(
        method: method,
        url: url,
        headers: headers
      ),
      body: try encoder.encode(body),
      timeout: timeout,
      expecting: responseType
    )
  }

  private func execute<Response: Decodable>(
    _ request: HTTPRequest,
    body: Data?,
    timeout: Duration?,
    expecting responseType: Response.Type
  ) async throws -> DecodedResponse<Response> {
    let response = try await transport.send(
      request,
      body: body,
      timeout: timeout
    )
    return try decode(response, as: responseType)
  }

  private func decode<Response: Decodable>(
    _ response: (response: HTTPResponse, body: Data?, url: URL?),
    as responseType: Response.Type
  ) throws -> DecodedResponse<Response> {
    guard (200..<300).contains(response.response.status.code) else {
      throw ClientError.unsuccessfulStatusCode(
        response.response.status.code,
        body: response.body.flatMap { String(data: $0, encoding: .utf8) }
      )
    }

    if let body = response.body, body.isEmpty == false {
      let decoder = configuration.jsonCoding.makeDecoder()
      let value = try decoder.decode(responseType, from: body)
      return DecodedResponse(
        value: value,
        response: response.response,
        body: body,
        url: response.url
      )
    }

    if responseType == EmptyResponse.self,
      let emptyResponse = EmptyResponse() as? Response
    {
      return DecodedResponse(
        value: emptyResponse,
        response: response.response,
        body: response.body,
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

  private func makeRequest(
    method: HTTPRequest.Method,
    url: URL,
    headers: HTTPFields
  ) -> HTTPRequest {
    HTTPRequest(
      method: method,
      url: url,
      headerFields: mergedHeaders(additionalHeaders: headers)
    )
  }

  private func prepare(_ request: HTTPRequest) -> HTTPRequest {
    var request = request
    request.headerFields = mergedHeaders(additionalHeaders: request.headerFields)
    return request
  }
}
