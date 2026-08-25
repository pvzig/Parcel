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

  /// Parses form bodies independently from the production codec for wire-format assertions.
  func decodeFormFields(_ data: Data) throws -> [String: [String]] {
    guard let body = String(data: data, encoding: .utf8) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Expected a UTF-8 form body.")
      )
    }

    guard body.isEmpty == false else {
      return [:]
    }

    var values: [String: [String]] = [:]
    for pair in body.split(separator: "&", omittingEmptySubsequences: false) {
      let segments = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let name = try decodeFormComponent(String(segments[0]))
      let value = try decodeFormComponent(segments.count == 2 ? String(segments[1]) : "")
      values[name, default: []].append(value)
    }
    return values
  }

  private func decodeFormComponent(_ component: String) throws -> String {
    let percentEncoded = component.replacing("+", with: "%20")
    guard let decoded = percentEncoded.removingPercentEncoding else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: [], debugDescription: "Invalid percent-encoded form component.")
      )
    }
    return decoded
  }

  func fixtureResponse(
    statusCode: Int,
    headerFields: HTTPFields = [:],
    url: URL? = nil,
    body: Data? = nil
  ) -> TransportResponse {
    TransportResponse(
      response: HTTPResponse(status: .init(code: statusCode), headerFields: headerFields),
      body: body.map(HTTPBody.init),
      url: url
    )
  }

  /// Transport spy that captures the last request and returns a canned response.
  actor RecordingTransport: Transport {
    private(set) var lastRequest: HTTPRequest?
    private(set) var lastBody: Data?
    private(set) var lastTimeout: Duration?

    let response: TransportResponse

    init(response: TransportResponse) {
      self.response = response
    }

    func send(
      _ request: HTTPRequest,
      body: HTTPBody?,
      timeout: Duration?
    ) async throws -> TransportResponse {
      lastRequest = request
      lastBody = try await body?.collect()
      lastTimeout = timeout
      return response
    }
  }

#endif
