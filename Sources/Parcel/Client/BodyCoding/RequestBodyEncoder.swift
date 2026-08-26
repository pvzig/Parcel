#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// Encodes typed request bodies for `Client`.
public protocol RequestBodyEncoder: Sendable {
    func encode<Request: Encodable>(_ value: Request) throws -> Data

    /// The `Content-Type` header value `Client.BodyCoding` applies by default for this encoder.
    ///
    /// Return `nil` when the encoder has no safe default.
    var defaultContentType: String? { get }
}
