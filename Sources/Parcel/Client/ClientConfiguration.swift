import HTTPTypes

public struct ClientConfiguration: Sendable {
  public var defaultHeaders: HTTPFields
  public var bodyCoding: BodyCodingConfiguration

  public init(
    defaultHeaders: HTTPFields = [:],
    bodyCoding: BodyCodingConfiguration = .json()
  ) {
    self.defaultHeaders = defaultHeaders
    self.bodyCoding = bodyCoding
  }
}
