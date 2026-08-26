#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// A response-body decoder that passes raw `Data` values through unchanged.
public struct RawDataBodyDecoder: ResponseBodyDecoder, Sendable {
    public var defaultAccept: [String] { ["application/octet-stream"] }
    public var decodesEmptyResponseBodies: Bool { true }

    public init() {}

    public func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws
        -> Response
    {
        guard let value = data as? Response else {
            throw DecodingError.typeMismatch(
                type,
                .init(
                    codingPath: [],
                    debugDescription: "RawDataBodyDecoder only supports Data response bodies."
                )
            )
        }

        return value
    }
}
