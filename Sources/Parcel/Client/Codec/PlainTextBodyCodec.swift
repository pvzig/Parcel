#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A `BodyCodec` that encodes and decodes UTF-8 plain-text `String` values.
///
/// Decoding validates that the response bytes are well-formed UTF-8 and throws
/// `DecodingError.dataCorrupted` otherwise.
public struct PlainTextBodyCodec: BodyCodec, Sendable {
  public var defaultRequestContentType: String? { "text/plain" }
  public var defaultAccept: [String] { ["text/plain"] }
  public var decodesEmptyResponseBodies: Bool { true }

  public init() {}

  public func encode<Request: Encodable>(_ value: Request) throws -> Data {
    guard let text = value as? String else {
      throw EncodingError.invalidValue(
        value,
        .init(
          codingPath: [],
          debugDescription: "PlainTextBodyCodec only supports String request bodies."
        )
      )
    }

    return Data(text.utf8)
  }

  public func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws
    -> Response
  {
    guard let text = String(data: data, encoding: .utf8) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: [],
          debugDescription: "PlainTextBodyCodec expects UTF-8 response data."
        )
      )
    }

    guard let value = text as? Response else {
      throw DecodingError.typeMismatch(
        type,
        .init(
          codingPath: [],
          debugDescription: "PlainTextBodyCodec only supports String response bodies."
        )
      )
    }

    return value
  }
}
