import HTTPTypes

/// The immutable, client-wide defaults Parcel applies when preparing requests and decoding
/// responses.
public struct ClientConfiguration: Sendable {
  /// Header fields added to every request, unless a per-request field overrides the same name.
  public let defaultHeaders: HTTPFields

  /// The codec used whenever `Client.send` is called without an explicit codec.
  public let defaultCodec: Client.Codec

  /// The timeout applied whenever a call omits one; `nil` disables the default timeout.
  ///
  /// The browser transport's deadline covers the fetch *and* the consumption of the response
  /// body, so a client streaming long-lived responses should configure this property as `nil`.
  public let defaultTimeout: Duration?

  /// The cap on response bytes Parcel buffers in memory when decoding or reporting an error body.
  public let maximumBufferedBodyBytes: Int

  /// Creates a configuration. Every parameter has a conservative default.
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
