import Foundation

/// Encodes and decodes typed request and response bodies for `Client`.
public protocol BodyCodec: Sendable {
  func encode<Request: Encodable>(_ value: Request) throws -> Data
  func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response
}
