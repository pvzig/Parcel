#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

extension Client {
  /// Describes how Parcel encodes typed request bodies and decodes typed responses.
  ///
  /// The initializers come in overload sets rather than one initializer with defaulted arguments
  /// because `nil` and `[]` are meaningful values here: passing them suppresses the header
  /// outright, so they cannot double as "use the body codec's declared media type." Built-in
  /// factories always adopt the body codec's declarations.
  ///
  /// A custom `BodyCodec` needs no factory of its own — initialize a codec with it directly, as in
  /// `Client.Codec(bodyCodec: MyCodec())`.
  public struct Codec: Sendable {
    /// The codec used to transform between typed values and raw body bytes.
    public let bodyCodec: any BodyCodec

    /// The default `Content-Type` header for typed requests that Parcel encodes.
    public let requestContentType: String?

    /// The default `Accept` header values for typed requests and typed response decoding.
    public let accept: [String]

    /// Creates a codec description using the body codec's declared media types.
    public init(bodyCodec: any BodyCodec) {
      self.bodyCodec = bodyCodec
      self.requestContentType = bodyCodec.defaultRequestContentType
      self.accept = bodyCodec.defaultAccept
    }

    /// Creates a codec with an exact request content type and the body codec's default accepts.
    public init(
      bodyCodec: any BodyCodec,
      requestContentType: String?
    ) {
      self.bodyCodec = bodyCodec
      self.requestContentType = requestContentType
      self.accept = bodyCodec.defaultAccept
    }

    /// Creates a codec with the body codec's default request content type and exact accepts.
    public init(
      bodyCodec: any BodyCodec,
      accept: [String]
    ) {
      self.bodyCodec = bodyCodec
      self.requestContentType = bodyCodec.defaultRequestContentType
      self.accept = accept
    }

    /// Creates a codec with exact media-type header values.
    public init(
      bodyCodec: any BodyCodec,
      requestContentType: String?,
      accept: [String]
    ) {
      self.bodyCodec = bodyCodec
      self.requestContentType = requestContentType
      self.accept = accept
    }

    /// Returns a JSON codec description.
    public static func json(codec: JSONBodyCodec = .init()) -> Self {
      Self(bodyCodec: codec)
    }

    /// Returns a form URL-encoded codec description.
    public static func formURLEncoded(codec: FormURLEncodedBodyCodec = .init()) -> Self {
      Self(bodyCodec: codec)
    }

    /// Returns a UTF-8 plain-text codec description.
    public static func plainText(codec: PlainTextBodyCodec = .init()) -> Self {
      Self(bodyCodec: codec)
    }

    /// Returns a raw binary codec description.
    public static func rawData(codec: RawDataBodyCodec = .init()) -> Self {
      Self(bodyCodec: codec)
    }

    func encode<Request: Encodable>(_ value: Request) throws -> Data {
      try bodyCodec.encode(value)
    }

    func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
      try bodyCodec.decode(type, from: data)
    }
  }
}
