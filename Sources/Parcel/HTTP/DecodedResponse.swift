public struct DecodedResponse<Value> {
  public let value: Value
  public let response: HTTPResponse

  public init(value: Value, response: HTTPResponse) {
    self.value = value
    self.response = response
  }
}
