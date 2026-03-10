import HTTPTypes

public struct ClientConfiguration: Sendable {
  public var defaultHeaders: HTTPFields
  public var jsonCoding: JSONCodingConfiguration

  public init(
    defaultHeaders: HTTPFields = [:],
    jsonCoding: JSONCodingConfiguration = .init()
  ) {
    self.defaultHeaders = defaultHeaders
    self.jsonCoding = jsonCoding
  }
}
