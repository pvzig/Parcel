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
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .get,
      to: url,
      headers: headers,
      expecting: responseType
    ).value
  }

  public func delete<Response: Decodable>(
    from url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .delete,
      to: url,
      headers: headers,
      expecting: responseType
    ).value
  }

  public func post<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .post,
      body: body,
      to: url,
      headers: headers,
      expecting: responseType
    ).value
  }

  public func put<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .put,
      body: body,
      to: url,
      headers: headers,
      expecting: responseType
    ).value
  }

  public func patch<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      .patch,
      body: body,
      to: url,
      headers: headers,
      expecting: responseType
    ).value
  }

  public func getResponse<Response: Decodable>(
    from url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .get,
      to: url,
      headers: headers,
      expecting: responseType
    )
  }

  public func deleteResponse<Response: Decodable>(
    from url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .delete,
      to: url,
      headers: headers,
      expecting: responseType
    )
  }

  public func postResponse<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .post,
      body: body,
      to: url,
      headers: headers,
      expecting: responseType
    )
  }

  public func putResponse<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .put,
      body: body,
      to: url,
      headers: headers,
      expecting: responseType
    )
  }

  public func patchResponse<Request: Encodable, Response: Decodable>(
    _ body: Request,
    to url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    try await sendResponse(
      .patch,
      body: body,
      to: url,
      headers: headers,
      expecting: responseType
    )
  }

  public func send<Response: Decodable>(
    _ method: HTTPMethod,
    to url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      method,
      to: url,
      headers: headers,
      expecting: responseType
    ).value
  }

  public func sendResponse<Response: Decodable>(
    _ method: HTTPMethod,
    to url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    let request = HTTPRequest(
      method: method,
      url: url,
      headers: mergedHeaders(additionalHeaders: headers, includesJSONBody: false)
    )
    return try await execute(request, expecting: responseType)
  }

  public func send<Request: Encodable, Response: Decodable>(
    _ method: HTTPMethod,
    body: Request,
    to url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> Response {
    try await sendResponse(
      method,
      body: body,
      to: url,
      headers: headers,
      expecting: responseType
    ).value
  }

  public func sendResponse<Request: Encodable, Response: Decodable>(
    _ method: HTTPMethod,
    body: Request,
    to url: String,
    headers: [String: String] = [:],
    expecting responseType: Response.Type = Response.self
  ) async throws -> DecodedResponse<Response> {
    let encoder = configuration.jsonCoding.makeEncoder()
    let request = HTTPRequest(
      method: method,
      url: url,
      headers: mergedHeaders(additionalHeaders: headers, includesJSONBody: true),
      body: try encoder.encode(body)
    )
    return try await execute(request, expecting: responseType)
  }

  private func execute<Response: Decodable>(
    _ request: HTTPRequest,
    expecting responseType: Response.Type
  ) async throws -> DecodedResponse<Response> {
    if configuration.jsonCoding.prefersTransportSpecificResponseDecoding,
      let responseDecodingTransport = transport as? any ResponseDecodingTransport
    {
      return try await responseDecodingTransport.sendResponse(
        request,
        expecting: responseType
      )
    }

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

  private func mergedHeaders(
    additionalHeaders: [String: String],
    includesJSONBody: Bool
  ) -> [String: String] {
    var headers = configuration.defaultHeaders

    for (name, value) in additionalHeaders {
      setHeader(name, value: value, in: &headers)
    }

    if containsHeader(named: "Accept", in: headers) == false {
      headers["Accept"] = "application/json"
    }

    if includesJSONBody && containsHeader(named: "Content-Type", in: headers) == false {
      headers["Content-Type"] = "application/json"
    }

    return headers
  }

  private func containsHeader(named headerName: String, in headers: [String: String]) -> Bool {
    headers.keys.contains { $0.lowercased() == headerName.lowercased() }
  }

  private func setHeader(
    _ name: String,
    value: String,
    in headers: inout [String: String]
  ) {
    if let existingName = headers.keys.first(where: { $0.lowercased() == name.lowercased() }) {
      headers.removeValue(forKey: existingName)
    }

    headers[name] = value
  }
}
