import Foundation

/// A `BodyCodec` that encodes and decodes UTF-8 plain-text `String` values.
public struct PlainTextBodyCodec: BodyCodec, Sendable {
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
    let text = String(decoding: data, as: UTF8.self)

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
