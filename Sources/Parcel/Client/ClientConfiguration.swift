public struct ClientConfiguration: Sendable {
  public var defaultHeaders: [String: String]
  public var jsonCoding: JSONCodingConfiguration

  public init(
    defaultHeaders: [String: String] = [:],
    jsonCoding: JSONCodingConfiguration = .init()
  ) {
    self.defaultHeaders = defaultHeaders
    self.jsonCoding = jsonCoding
  }
}
