import Foundation

/// A `BodyCodec` for flat `application/x-www-form-urlencoded` payloads.
///
/// `FormURLEncodedBodyCodec` supports top-level keyed payloads plus repeated keys for array
/// values. Nested keyed containers are unsupported.
public struct FormURLEncodedBodyCodec: BodyCodec, Sendable {
  public init() {}

  public func encode<Request: Encodable>(_ value: Request) throws -> Data {
    try FormURLEncodedEncoder.encode(value)
  }

  public func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws
    -> Response
  {
    try FormURLEncodedDecoder.decode(type, from: data)
  }
}
