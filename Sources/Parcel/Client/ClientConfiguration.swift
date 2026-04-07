import HTTPTypes

public struct ClientConfiguration: Sendable {
  public var defaultHeaders: HTTPFields
  public var defaultCodec: Client.Codec
  public var defaultTimeout: Duration?
  public var maximumBufferedBodyBytes: Int

  public init(
    defaultHeaders: HTTPFields = [:],
    defaultCodec: Client.Codec = .json(),
    defaultTimeout: Duration? = .seconds(90),
    maximumBufferedBodyBytes: Int = HTTPBody.defaultMaximumCollectedBytes
  ) {
    precondition(maximumBufferedBodyBytes >= 0, "maximumBufferedBodyBytes must be nonnegative")
    self.defaultHeaders = defaultHeaders
    self.defaultCodec = defaultCodec
    self.defaultTimeout = defaultTimeout
    self.maximumBufferedBodyBytes = maximumBufferedBodyBytes
  }
}
