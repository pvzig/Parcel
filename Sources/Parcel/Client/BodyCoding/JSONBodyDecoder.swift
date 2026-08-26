#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// A response-body decoder for JSON values.
public struct JSONBodyDecoder: ResponseBodyDecoder, Sendable {
  public let makeDecoder: @Sendable () -> JSONDecoder

  public var defaultAccept: [String] { ["application/json"] }

  public init(
    makeDecoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() }
  ) {
    self.makeDecoder = makeDecoder
  }

  public func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws
    -> Response
  {
    try makeDecoder().decode(type, from: data)
  }
}
