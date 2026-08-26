#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A response-body decoder for UTF-8 plain-text `String` values.
///
/// Decoding validates that the response bytes are well-formed UTF-8 and throws
/// `DecodingError.dataCorrupted` otherwise.
public struct PlainTextBodyDecoder: ResponseBodyDecoder, Sendable {
  public var defaultAccept: [String] { ["text/plain"] }
  public var decodesEmptyResponseBodies: Bool { true }

  public init() {}

  public func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws
    -> Response
  {
    guard let text = String(data: data, encoding: .utf8) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: [],
          debugDescription: "PlainTextBodyDecoder expects UTF-8 response data."
        )
      )
    }

    guard let value = text as? Response else {
      throw DecodingError.typeMismatch(
        type,
        .init(
          codingPath: [],
          debugDescription: "PlainTextBodyDecoder only supports String response bodies."
        )
      )
    }

    return value
  }
}
