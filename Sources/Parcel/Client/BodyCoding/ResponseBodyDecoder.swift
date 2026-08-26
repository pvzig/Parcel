#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// Decodes typed response bodies for `Client`.
public protocol ResponseBodyDecoder: Sendable {
  func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response

  /// The `Accept` header values `Client.BodyCoding` applies by default for this decoder.
  ///
  /// Return an empty array when the decoder has no safe defaults.
  var defaultAccept: [String] { get }

  /// Whether this decoder can decode a zero-length response body into a value.
  var decodesEmptyResponseBodies: Bool { get }
}

extension ResponseBodyDecoder {
  public var decodesEmptyResponseBodies: Bool { false }
}
