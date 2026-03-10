#if !arch(wasm32)
  import Foundation

  @testable import Parcel

  /// Request fixture used to verify JSON request encoding.
  struct GenerateRequest: Codable, Equatable {
    let pagePath: String
  }

  /// Response fixture used by success-path decoding tests.
  struct GenerateAccepted: Codable, Equatable {
    let statusURL: String

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

  /// Transport stub that tracks whether the raw or typed send path was used.
  struct ResponseDecodingRecordingTransport: ResponseDecodingTransport {
    private let state = ResponseDecodingTransportState()
    let response: HTTPResponse

    init(response: HTTPResponse = HTTPResponse(statusCode: 204)) {
      self.response = response
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
      await state.recordRawSend()
      return response
    }

    func sendResponse<Response: Decodable>(
      _ request: HTTPRequest,
      expecting responseType: Response.Type
    ) async throws -> DecodedResponse<Response> {
      await state.recordTypedSend()

      if let response = GenerateAccepted(statusURL: "https://example.com/status") as? Response {
        return DecodedResponse(
          value: response,
          response: HTTPResponse(statusCode: 200)
        )
      }

      throw TestError.unsupportedResponseType
    }

    func counts() async -> (rawSendCount: Int, typedSendCount: Int) {
      await state.snapshot()
    }
  }

  /// Test-only error values returned by helper transports.
  enum TestError: Error {
    case unsupportedResponseType
  }

  /// Actor-backed mutable state for response-decoding transport call counts.
  actor ResponseDecodingTransportState {
    private var rawSendCount = 0
    private var typedSendCount = 0

    func recordRawSend() {
      rawSendCount += 1
    }

    func recordTypedSend() {
      typedSendCount += 1
    }

    func snapshot() -> (rawSendCount: Int, typedSendCount: Int) {
      (rawSendCount, typedSendCount)
    }
  }
#endif
