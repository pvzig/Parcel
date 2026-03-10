import Foundation
import HTTPTypes

public struct DecodedResponse<Value> {
  public let value: Value
  public let response: HTTPResponse
  public let body: Data?
  public let url: URL?

  public init(
    value: Value,
    response: HTTPResponse,
    body: Data?,
    url: URL?
  ) {
    self.value = value
    self.response = response
    self.body = body
    self.url = url
  }
}
