#if !arch(wasm32)
  import Foundation
  import Testing

  @testable import Parcel

  /// Codec fixture with no declared media types, used to verify header defaults.
  private struct OpaqueCodec: BodyCodec {
    var defaultRequestContentType: String? { nil }
    var defaultAccept: [String] { [] }

    func encode<Request: Encodable>(_ value: Request) throws -> Data {
      Data()
    }

    func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "OpaqueCodec cannot decode.")
      )
    }
  }

  @Test func directCodecConstructionUsesBodyCodecMediaTypeDefaults() {
    let json = Client.Codec(bodyCodec: JSONBodyCodec())
    #expect(json.requestContentType == "application/json")
    #expect(json.accept == ["application/json"])

    let form = Client.Codec(bodyCodec: FormURLEncodedBodyCodec())
    #expect(form.requestContentType == "application/x-www-form-urlencoded")

    let custom = Client.Codec(
      bodyCodec: JSONBodyCodec(),
      requestContentType: "application/vnd.parcel+json",
      accept: ["application/vnd.parcel+json"]
    )
    #expect(custom.requestContentType == "application/vnd.parcel+json")
    #expect(custom.accept == ["application/vnd.parcel+json"])
  }

  @Test func codecsWithoutDeclaredMediaTypesApplyNoHeaderDefaults() {
    let codec = Client.Codec(bodyCodec: OpaqueCodec())

    #expect(codec.requestContentType == nil)
    #expect(codec.accept == [])
  }

  @Test func explicitCodecMediaTypesCanSuppressBodyCodecDefaults() {
    let codec = Client.Codec(
      bodyCodec: JSONBodyCodec(),
      requestContentType: nil,
      accept: []
    )

    #expect(codec.requestContentType == nil)
    #expect(codec.accept == [])
  }

  @Test func jsonCodecFactoriesRemainMutableAndRunPerOperation() throws {
    struct Payload: Codable, Equatable {
      let zeta: Int
      let alpha: Int
    }

    var codec = JSONBodyCodec()
    codec.makeEncoder = {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      return encoder
    }

    let payload = Payload(zeta: 1, alpha: 2)
    let first = try codec.encode(payload)
    codec.makeEncoder = { JSONEncoder() }
    let second = try codec.encode(payload)

    #expect(String(decoding: first, as: UTF8.self) == #"{"alpha":2,"zeta":1}"#)
    #expect(try codec.decode(Payload.self, from: second) == payload)
  }

  @Test func formURLEncodedCodecRoundTripsEmptyArrays() throws {
    let codec = FormURLEncodedBodyCodec()
    let payload = TokenExchangePayload(
      grantType: "client_credentials",
      scope: "read write",
      expiresIn: 3600,
      active: true,
      tags: []
    )

    let body = try codec.encode(payload)
    let decoded = try codec.decode(TokenExchangePayload.self, from: body)

    #expect(decoded == payload)
  }

  @Test func formURLEncodedCodecDoesNotSynthesizeMissingCustomValues() {
    struct DecoderIgnoringValue: Decodable {
      init(from decoder: any Decoder) throws {}
    }
    struct Payload: Decodable {
      let required: DecoderIgnoringValue
    }

    do {
      _ = try FormURLEncodedBodyCodec().decode(Payload.self, from: Data())
      Issue.record("Expected a missing required value to throw.")
    } catch DecodingError.keyNotFound(let key, _) {
      #expect(key.stringValue == "required")
    } catch {
      Issue.record("Expected keyNotFound, got \(error).")
    }
  }

  @Test func formURLEncodedCodecRejectsNestedArraysOnEncode() {
    struct NestedPayload: Encodable {
      let matrix: [[String]]
    }

    #expect(throws: EncodingError.self) {
      _ = try FormURLEncodedBodyCodec().encode(
        NestedPayload(matrix: [["a", "b"], ["c"]])
      )
    }
  }

  @Test func formURLEncodedCodecRejectsEmptyNestedArraysOnEncode() {
    struct NestedPayload: Encodable {
      let matrix: [[String]]
    }

    #expect(throws: EncodingError.self) {
      _ = try FormURLEncodedBodyCodec().encode(
        NestedPayload(matrix: [[]])
      )
    }
  }

  @Test func formURLEncodedCodecRejectsEmptyNestedKeyedValuesOnEncode() {
    struct EmptyValue: Encodable {}
    struct NestedPayload: Encodable {
      let nested: EmptyValue
    }

    #expect(throws: EncodingError.self) {
      _ = try FormURLEncodedBodyCodec().encode(
        NestedPayload(nested: EmptyValue())
      )
    }
  }

  @Test func formURLEncodedCodecUsesHTMLFormPercentEncoding() throws {
    struct Payload: Encodable {
      let value: String
    }

    let data = try FormURLEncodedBodyCodec().encode(Payload(value: "*~"))

    #expect(String(decoding: data, as: UTF8.self) == "value=*%7E")
  }

  @Test func formURLEncodedCodecRejectsNilArrayElementsOnEncode() {
    struct OptionalTagsPayload: Encodable {
      let tag: [String?]
    }

    #expect(throws: EncodingError.self) {
      _ = try FormURLEncodedBodyCodec().encode(
        OptionalTagsPayload(tag: ["a", nil, "b"])
      )
    }
  }

  @Test func formURLEncodedCodecIgnoresEmptyFieldSequences() throws {
    struct Payload: Decodable, Equatable {
      let a: String
      let b: String
    }

    let codec = FormURLEncodedBodyCodec()
    let decoded = try codec.decode(Payload.self, from: Data("a=1&&b=2&".utf8))

    #expect(decoded == Payload(a: "1", b: "2"))
  }

  @Test func plainTextCodecRejectsInvalidUTF8ResponseBodies() {
    #expect(throws: DecodingError.self) {
      _ = try PlainTextBodyCodec().decode(String.self, from: Data([0xFF, 0xFE]))
    }
  }

  @Test func plainTextCodecDecodesEmptyResponseBodies() throws {
    let decoded = try PlainTextBodyCodec().decode(String.self, from: Data())

    #expect(decoded == "")
  }
#endif
