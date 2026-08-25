#if arch(wasm32)
  import Foundation
  import HTTPTypes
  import JavaScriptEventLoop
  @preconcurrency import JavaScriptKit

  @testable import Parcel

  extension HTTPField.Name {
    static let xBinary = Self("X-Binary")!
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

  /// Response fixture used by browser transport decoding tests.
  struct GenerateAccepted: Codable, Equatable {
    let statusURL: URL

    private enum CodingKeys: String, CodingKey {
      case statusURL = "statusUrl"
    }
  }

  /// Captured request data returned by the JavaScript fetch prelude.
  struct RecordedBrowserRequest: Decodable, Equatable {
    let url: URL
    let method: String
    let headers: [String: String]
    let bodyText: String?
    let mode: String?
    let credentials: String?
    let cache: String?
    let redirect: String?
    let aborted: Bool
    let bodyReadStarted: Bool
    let bodyCancelled: Bool
    let readerReleased: Bool
  }

  actor BrowserTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
      guard isOpen == false else {
        return
      }

      await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
    }

    func open() {
      isOpen = true
      let waiters = waiters
      self.waiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
    }
  }

  struct NoncooperativeGatedBodySequence: AsyncSequence, Sendable {
    typealias Element = [UInt8]

    struct AsyncIterator: AsyncIteratorProtocol {
      let gate: BrowserTestGate
      var emitted = false

      mutating func next() async -> [UInt8]? {
        guard emitted == false else {
          return nil
        }

        await gate.wait()
        emitted = true
        return [0x61]
      }
    }

    let gate: BrowserTestGate

    func makeAsyncIterator() -> AsyncIterator {
      .init(gate: gate)
    }
  }

  /// Errors thrown when the JavaScript test harness is unavailable or malformed.
  enum BrowserTestHarnessError: Error {
    case missingHarness
    case missingFunction(String)
    case invalidPromise(String)
    case invalidRecordedRequests
  }

  /// Bridge to the JavaScript prelude that configures mocked fetch responses.
  struct BrowserTestHarness {
    enum RequestState: String, Sendable {
      case bodyCancelled
      case bodyReadStarted
      case readerReleased
    }

    enum RuntimeScope: String, Sendable {
      case window
      case worker
    }

    struct ResponseBehavior: Codable, Sendable {
      let fetchDelayMilliseconds: Int?
      let fetchErrorName: String?
      let fetchErrorMessage: String?
      let bodyReadDelayMilliseconds: Int?
      let bodyReadErrorName: String?
      let bodyReadErrorMessage: String?
      let cancelErrorName: String?
      let cancelErrorMessage: String?
      let omitResponseStatus: Bool?
      let invalidBodyChunk: Bool?

      init(
        fetchDelayMilliseconds: Int? = nil,
        fetchErrorName: String? = nil,
        fetchErrorMessage: String? = nil,
        bodyReadDelayMilliseconds: Int? = nil,
        bodyReadErrorName: String? = nil,
        bodyReadErrorMessage: String? = nil,
        cancelErrorName: String? = nil,
        cancelErrorMessage: String? = nil,
        omitResponseStatus: Bool? = nil,
        invalidBodyChunk: Bool? = nil
      ) {
        self.fetchDelayMilliseconds = fetchDelayMilliseconds
        self.fetchErrorName = fetchErrorName
        self.fetchErrorMessage = fetchErrorMessage
        self.bodyReadDelayMilliseconds = bodyReadDelayMilliseconds
        self.bodyReadErrorName = bodyReadErrorName
        self.bodyReadErrorMessage = bodyReadErrorMessage
        self.cancelErrorName = cancelErrorName
        self.cancelErrorMessage = cancelErrorMessage
        self.omitResponseStatus = omitResponseStatus
        self.invalidBodyChunk = invalidBodyChunk
      }
    }

    private let api: JSObject

    init() throws {
      guard let api = JSObject.global["__parcelTest"].object else {
        throw BrowserTestHarnessError.missingHarness
      }
      self.api = api
    }

    func reset() throws {
      guard let reset = api.reset as ((any ConvertibleToJSValue...) -> JSValue)? else {
        throw BrowserTestHarnessError.missingFunction("reset")
      }

      _ = reset()
    }

    func configureRuntimeScope(_ scope: RuntimeScope) throws {
      guard
        let configureRuntimeScope =
          api.configureRuntimeScope as ((any ConvertibleToJSValue...) -> JSValue)?
      else {
        throw BrowserTestHarnessError.missingFunction("configureRuntimeScope")
      }

      _ = configureRuntimeScope(scope.rawValue)
    }

    func removeFetch() throws {
      guard let removeFetch = api.removeFetch as ((any ConvertibleToJSValue...) -> JSValue)? else {
        throw BrowserTestHarnessError.missingFunction("removeFetch")
      }

      _ = removeFetch()
    }

    func removeClearTimeout() throws {
      guard
        let removeClearTimeout =
          api.removeClearTimeout as ((any ConvertibleToJSValue...) -> JSValue)?
      else {
        throw BrowserTestHarnessError.missingFunction("removeClearTimeout")
      }

      _ = removeClearTimeout()
    }

    func configureResponse(
      statusCode: Int,
      headers: [String: String] = [:],
      url: URL? = nil,
      bodyText: String? = nil,
      jsonBody: String? = nil,
      behavior: ResponseBehavior = .init()
    ) throws {
      guard
        let configureResponse =
          api.configureResponse as ((any ConvertibleToJSValue...) -> JSValue)?
      else {
        throw BrowserTestHarnessError.missingFunction("configureResponse")
      }

      let headersData = try JSONEncoder().encode(headers)
      let headersJSON = String(decoding: headersData, as: UTF8.self)
      let behaviorData = try JSONEncoder().encode(behavior)
      let behaviorJSON = String(decoding: behaviorData, as: UTF8.self)

      _ = configureResponse(
        JSValue.number(Double(statusCode)),
        url.map { JSValue.string($0.absoluteString) } ?? JSValue.null,
        JSValue.string(headersJSON),
        bodyText.map(JSValue.string) ?? JSValue.null,
        jsonBody.map(JSValue.string) ?? JSValue.null,
        JSValue.string(behaviorJSON)
      )
    }

    func waitForRequestState(
      _ state: RequestState,
      requestIndex: Int = 0,
      isolation: isolated (any Actor)? = #isolation
    ) async throws {
      guard
        let waitForRequestState =
          api.waitForRequestState as ((any ConvertibleToJSValue...) -> JSValue)?
      else {
        throw BrowserTestHarnessError.missingFunction("waitForRequestState")
      }

      guard
        let promiseObject = waitForRequestState(requestIndex, state.rawValue).object,
        let promise = JSPromise(promiseObject)
      else {
        throw BrowserTestHarnessError.invalidPromise("waitForRequestState")
      }

      _ = try await promise.value(isolation: isolation)
    }

    func recordedRequests() throws -> [RecordedBrowserRequest] {
      guard
        let recordedRequestsJSON =
          api.recordedRequestsJSON as ((any ConvertibleToJSValue...) -> JSValue)?,
        let json = recordedRequestsJSON().string
      else {
        throw BrowserTestHarnessError.invalidRecordedRequests
      }

      return try JSONDecoder().decode(
        [RecordedBrowserRequest].self,
        from: Data(json.utf8)
      )
    }
  }

  func collectBodyData(_ body: HTTPBody?) async throws -> Data? {
    try await body?.collect()
  }

  func collectBodyText(_ body: HTTPBody?) async throws -> String? {
    guard let data = try await collectBodyData(body) else {
      return nil
    }

    return String(decoding: data, as: UTF8.self)
  }
#endif
