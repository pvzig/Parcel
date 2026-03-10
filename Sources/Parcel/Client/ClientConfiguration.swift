import HTTPTypes

public struct ClientConfiguration: Sendable {
  public var defaultHeaders: HTTPFields
  public var bodyCoding: BodyCodingConfiguration
  public var defaultTimeout: Duration?

  public init(
    defaultHeaders: HTTPFields = [:],
    bodyCoding: BodyCodingConfiguration = .json(),
    defaultTimeout: Duration? = .seconds(90)
  ) {
    self.defaultHeaders = defaultHeaders
    self.bodyCoding = bodyCoding
    self.defaultTimeout = defaultTimeout
  }
}
