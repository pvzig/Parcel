public protocol Transport: Sendable {
  /// Sends a raw request and returns the HTTP response as-is, including non-2xx status codes.
  /// Higher-level callers are responsible for interpreting the returned status code.
  func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
