public enum ClientError: Error, Equatable {
  public struct ResponseBodyFailure: Equatable, Sendable {
    public enum Operation: String, Equatable, Sendable {
      case bytes
      case json
      case text
    }

    public struct JavaScriptError: Equatable, Sendable {
      public let name: String?
      public let message: String?
      public let description: String
      public let stack: String?

      public init(
        name: String?,
        message: String?,
        description: String,
        stack: String?
      ) {
        self.name = name
        self.message = message
        self.description = description
        self.stack = stack
      }
    }

    public let operation: Operation
    public let javaScriptError: JavaScriptError

    public init(
      operation: Operation,
      javaScriptError: JavaScriptError
    ) {
      self.operation = operation
      self.javaScriptError = javaScriptError
    }
  }

  case emptyResponseBody
  case invalidFetchResponse
  case invalidJavaScriptContext
  case invalidResponseBody
  case responseBodyFailure(ResponseBodyFailure)
  case unsuccessfulStatusCode(Int, body: String?)
  case unsupportedPlatform
}
