#if arch(wasm32)
  import Foundation
  @preconcurrency import JavaScriptKit

  /// Response fixture used by browser transport decoding tests.
  struct GenerateAccepted: Codable, Equatable {
    let statusURL: String

    private enum CodingKeys: String, CodingKey {
      case statusURL = "statusUrl"
    }
  }

  /// Captured request data returned by the JavaScript fetch prelude.
  struct RecordedBrowserRequest: Decodable, Equatable {
    let url: String
    let method: String
    let headers: [String: String]
    let bodyText: String?
    let mode: String?
    let credentials: String?
    let cache: String?
    let aborted: Bool
  }

  /// Errors thrown when the JavaScript test harness is unavailable or malformed.
  enum BrowserTestHarnessError: Error {
    case missingHarness
    case missingFunction(String)
    case invalidRecordedRequests
  }

  /// Bridge to the JavaScript prelude that configures mocked fetch responses.
  struct BrowserTestHarness {
    enum RuntimeScope: String, Sendable {
      case window
      case worker
    }

    struct ResponseBehavior: Codable, Sendable {
      let fetchDelayMilliseconds: Int?
      let fetchErrorName: String?
      let fetchErrorMessage: String?
      let arrayBufferDelayMilliseconds: Int?
      let arrayBufferErrorName: String?
      let arrayBufferErrorMessage: String?
      let jsonDelayMilliseconds: Int?
      let jsonErrorName: String?
      let jsonErrorMessage: String?
      let textDelayMilliseconds: Int?
      let textErrorName: String?
      let textErrorMessage: String?

      init(
        fetchDelayMilliseconds: Int? = nil,
        fetchErrorName: String? = nil,
        fetchErrorMessage: String? = nil,
        arrayBufferDelayMilliseconds: Int? = nil,
        arrayBufferErrorName: String? = nil,
        arrayBufferErrorMessage: String? = nil,
        jsonDelayMilliseconds: Int? = nil,
        jsonErrorName: String? = nil,
        jsonErrorMessage: String? = nil,
        textDelayMilliseconds: Int? = nil,
        textErrorName: String? = nil,
        textErrorMessage: String? = nil
      ) {
        self.fetchDelayMilliseconds = fetchDelayMilliseconds
        self.fetchErrorName = fetchErrorName
        self.fetchErrorMessage = fetchErrorMessage
        self.arrayBufferDelayMilliseconds = arrayBufferDelayMilliseconds
        self.arrayBufferErrorName = arrayBufferErrorName
        self.arrayBufferErrorMessage = arrayBufferErrorMessage
        self.jsonDelayMilliseconds = jsonDelayMilliseconds
        self.jsonErrorName = jsonErrorName
        self.jsonErrorMessage = jsonErrorMessage
        self.textDelayMilliseconds = textDelayMilliseconds
        self.textErrorName = textErrorName
        self.textErrorMessage = textErrorMessage
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

    func configureResponse(
      statusCode: Int,
      headers: [String: String] = [:],
      url: String? = nil,
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
        url.map(JSValue.string) ?? JSValue.null,
        JSValue.string(headersJSON),
        bodyText.map(JSValue.string) ?? JSValue.null,
        jsonBody.map(JSValue.string) ?? JSValue.null,
        JSValue.string(behaviorJSON)
      )
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
#endif
