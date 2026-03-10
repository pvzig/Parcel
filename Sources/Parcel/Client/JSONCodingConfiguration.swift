import Foundation

public struct JSONCodingConfiguration: Sendable {
  public var makeEncoder: @Sendable () -> JSONEncoder
  public var makeDecoder: @Sendable () -> JSONDecoder

  public init(
    makeEncoder: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() },
    makeDecoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() }
  ) {
    self.makeEncoder = makeEncoder
    self.makeDecoder = makeDecoder
  }
}
