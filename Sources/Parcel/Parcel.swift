public struct ParcelClientConfiguration: Sendable, Equatable {
  public var defaultHeaders: [String: String]

  public init(defaultHeaders: [String: String] = [:]) {
    self.defaultHeaders = defaultHeaders
  }
}

public struct ParcelClient: Sendable {
  public let configuration: ParcelClientConfiguration

  public init(configuration: ParcelClientConfiguration = .init()) {
    self.configuration = configuration
  }
}

public enum ParcelMethod: String, CaseIterable, Sendable {
  case delete = "DELETE"
  case get = "GET"
  case patch = "PATCH"
  case post = "POST"
  case put = "PUT"
}
