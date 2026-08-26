#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A request-body encoder for UTF-8 plain-text `String` values.
public struct PlainTextBodyEncoder: RequestBodyEncoder, Sendable {
  public var defaultContentType: String? { "text/plain" }

  public init() {}

  public func encode<Request: Encodable>(_ value: Request) throws -> Data {
    guard let text = value as? String else {
      throw EncodingError.invalidValue(
        value,
        .init(
          codingPath: [],
          debugDescription: "PlainTextBodyEncoder only supports String request bodies."
        )
      )
    }

    return Data(text.utf8)
  }
}
