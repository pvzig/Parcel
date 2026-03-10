import Foundation

public struct HTTPRequest: Equatable, Sendable {
  public let method: HTTPMethod
  public let url: URL
  public let headers: HTTPHeaders
  public let body: Data?
  public let options: HTTPRequestOptions

  public init(
    method: HTTPMethod,
    url: URL,
    headers: HTTPHeaders = [:],
    body: Data? = nil,
    options: HTTPRequestOptions = .init()
  ) {
    self.method = method
    self.url = url
    self.headers = headers
    self.body = body
    self.options = options
  }
}
