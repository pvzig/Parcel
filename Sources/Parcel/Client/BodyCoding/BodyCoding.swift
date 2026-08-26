#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

extension Client {
  public struct BodyCoding: Sendable {
    /// The encoder used to transform typed request values into raw body bytes.
    public let requestEncoder: any RequestBodyEncoder

    /// The decoder used to transform raw response bytes into typed values.
    public let responseDecoder: any ResponseBodyDecoder

    /// The default `Content-Type` header for typed requests that Parcel encodes.
    public let requestContentType: String?

    /// The default `Accept` header values for typed requests and typed response decoding.
    public let accept: [String]

    /// Creates body coding using the encoder and decoder's declared media types.
    public init(
      requestEncoder: any RequestBodyEncoder,
      responseDecoder: any ResponseBodyDecoder
    ) {
      self.requestEncoder = requestEncoder
      self.responseDecoder = responseDecoder
      self.requestContentType = requestEncoder.defaultContentType
      self.accept = responseDecoder.defaultAccept
    }

    /// Creates body coding with an exact request content type and the decoder's default accepts.
    public init(
      requestEncoder: any RequestBodyEncoder,
      responseDecoder: any ResponseBodyDecoder,
      requestContentType: String?
    ) {
      self.requestEncoder = requestEncoder
      self.responseDecoder = responseDecoder
      self.requestContentType = requestContentType
      self.accept = responseDecoder.defaultAccept
    }

    /// Creates body coding with the encoder's default request content type and exact accepts.
    public init(
      requestEncoder: any RequestBodyEncoder,
      responseDecoder: any ResponseBodyDecoder,
      accept: [String]
    ) {
      self.requestEncoder = requestEncoder
      self.responseDecoder = responseDecoder
      self.requestContentType = requestEncoder.defaultContentType
      self.accept = accept
    }

    /// Creates body coding with exact media-type header values.
    public init(
      requestEncoder: any RequestBodyEncoder,
      responseDecoder: any ResponseBodyDecoder,
      requestContentType: String?,
      accept: [String]
    ) {
      self.requestEncoder = requestEncoder
      self.responseDecoder = responseDecoder
      self.requestContentType = requestContentType
      self.accept = accept
    }

    /// Returns JSON request and response body coding.
    public static func json(
      encoder: JSONBodyEncoder = .init(),
      decoder: JSONBodyDecoder = .init()
    ) -> Self {
      Self(requestEncoder: encoder, responseDecoder: decoder)
    }

    /// Returns form URL-encoded request and JSON response body coding.
    public static func formURLEncoded(
      encoder: FormURLEncodedBodyEncoder = .init(),
      decoder: any ResponseBodyDecoder = JSONBodyDecoder()
    ) -> Self {
      Self(requestEncoder: encoder, responseDecoder: decoder)
    }

    /// Returns UTF-8 plain-text request and response body coding.
    public static func plainText(
      encoder: PlainTextBodyEncoder = .init(),
      decoder: PlainTextBodyDecoder = .init()
    ) -> Self {
      Self(requestEncoder: encoder, responseDecoder: decoder)
    }

    /// Returns raw binary request and response body coding.
    public static func rawData(
      encoder: RawDataBodyEncoder = .init(),
      decoder: RawDataBodyDecoder = .init()
    ) -> Self {
      Self(requestEncoder: encoder, responseDecoder: decoder)
    }

    func encode<Request: Encodable>(_ value: Request) throws -> Data {
      try requestEncoder.encode(value)
    }

    func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
      try responseDecoder.decode(type, from: data)
    }
  }
}
