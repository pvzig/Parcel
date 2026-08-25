#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// Encodes and decodes typed request and response bodies for `Client`.
public protocol BodyCodec: Sendable {
  func encode<Request: Encodable>(_ value: Request) throws -> Data
  func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response

  /// The `Content-Type` header value `Client.Codec` applies by default for this codec.
  ///
  /// Return `nil` when the codec has no safe default.
  var defaultRequestContentType: String? { get }

  /// The `Accept` header values `Client.Codec` applies by default for this codec.
  ///
  /// Return an empty array when the codec has no safe defaults.
  var defaultAccept: [String] { get }

  /// Whether this codec can decode a zero-length response body into a value.
  var decodesEmptyResponseBodies: Bool { get }
}

extension BodyCodec {
  public var decodesEmptyResponseBodies: Bool { false }
}
