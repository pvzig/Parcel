#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A request-body encoder for JSON values.
public struct JSONBodyEncoder: RequestBodyEncoder, Sendable {
  public let makeEncoder: @Sendable () -> JSONEncoder

  public var defaultContentType: String? { "application/json" }

  public init(
    makeEncoder: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() }
  ) {
    self.makeEncoder = makeEncoder
  }

  public func encode<Request: Encodable>(_ value: Request) throws -> Data {
    try makeEncoder().encode(value)
  }
}
