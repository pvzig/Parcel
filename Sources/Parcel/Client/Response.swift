import HTTPTypes

#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

extension Client {
  /// A successfully decoded response value plus the response metadata Parcel preserved.
  public struct Response<Value> {
    /// The decoded response value.
    public let value: Value

    /// The HTTP response head returned by the transport.
    public let response: HTTPResponse

    /// The final response URL, if the transport reported one.
    public let url: URL?

    /// Creates a typed response wrapper.
    public init(
      value: Value,
      response: HTTPResponse,
      url: URL?
    ) {
      self.value = value
      self.response = response
      self.url = url
    }
  }
}

extension Client.Response: Sendable where Value: Sendable {}
