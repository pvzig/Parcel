import HTTPTypes

/// The immutable, client-wide defaults Parcel applies when preparing requests and decoding
/// responses.
public struct ClientConfiguration: Sendable {
  /// The default cap on response bytes Parcel buffers inside an HTTP client's response handler.
  public static let defaultMaximumBufferedBodyBytes = 2 * 1024 * 1024

  /// Header fields added to every request, unless a per-request field overrides the same name.
  public let defaultHeaders: HTTPFields

  /// The body coding used whenever an operation does not declare its own.
  public let defaultBodyCoding: Client.BodyCoding

  /// The cap on response bytes Parcel buffers in memory when decoding or reporting an error body.
  public let maximumBufferedBodyBytes: Int

  /// Creates a configuration. Every parameter has a conservative default.
  public init(
    defaultHeaders: HTTPFields = [:],
    defaultBodyCoding: Client.BodyCoding = .json(),
    maximumBufferedBodyBytes: Int = Self.defaultMaximumBufferedBodyBytes
  ) {
    precondition(maximumBufferedBodyBytes >= 0, "maximumBufferedBodyBytes must be nonnegative")
    self.defaultHeaders = defaultHeaders
    self.defaultBodyCoding = defaultBodyCoding
    self.maximumBufferedBodyBytes = maximumBufferedBodyBytes
  }
}
