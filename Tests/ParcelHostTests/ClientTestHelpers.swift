#if !arch(wasm32)
  import Foundation

  @testable import Parcel

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

  /// Transport spy that captures the last request and returns a canned response.
  actor RecordingTransport: Transport {
    private(set) var lastRequest: HTTPRequest?

    let response: HTTPResponse

    init(response: HTTPResponse) {
      self.response = response
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
      lastRequest = request
      return response
    }
  }

#endif
