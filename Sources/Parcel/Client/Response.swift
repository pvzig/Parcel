import HTTPTypes

extension Client {
    /// A successfully decoded response value plus the response metadata Parcel preserved.
    public struct Response<Value> {
        /// The decoded response value.
        public let value: Value

        /// The HTTP response head returned by the underlying HTTP client.
        public let response: HTTPResponse

        /// Creates a typed response wrapper.
        public init(
            value: Value,
            response: HTTPResponse
        ) {
            self.value = value
            self.response = response
        }
    }
}

extension Client.Response: Sendable where Value: Sendable {}
