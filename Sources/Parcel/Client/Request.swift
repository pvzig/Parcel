import HTTPTypes

#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

extension Client {
  /// A complete HTTP operation that produces a decoded `Output` value.
  public struct Request<Output: Decodable>: Sendable {
    /// The HTTP method Parcel sends.
    public let method: HTTPRequest.Method

    /// The target URL.
    public let url: URL

    /// Header fields appended after the client's default headers.
    public var headers: HTTPFields

    /// Per-operation body coding, or `nil` to use the client's default.
    public let bodyCoding: BodyCoding?

    private let makeBody: (@Sendable (BodyCoding) throws -> Data?)?

    /// Creates a request without a typed body.
    public init(
      method: HTTPRequest.Method,
      url: URL,
      headers: HTTPFields = [:],
      bodyCoding: BodyCoding? = nil
    ) {
      self.method = method
      self.url = url
      self.headers = headers
      self.bodyCoding = bodyCoding
      self.makeBody = nil
    }

    /// Creates a request with a typed body that Parcel encodes using the chosen body coding.
    public init<Body: Encodable & Sendable>(
      method: HTTPRequest.Method,
      url: URL,
      headers: HTTPFields = [:],
      body: Body,
      bodyCoding: BodyCoding? = nil
    ) {
      self.method = method
      self.url = url
      self.headers = headers
      self.bodyCoding = bodyCoding
      self.makeBody = { bodyCoding in
        try bodyCoding.encode(body)
      }
    }

    /// Returns a `GET` request.
    public static func get(
      _ url: URL,
      headers: HTTPFields = [:],
      bodyCoding: BodyCoding? = nil
    ) -> Self {
      .init(
        method: .get,
        url: url,
        headers: headers,
        bodyCoding: bodyCoding
      )
    }

    /// Returns a `HEAD` request.
    public static func head(
      _ url: URL,
      headers: HTTPFields = [:],
      bodyCoding: BodyCoding? = nil
    ) -> Self {
      .init(
        method: .head,
        url: url,
        headers: headers,
        bodyCoding: bodyCoding
      )
    }

    /// Returns a `DELETE` request.
    public static func delete(
      _ url: URL,
      headers: HTTPFields = [:],
      bodyCoding: BodyCoding? = nil
    ) -> Self {
      .init(
        method: .delete,
        url: url,
        headers: headers,
        bodyCoding: bodyCoding
      )
    }

    /// Returns a `POST` request with a typed body.
    public static func post<Body: Encodable & Sendable>(
      _ url: URL,
      body: Body,
      headers: HTTPFields = [:],
      bodyCoding: BodyCoding? = nil
    ) -> Self {
      .init(
        method: .post,
        url: url,
        headers: headers,
        body: body,
        bodyCoding: bodyCoding
      )
    }

    /// Returns a `PUT` request with a typed body.
    public static func put<Body: Encodable & Sendable>(
      _ url: URL,
      body: Body,
      headers: HTTPFields = [:],
      bodyCoding: BodyCoding? = nil
    ) -> Self {
      .init(
        method: .put,
        url: url,
        headers: headers,
        body: body,
        bodyCoding: bodyCoding
      )
    }

    /// Returns a `PATCH` request with a typed body.
    public static func patch<Body: Encodable & Sendable>(
      _ url: URL,
      body: Body,
      headers: HTTPFields = [:],
      bodyCoding: BodyCoding? = nil
    ) -> Self {
      .init(
        method: .patch,
        url: url,
        headers: headers,
        body: body,
        bodyCoding: bodyCoding
      )
    }

    var hasBody: Bool {
      makeBody != nil
    }

    func encodedBody(using bodyCoding: BodyCoding) throws -> Data? {
      try makeBody?(bodyCoding)
    }
  }
}
