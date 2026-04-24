#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A `BodyCodec` that encodes and decodes request bodies as JSON.
public struct JSONBodyCodec: BodyCodec, Sendable {
  public var makeEncoder: @Sendable () -> JSONEncoder
  public var makeDecoder: @Sendable () -> JSONDecoder

  public init(
    makeEncoder: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() },
    makeDecoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() }
  ) {
    self.makeEncoder = makeEncoder
    self.makeDecoder = makeDecoder
  }

  public func encode<Request: Encodable>(_ value: Request) throws -> Data {
    try makeEncoder().encode(value)
  }

  public func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws
    -> Response
  {
    try makeDecoder().decode(type, from: data)
  }
}
