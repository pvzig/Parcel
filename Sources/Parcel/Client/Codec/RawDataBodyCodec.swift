#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A `BodyCodec` that passes typed `Data` request and response bodies through unchanged.
public struct RawDataBodyCodec: BodyCodec, Sendable {
  public init() {}

  public func encode<Request: Encodable>(_ value: Request) throws -> Data {
    guard let data = value as? Data else {
      throw EncodingError.invalidValue(
        value,
        .init(
          codingPath: [],
          debugDescription: "RawDataBodyCodec only supports Data request bodies."
        )
      )
    }

    return data
  }

  public func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws
    -> Response
  {
    guard let value = data as? Response else {
      throw DecodingError.typeMismatch(
        type,
        .init(
          codingPath: [],
          debugDescription: "RawDataBodyCodec only supports Data response bodies."
        )
      )
    }

    return value
  }
}
