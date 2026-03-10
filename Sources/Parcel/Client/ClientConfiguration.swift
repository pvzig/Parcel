public struct ClientConfiguration: Sendable {
  public var defaultHeaders: HTTPHeaders
  public var jsonCoding: JSONCodingConfiguration

  public init(
    defaultHeaders: HTTPHeaders = [:],
    jsonCoding: JSONCodingConfiguration = .init()
  ) {
    self.defaultHeaders = defaultHeaders
    self.jsonCoding = jsonCoding
  }
}
