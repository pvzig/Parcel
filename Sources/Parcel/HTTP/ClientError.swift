import HTTPTypes

/// The errors Parcel throws for validation, buffering, and status-code failures.
///
/// Task cancellation is reported as `CancellationError`, and codec failures surface as
/// `EncodingError` / `DecodingError`, so neither appears here.
public enum ClientError: Error, Equatable {
  /// A successful response carried no bytes, and the codec cannot decode an empty body.
  case emptyResponseBody

  /// The request URL is not an absolute URL with a scheme and a host. Carries the URL string.
  case invalidRequestURL(String)

  /// A `GET` or `HEAD` request carried a body, which the Fetch specification forbids.
  case requestBodyNotAllowed(HTTPRequest.Method)

  /// The response body exceeded the configured in-memory buffering limit.
  case responseBodyTooLarge(maximumBytes: Int)

  /// A typed request received a non-2xx response. Carries the status code and, when it could be
  /// read within `maximumBufferedBodyBytes`, the response body as text.
  case unsuccessfulStatusCode(Int, body: String?)
}
