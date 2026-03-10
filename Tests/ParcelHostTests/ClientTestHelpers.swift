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
