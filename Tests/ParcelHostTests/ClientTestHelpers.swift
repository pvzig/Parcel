#if !arch(wasm32)
  import Foundation
  import HTTPTypes

  @testable import Parcel

  extension HTTPField.Name {
    static let xClient = Self("X-Client")!
    static let xTrace = Self("X-Trace")!
  }

  func fixtureURL(_ string: String) -> URL {
    guard let url = URL(string: string) else {
      preconditionFailure("Invalid fixture URL: \(string)")
    }

    return url
  }

  let exampleGenerateURL = fixtureURL("https://example.com/generate")
  let exampleStatusURL = fixtureURL("https://example.com/status")

  /// Request fixture used to verify JSON request encoding.
  struct GenerateRequest: Codable, Equatable {
    let pagePath: String
  }

  /// Response fixture used by success-path decoding tests.
  struct GenerateAccepted: Codable, Equatable {
    let statusURL: URL

    private enum CodingKeys: String, CodingKey {
      case statusURL = "statusUrl"
    }
  }

  /// Response fixture used to exercise custom date decoding.
  struct DatedAccepted: Decodable, Equatable {
    let generatedAt: Date
  }

  /// Flat form fixture used to validate `FormURLEncodedBodyCodec`.
  struct TokenExchangePayload: Codable, Equatable {
    let grantType: String
    let scope: String
    let expiresIn: Int
    let active: Bool
    let tags: [String]

    private enum CodingKeys: String, CodingKey {
      case grantType = "grant_type"
      case scope
      case expiresIn = "expires_in"
      case active
      case tags = "tag"
    }
  }

  func decodeFormFields(_ data: Data) -> [String: [String]] {
    guard let body = String(data: data, encoding: .utf8) else {
      preconditionFailure("Expected UTF-8 form body")
    }

    guard body.isEmpty == false else {
      return [:]
    }

    var values: [String: [String]] = [:]

    for pair in body.split(separator: "&", omittingEmptySubsequences: false) {
      let segments = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let name = decodeFormComponent(String(segments[0]))
      let value = decodeFormComponent(segments.count == 2 ? String(segments[1]) : "")
      values[name, default: []].append(value)
    }

    return values
  }

  private func decodeFormComponent(_ component: String) -> String {
    let bytes = Array(component.utf8)
    var decodedBytes: [UInt8] = []
    decodedBytes.reserveCapacity(bytes.count)

    var index = 0
    while index < bytes.count {
      switch bytes[index] {
      case 0x2B:
        decodedBytes.append(0x20)
        index += 1
      case 0x25:
        guard
          index + 2 < bytes.count,
          let upper = decodeHexDigit(bytes[index + 1]),
          let lower = decodeHexDigit(bytes[index + 2])
        else {
          preconditionFailure("Invalid percent-encoded form component")
        }

        decodedBytes.append((upper << 4) | lower)
        index += 3
      default:
        decodedBytes.append(bytes[index])
        index += 1
      }
    }

    guard let decoded = String(bytes: decodedBytes, encoding: .utf8) else {
      preconditionFailure("Decoded form component was not valid UTF-8")
    }

    return decoded
  }

  private func decodeHexDigit(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 0x30...0x39:
      byte - 48
    case 0x41...0x46:
      byte - 55
    case 0x61...0x66:
      byte - 87
    default:
      nil
    }
  }

  func fixtureResponse(
    statusCode: Int,
    headerFields: HTTPFields = [:],
    url: URL? = nil,
    body: Data? = nil
  ) -> (response: HTTPResponse, body: Data?, url: URL?) {
    (
      response: HTTPResponse(status: .init(code: statusCode), headerFields: headerFields),
      body: body,
      url: url
    )
  }

  /// Transport spy that captures the last request and returns a canned response.
  actor RecordingTransport: Transport {
    private(set) var lastRequest: HTTPRequest?
    private(set) var lastBody: Data?

    let response: (response: HTTPResponse, body: Data?, url: URL?)

    init(response: (response: HTTPResponse, body: Data?, url: URL?)) {
      self.response = response
    }

    func send(
      _ request: HTTPRequest,
      body: Data?,
      timeout: Duration?
    ) async throws -> (response: HTTPResponse, body: Data?, url: URL?) {
      lastRequest = request
      lastBody = body
      return response
    }
  }

#endif
