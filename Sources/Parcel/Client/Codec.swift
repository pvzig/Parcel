import Foundation

extension Client {
  /// Describes how Parcel encodes typed request bodies and decodes typed responses.
  public struct Codec: Sendable {
    /// The codec used to transform between typed values and raw body bytes.
    public let bodyCodec: any BodyCodec

    /// The default `Content-Type` header for typed requests that Parcel encodes.
    public let requestContentType: String?

    /// The default `Accept` header values for typed requests and typed response decoding.
    public let accept: [String]

    /// Creates a codec description.
    public init(
      bodyCodec: any BodyCodec,
      requestContentType: String? = nil,
      accept: [String] = []
    ) {
      self.bodyCodec = bodyCodec
      self.requestContentType = requestContentType
      self.accept = accept
    }

    /// Returns a JSON codec description.
    public static func json(
      codec: JSONBodyCodec = .init(),
      requestContentType: String? = "application/json",
      accept: [String] = ["application/json"]
    ) -> Self {
      Self(
        bodyCodec: codec,
        requestContentType: requestContentType,
        accept: accept
      )
    }

    /// Returns a form URL-encoded codec description.
    public static func formURLEncoded(
      codec: FormURLEncodedBodyCodec = .init(),
      requestContentType: String? = "application/x-www-form-urlencoded",
      accept: [String] = ["application/x-www-form-urlencoded"]
    ) -> Self {
      Self(
        bodyCodec: codec,
        requestContentType: requestContentType,
        accept: accept
      )
    }

    /// Returns a UTF-8 plain-text codec description.
    public static func plainText(
      codec: PlainTextBodyCodec = .init(),
      requestContentType: String? = "text/plain",
      accept: [String] = ["text/plain"]
    ) -> Self {
      Self(
        bodyCodec: codec,
        requestContentType: requestContentType,
        accept: accept
      )
    }

    /// Returns a raw binary codec description.
    public static func rawData(
      codec: RawDataBodyCodec = .init(),
      requestContentType: String? = "application/octet-stream",
      accept: [String] = ["application/octet-stream"]
    ) -> Self {
      Self(
        bodyCodec: codec,
        requestContentType: requestContentType,
        accept: accept
      )
    }

    /// Returns a custom codec description.
    public static func custom(
      _ bodyCodec: any BodyCodec,
      requestContentType: String? = nil,
      accept: [String] = []
    ) -> Self {
      Self(
        bodyCodec: bodyCodec,
        requestContentType: requestContentType,
        accept: accept
      )
    }

    func encode<Request: Encodable>(_ value: Request) throws -> Data {
      try bodyCodec.encode(value)
    }

    func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
      try bodyCodec.decode(type, from: data)
    }
  }
}
