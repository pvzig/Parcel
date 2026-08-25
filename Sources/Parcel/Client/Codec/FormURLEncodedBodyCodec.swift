#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A `BodyCodec` for flat `application/x-www-form-urlencoded` payloads.
///
/// `FormURLEncodedBodyCodec` supports top-level keyed payloads plus repeated keys for array
/// values. Nested keyed containers are unsupported.
public struct FormURLEncodedBodyCodec: BodyCodec, Sendable {
  public var defaultRequestContentType: String? { "application/x-www-form-urlencoded" }
  public var defaultAccept: [String] { ["application/x-www-form-urlencoded"] }

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

/// The shape restrictions this codec enforces, phrased once so the encoder and the decoder report
/// the same limitation in the same words.
enum FormURLEncodedShapeError {
  static let nestedKeyedContainer =
    "FormURLEncodedBodyCodec does not support nested keyed containers."
  static let nestedArray = "Form field arrays cannot contain nested arrays."
  static let nilArrayElement = "Form field arrays cannot contain nil elements."
  static let topLevelKeyedOnly = "FormURLEncodedBodyCodec only supports top-level keyed values."
  static let arrayUnderKeyOnly =
    "FormURLEncodedBodyCodec only supports arrays nested under a keyed value."
}
