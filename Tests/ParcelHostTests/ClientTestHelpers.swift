#if !arch(wasm32)
  import BasicContainers
  import Foundation
  import HTTPAPIs
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
  struct GenerateRequest: Codable, Equatable, Sendable {
    let pagePath: String
  }

  /// Response fixture used by success-path decoding tests.
  struct GenerateAccepted: Codable, Equatable, Sendable {
    let statusURL: URL

    private enum CodingKeys: String, CodingKey {
      case statusURL = "statusUrl"
    }
  }

  /// Response fixture used to exercise custom date decoding.
  struct DatedAccepted: Decodable, Equatable, Sendable {
    let generatedAt: Date
  }

  /// Flat form fixture used to validate `FormURLEncodedBodyEncoder`.
  struct TokenExchangePayload: Codable, Equatable, Sendable {
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

  extension Client.Request where Output == GenerateAccepted {
    /// Typed operation fixture used to verify output inference and JSON request encoding.
    static func generate(
      _ body: GenerateRequest,
      headers: HTTPFields = [:]
    ) -> Self {
      .post(
        exampleGenerateURL,
        body: body,
        headers: headers
      )
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

  struct CannedResponse: Sendable {
    let response: HTTPResponse
    let body: Data
  }

  func fixtureResponse(
    statusCode: Int,
    headerFields: HTTPFields = [:],
    body: Data? = nil
  ) -> CannedResponse {
    CannedResponse(
      response: HTTPResponse(status: .init(code: statusCode), headerFields: headerFields),
      body: body ?? Data()
    )
  }

  actor RequestBodyStorage {
    private var bytes: [UInt8] = []

    func append(_ bytes: [UInt8]) {
      self.bytes.append(contentsOf: bytes)
    }

    func data() -> Data {
      Data(bytes)
    }
  }

  struct RecordingRequestBodyWriter: CallerAsyncWriter, ~Copyable {
    typealias WriteElement = UInt8
    typealias WriteFailure = any Error
    typealias FinalElement = HTTPFields?

    let storage: RequestBodyStorage

    mutating func write<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
      buffer: inout Buffer
    ) async throws where Buffer.Element: ~Copyable {
      await storage.append(consume(&buffer))
    }

    consuming func finish<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
      buffer: inout Buffer,
      finalElement: consuming HTTPFields?
    ) async throws where Buffer.Element: ~Copyable {
      await storage.append(consume(&buffer))
    }

    private func consume<Buffer: RangeReplaceableContainer<UInt8> & ~Copyable>(
      _ buffer: inout Buffer
    ) -> [UInt8] where Buffer.Element: ~Copyable {
      var bytes: [UInt8] = []
      var consumer = buffer.consumeAll()
      while let byte = consumer.next() {
        bytes.append(byte)
      }
      return bytes
    }
  }

  private actor ResponseBodyReadRecorder {
    private(set) var count = 0

    func recordRead() {
      count += 1
    }
  }

  struct CannedResponseBodyReader: AsyncReader, ~Copyable {
    typealias ReadElement = UInt8
    typealias ReadFailure = Never
    typealias Buffer = UniqueArray<UInt8>
    typealias FinalElement = HTTPFields?

    private var buffer: UniqueArray<UInt8>
    private var deliveredBody = false
    private let readRecorder: ResponseBodyReadRecorder

    fileprivate init(body: Data, readRecorder: ResponseBodyReadRecorder) {
      self.buffer = UniqueArray(copying: body)
      self.readRecorder = readRecorder
    }

    mutating func read<Return: ~Copyable, Failure: Error>(
      body:
        nonisolated(nonsending) (
          inout UniqueArray<UInt8>,
          consuming HTTPFields??
        ) async throws(Failure) -> Return
    ) async throws(EitherError<Never, Failure>) -> Return {
      await readRecorder.recordRead()

      let finalElement: HTTPFields??
      if deliveredBody || buffer.isEmpty {
        finalElement = .some(nil)
      } else {
        deliveredBody = true
        finalElement = nil
      }

      do {
        return try await body(&buffer, finalElement)
      } catch {
        throw .second(error)
      }
    }
  }

  private actor RequestRecorder {
    private(set) var lastRequest: HTTPRequest?
    private(set) var lastBody: Data?

    func record(request: HTTPRequest, body: Data?) {
      lastRequest = request
      lastBody = body
    }
  }

  /// HTTP client spy that captures the last request and drives the scoped response handler.
  final class RecordingHTTPClient: HTTPAPIs.HTTPClient, Sendable {
    struct RequestOptions: HTTPClientCapability.RequestOptions, Sendable {}

    typealias Writer = RecordingRequestBodyWriter
    typealias Reader = CannedResponseBodyReader

    let defaultRequestOptions = RequestOptions()
    private let recorder = RequestRecorder()
    private let response: CannedResponse
    private let responseBodyReadRecorder = ResponseBodyReadRecorder()

    var lastRequest: HTTPRequest? {
      get async { await recorder.lastRequest }
    }

    var lastBody: Data? {
      get async { await recorder.lastBody }
    }

    var responseBodyReadCount: Int {
      get async { await responseBodyReadRecorder.count }
    }

    init(response: CannedResponse) {
      self.response = response
    }

    func perform<Return: ~Copyable>(
      request: HTTPRequest,
      body: consuming HTTPClientRequestBody<RecordingRequestBodyWriter>?,
      options: RequestOptions,
      responseHandler:
        nonisolated(nonsending) (
          HTTPResponse,
          consuming CannedResponseBodyReader
        ) async throws -> Return
    ) async throws -> Return {
      let bodyData: Data?
      if let body {
        let storage = RequestBodyStorage()
        try await body.produce(into: RecordingRequestBodyWriter(storage: storage))
        bodyData = await storage.data()
      } else {
        bodyData = nil
      }
      await recorder.record(request: request, body: bodyData)

      return try await responseHandler(
        response.response,
        CannedResponseBodyReader(
          body: response.body,
          readRecorder: responseBodyReadRecorder
        )
      )
    }
  }

#endif
