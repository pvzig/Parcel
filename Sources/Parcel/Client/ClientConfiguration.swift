import HTTPTypes

public struct ClientConfiguration: Sendable {
  public var defaultHeaders: HTTPFields
  public var bodyCoding: BodyCodingConfiguration
  public var defaultTimeout: Duration?
  public var maximumBufferedBodyBytes: Int

  public init(
    defaultHeaders: HTTPFields = [:],
    bodyCoding: BodyCodingConfiguration = .json(),
    defaultTimeout: Duration? = .seconds(90),
    maximumBufferedBodyBytes: Int = HTTPBody.defaultMaximumCollectedBytes
  ) {
    precondition(maximumBufferedBodyBytes >= 0, "maximumBufferedBodyBytes must be nonnegative")
    self.defaultHeaders = defaultHeaders
    self.bodyCoding = bodyCoding
    self.defaultTimeout = defaultTimeout
    self.maximumBufferedBodyBytes = maximumBufferedBodyBytes
  }
}
