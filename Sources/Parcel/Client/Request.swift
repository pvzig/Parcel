import HTTPTypes

#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

extension Client {
  /// A typed request description that Parcel encodes using a `Codec` when sent.
  public struct Request {
    /// The HTTP method Parcel sends.
    public let method: HTTPRequest.Method

    /// The target URL.
    public let url: URL

    /// Header fields appended after the client's default headers.
    public var headers: HTTPFields

    private let makeBody: ((Codec) throws -> HTTPBody?)?

    /// Creates a request without a typed body.
    public init(
      method: HTTPRequest.Method,
      url: URL,
      headers: HTTPFields = [:]
    ) {
      self.method = method
      self.url = url
      self.headers = headers
      self.makeBody = nil
    }

    /// Creates a request with a typed body that Parcel encodes using the chosen codec.
    public init<Body: Encodable>(
      method: HTTPRequest.Method,
      url: URL,
      headers: HTTPFields = [:],
      body: Body
    ) {
      self.method = method
      self.url = url
      self.headers = headers
      self.makeBody = { codec in
        HTTPBody(try codec.encode(body))
      }
    }

    /// Returns a `GET` request.
    public static func get(
      _ url: URL,
      headers: HTTPFields = [:]
    ) -> Self {
      .init(
        method: .get,
        url: url,
        headers: headers
      )
    }

    /// Returns a `HEAD` request.
    public static func head(
      _ url: URL,
      headers: HTTPFields = [:]
    ) -> Self {
      .init(
        method: .head,
        url: url,
        headers: headers
      )
    }

    /// Returns a `DELETE` request.
    public static func delete(
      _ url: URL,
      headers: HTTPFields = [:]
    ) -> Self {
      .init(
        method: .delete,
        url: url,
        headers: headers
      )
    }

    /// Returns a `POST` request with a typed body.
    public static func post<Body: Encodable>(
      _ url: URL,
      body: Body,
      headers: HTTPFields = [:]
    ) -> Self {
      .init(
        method: .post,
        url: url,
        headers: headers,
        body: body
      )
    }

    /// Returns a `PUT` request with a typed body.
    public static func put<Body: Encodable>(
      _ url: URL,
      body: Body,
      headers: HTTPFields = [:]
    ) -> Self {
      .init(
        method: .put,
        url: url,
        headers: headers,
        body: body
      )
    }

    /// Returns a `PATCH` request with a typed body.
    public static func patch<Body: Encodable>(
      _ url: URL,
      body: Body,
      headers: HTTPFields = [:]
    ) -> Self {
      .init(
        method: .patch,
        url: url,
        headers: headers,
        body: body
      )
    }

    var hasBody: Bool {
      makeBody != nil
    }

    func encodedBody(using codec: Codec) throws -> HTTPBody? {
      try makeBody?(codec)
    }
  }
}
