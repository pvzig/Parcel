#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// A request-body encoder for flat `application/x-www-form-urlencoded` payloads.
///
/// `FormURLEncodedBodyEncoder` supports top-level keyed payloads plus repeated keys for array
/// values. Nested keyed containers are unsupported.
public struct FormURLEncodedBodyEncoder: RequestBodyEncoder, Sendable {
    public var defaultContentType: String? { "application/x-www-form-urlencoded" }

    public init() {}

    public func encode<Request: Encodable>(_ value: Request) throws -> Data {
        try FormURLEncodedEncoder.encode(value)
    }
}
