import HTTPTypes

extension HTTPRequest.Method {
  func validateBodyAllowed(hasBody: Bool) throws {
    if hasBody, self == .get || self == .head {
      throw ClientError.requestBodyNotAllowed(self)
    }
  }
}
