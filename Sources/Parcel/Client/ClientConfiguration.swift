import HTTPTypes

public struct ClientConfiguration: Sendable {
  public var defaultHeaders: HTTPFields
  public var bodyCodec: any BodyCodec

  public init(
    defaultHeaders: HTTPFields = [:],
    bodyCodec: any BodyCodec = JSONBodyCodec()
  ) {
    self.defaultHeaders = defaultHeaders
    self.bodyCodec = bodyCodec
  }
}
