import HTTPTypes

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

extension Client {
    /// A raw HTTP response whose body was buffered inside the HTTP client's response handler.
    public struct RawResponse: Sendable {
        /// The response head returned by the HTTP client.
        public let response: HTTPResponse

        /// The complete response body, bounded by `maximumBufferedBodyBytes`.
        public let body: Data

        /// Creates a buffered raw response.
        public init(response: HTTPResponse, body: Data) {
            self.response = response
            self.body = body
        }
    }
}
