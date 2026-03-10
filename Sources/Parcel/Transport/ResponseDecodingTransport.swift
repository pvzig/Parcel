protocol ResponseDecodingTransport: Transport {
  /// Sends a request and decodes a successful response, throwing on non-2xx status codes.
  func sendResponse<Response: Decodable>(
    _ request: HTTPRequest,
    expecting responseType: Response.Type
  ) async throws -> DecodedResponse<Response>
}
