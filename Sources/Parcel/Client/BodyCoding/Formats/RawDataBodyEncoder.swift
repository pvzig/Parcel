#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// A request-body encoder that passes typed `Data` values through unchanged.
public struct RawDataBodyEncoder: RequestBodyEncoder, Sendable {
    public var defaultContentType: String? { "application/octet-stream" }

    public init() {}

    public func encode<Request: Encodable>(_ value: Request) throws -> Data {
        guard let data = value as? Data else {
            throw EncodingError.invalidValue(
                value,
                .init(
                    codingPath: [],
                    debugDescription: "RawDataBodyEncoder only supports Data request bodies."
                )
            )
        }

        return data
    }
}
