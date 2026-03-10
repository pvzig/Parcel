import Foundation
import HTTPTypes

public struct TransportResponse: Sendable {
  public let response: HTTPResponse
  public let body: HTTPBody?
  public let url: URL?

  public init(
    response: HTTPResponse,
    body: HTTPBody?,
    url: URL?
  ) {
    self.response = response
    self.body = body
    self.url = url
  }
}
