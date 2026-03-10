import Foundation
import HTTPTypes

public protocol Transport: Sendable {
  /// Sends a raw request and returns the HTTP response as-is, including non-2xx status codes.
  /// Higher-level callers are responsible for interpreting the returned status code.
  func send(
    _ request: HTTPRequest,
    body: Data?,
    timeout: Duration?
  ) async throws -> (response: HTTPResponse, body: Data?, url: URL?)
}
