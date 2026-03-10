import Foundation

public struct JSONCodingConfiguration: Sendable {
  public var makeEncoder: @Sendable () -> JSONEncoder
  public var makeDecoder: @Sendable () -> JSONDecoder
  public var prefersTransportSpecificResponseDecoding: Bool

  public init(
    makeEncoder: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() },
    makeDecoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() },
    prefersTransportSpecificResponseDecoding: Bool = true
  ) {
    self.makeEncoder = makeEncoder
    self.makeDecoder = makeDecoder
    self.prefersTransportSpecificResponseDecoding = prefersTransportSpecificResponseDecoding
  }
}
