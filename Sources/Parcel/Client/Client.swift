import Foundation

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
    from url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .get,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    ).value
  }

  public func head<Response: Decodable>(
    from url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .head,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    ).value
  }

  public func delete<Response: Decodable>(
    from url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .delete,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    ).value
  }

  public func post<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .post,
      body: body,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    ).value
  }

  public func put<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .put,
      body: body,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    ).value
  }

  public func patch<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .patch,
      body: body,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    ).value
  }

  public func getResponse<Response: Decodable>(
    from url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .get,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    )
  }

  public func headResponse<Response: Decodable>(
    from url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .head,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    )
  }

  public func deleteResponse<Response: Decodable>(
    from url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .delete,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    )
  }

  public func postResponse<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .post,
      body: body,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    )
  }

  public func putResponse<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .put,
      body: body,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    )
  }

  public func patchResponse<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .patch,
      body: body,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    )
  }

  public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    try await transport.send(prepare(request))
  }

  public func sendResponse<Response: Decodable>(
    _ request: HTTPRequest,
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await execute(prepare(request), expecting: responseType)
  }

  public func send<Response: Decodable>(
    _ method: HTTPMethod,
    to url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      method,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    ).value
  }

  public func sendResponse<Response: Decodable>(
    _ method: HTTPMethod,
    to url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await execute(
      makeRequest(
        method: method,
        url: url,
        headers: headers,
        options: options
      ),
      expecting: responseType
    )
  }

  public func send<Request: Encodable, Response: Decodable>(
    _ method: HTTPMethod,
    body: Request,
    to url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      method,
      body: body,
      to: url,
      headers: headers,
      options: options,
      expecting: responseType
    ).value
  }

  public func sendResponse<Request: Encodable, Response: Decodable>(
    _ method: HTTPMethod,
    body: Request,
    to url: String,
    headers: HTTPHeaders = [:],
    options: HTTPRequestOptions = .init(),
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    let encoder = configuration.jsonCoding.makeEncoder()
    return try await execute(
      makeRequest(
        method: method,
        url: url,
        headers: headers,
        body: try encoder.encode(body),
        options: options
      ),
      expecting: responseType
    )
  }

  private func execute<Response: Decodable>(
    _ request: HTTPRequest,
    expecting responseType: Response.Type
  ) async throws -> DecodedResponse<Response> {
    let response = try await transport.send(request)
    return try decode(response, as: responseType)
  }

  private func decode<Response: Decodable>(
    _ response: HTTPResponse,
    as responseType: Response.Type
  ) throws -> DecodedResponse<Response> {
    guard (200..<300).contains(response.statusCode) else {
      throw ClientError.unsuccessfulStatusCode(response.statusCode, body: response.textBody)
    }

    if let body = response.body, body.isEmpty == false {
      let decoder = configuration.jsonCoding.makeDecoder()
      let value = try decoder.decode(responseType, from: body)
      return DecodedResponse(value: value, response: response)
    }

    if responseType == EmptyResponse.self,
      let emptyResponse = EmptyResponse() as? Response
    {
      return DecodedResponse(value: emptyResponse, response: response)
    }

    throw ClientError.emptyResponseBody
  }

  private func mergedHeaders(additionalHeaders: HTTPHeaders) -> HTTPHeaders {
    var headers = configuration.defaultHeaders

    headers.merge(overridingWith: additionalHeaders)

    return headers
  }

  private func makeRequest(
    method: HTTPMethod,
    url: String,
    headers: HTTPHeaders,
    body: Data? = nil,
    options: HTTPRequestOptions
  ) -> HTTPRequest {
    HTTPRequest(
      method: method,
      url: url,
      headers: mergedHeaders(additionalHeaders: headers),
      body: body,
      options: options
    )
  }

  private func prepare(_ request: HTTPRequest) -> HTTPRequest {
    HTTPRequest(
      method: request.method,
      url: request.url,
      headers: mergedHeaders(additionalHeaders: request.headers),
      body: request.body,
      options: request.options
    )
  }
}
