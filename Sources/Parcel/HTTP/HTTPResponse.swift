import Foundation

public struct HTTPResponse: Equatable, Sendable {
  public let statusCode: Int
  public let headers: [String: String]
  public let url: String?
  public let body: Data?

  public init(
    statusCode: Int,
    headers: [String: String] = [:],
    url: String? = nil,
    body: Data? = nil
  ) {
    self.statusCode = statusCode
    self.headers = headers
    self.url = url
    self.body = body
  }

  public var textBody: String? {
    body.flatMap { String(data: $0, encoding: .utf8) }
  }
}
