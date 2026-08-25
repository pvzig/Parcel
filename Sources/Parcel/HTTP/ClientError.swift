import HTTPTypes

/// The errors Parcel throws for transport, validation, and status-code failures.
///
/// Task cancellation is reported as `CancellationError`, and codec failures surface as
/// `EncodingError` / `DecodingError`, so neither appears here.
public enum ClientError: Error, Equatable {
  /// JavaScript error metadata captured from a rejected browser promise.
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

  /// A successful response carried no bytes, and the codec cannot decode an empty body.
  case emptyResponseBody

  /// The `fetch` promise rejected for a reason other than an abort: offline, DNS, CORS, or a
  /// URL the browser refused outright.
  case fetchFailure(JavaScriptError)

  /// The browser returned something Parcel could not read as a `Response`, such as a missing or
  /// out-of-range status code.
  case invalidFetchResponse

  /// Required JavaScript globals disappeared after the browser transport initialized.
  case invalidJavaScriptContext

  /// The request URL is not an absolute URL with a scheme and a host. Carries the URL string.
  case invalidRequestURL(String)

  /// The response body stream yielded something other than a `Uint8Array`.
  case invalidResponseBody

  /// A `GET` or `HEAD` request carried a body, which the Fetch specification forbids.
  case requestBodyNotAllowed(HTTPRequest.Method)

  /// Reading the response body's byte stream failed after the response head arrived.
  case responseBodyFailure(JavaScriptError)

  /// The request, or the consumption of its response body, exceeded the timeout.
  case timedOut

  /// A typed request received a non-2xx response. Carries the status code and, when it could be
  /// read within `maximumBufferedBodyBytes`, the response body as text.
  case unsuccessfulStatusCode(Int, body: String?)

  /// Parcel compiled for `wasm32` but no browser-capable JavaScript runtime is available.
  case unsupportedPlatform
}
