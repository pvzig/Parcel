#if !arch(wasm32)
    import Foundation
    import Testing

    @testable import Parcel

    /// Request encoder fixture with no declared media type, used to verify header defaults.
    private struct OpaqueRequestBodyEncoder: RequestBodyEncoder {
        var defaultContentType: String? { nil }

        func encode<Request: Encodable>(_ value: Request) throws -> Data {
            Data()
        }
    }

    /// Response decoder fixture with no declared media types, used to verify header defaults.
    private struct OpaqueResponseBodyDecoder: ResponseBodyDecoder {
        var defaultAccept: [String] { [] }

        func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response
        {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "OpaqueResponseBodyDecoder cannot decode.")
            )
        }
    }

    @Test func directBodyCodingConstructionUsesComponentMediaTypeDefaults() {
        let json = Client.BodyCoding(
            requestEncoder: JSONBodyEncoder(),
            responseDecoder: JSONBodyDecoder()
        )
        #expect(json.requestContentType == "application/json")
        #expect(json.accept == ["application/json"])

        let form = Client.BodyCoding.formURLEncoded()
        #expect(form.requestContentType == "application/x-www-form-urlencoded")
        #expect(form.accept == ["application/json"])

        let formWithTextResponse = Client.BodyCoding.formURLEncoded(
            decoder: PlainTextBodyDecoder()
        )
        #expect(formWithTextResponse.accept == ["text/plain"])

        let custom = Client.BodyCoding(
            requestEncoder: JSONBodyEncoder(),
            responseDecoder: JSONBodyDecoder(),
            requestContentType: "application/vnd.parcel+json",
            accept: ["application/vnd.parcel+json"]
        )
        #expect(custom.requestContentType == "application/vnd.parcel+json")
        #expect(custom.accept == ["application/vnd.parcel+json"])
    }

    @Test func componentsWithoutDeclaredMediaTypesApplyNoHeaderDefaults() {
        let bodyCoding = Client.BodyCoding(
            requestEncoder: OpaqueRequestBodyEncoder(),
            responseDecoder: OpaqueResponseBodyDecoder()
        )

        #expect(bodyCoding.requestContentType == nil)
        #expect(bodyCoding.accept == [])
    }

    @Test func explicitBodyCodingMediaTypesCanSuppressComponentDefaults() {
        let bodyCoding = Client.BodyCoding(
            requestEncoder: JSONBodyEncoder(),
            responseDecoder: JSONBodyDecoder(),
            requestContentType: nil,
            accept: []
        )

        #expect(bodyCoding.requestContentType == nil)
        #expect(bodyCoding.accept == [])
    }

    @Test func jsonBodyComponentsUseCustomFactories() throws {
        struct Payload: Codable, Equatable {
            let zeta: Int
            let alpha: Int
        }

        let encoder = JSONBodyEncoder {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return encoder
        }

        let payload = Payload(zeta: 1, alpha: 2)
        let encoded = try encoder.encode(payload)
        let decoder = JSONBodyDecoder { JSONDecoder() }

        #expect(String(decoding: encoded, as: UTF8.self) == #"{"alpha":2,"zeta":1}"#)
        #expect(try decoder.decode(Payload.self, from: encoded) == payload)
    }

    @Test func formURLEncodedBodyEncoderRejectsNestedArrays() {
        struct NestedPayload: Encodable {
            let matrix: [[String]]
        }

        #expect(throws: EncodingError.self) {
            _ = try FormURLEncodedBodyEncoder().encode(
                NestedPayload(matrix: [["a", "b"], ["c"]])
            )
        }
    }

    @Test func formURLEncodedBodyEncoderRejectsEmptyNestedArrays() {
        struct NestedPayload: Encodable {
            let matrix: [[String]]
        }

        #expect(throws: EncodingError.self) {
            _ = try FormURLEncodedBodyEncoder().encode(
                NestedPayload(matrix: [[]])
            )
        }
    }

    @Test func formURLEncodedBodyEncoderRejectsEmptyNestedKeyedValues() {
        struct EmptyValue: Encodable {}
        struct NestedPayload: Encodable {
            let nested: EmptyValue
        }

        #expect(throws: EncodingError.self) {
            _ = try FormURLEncodedBodyEncoder().encode(
                NestedPayload(nested: EmptyValue())
            )
        }
    }

    @Test func formURLEncodedBodyEncoderUsesHTMLFormPercentEncoding() throws {
        struct Payload: Encodable {
            let value: String
        }

        let data = try FormURLEncodedBodyEncoder().encode(Payload(value: "*~"))

        #expect(String(decoding: data, as: UTF8.self) == "value=*%7E")
    }

    @Test func formURLEncodedBodyEncoderRejectsNilArrayElements() {
        struct OptionalTagsPayload: Encodable {
            let tag: [String?]
        }

        #expect(throws: EncodingError.self) {
            _ = try FormURLEncodedBodyEncoder().encode(
                OptionalTagsPayload(tag: ["a", nil, "b"])
            )
        }
    }

    @Test func plainTextBodyDecoderRejectsInvalidUTF8ResponseBodies() {
        #expect(throws: DecodingError.self) {
            _ = try PlainTextBodyDecoder().decode(String.self, from: Data([0xFF, 0xFE]))
        }
    }

    @Test func plainTextBodyDecoderDecodesEmptyResponseBodies() throws {
        let decoded = try PlainTextBodyDecoder().decode(String.self, from: Data())

        #expect(decoded == "")
    }
#endif
