#if arch(wasm32)
  import Foundation
  import HTTPTypes
  import JavaScriptKit

  @testable import Parcel

  extension HTTPField.Name {
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

  struct GenerateRequest: Codable, Equatable, Sendable {
    let pagePath: String
  }

  struct GenerateAccepted: Codable, Equatable, Sendable {
    let statusURL: URL

    private enum CodingKeys: String, CodingKey {
      case statusURL = "statusUrl"
    }
  }

  struct RecordedBrowserRequest: Decodable, Equatable {
    let url: URL
    let method: String
    let headers: [String: String]
    let bodyText: String?
  }

  enum BrowserTestHarnessError: Error {
    case invalidRecordedRequests
    case missingFunction(String)
    case missingHarness
  }

  struct BrowserTestHarness {
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

    func configureResponse(
      statusCode: Int,
      headers: [String: String] = [:],
      bodyText: String = ""
    ) throws {
      guard
        let configureResponse =
          api.configureResponse as ((any ConvertibleToJSValue...) -> JSValue)?
      else {
        throw BrowserTestHarnessError.missingFunction("configureResponse")
      }

      let headersData = try JSONEncoder().encode(headers)
      let headersJSON = String(decoding: headersData, as: UTF8.self)

      _ = configureResponse(
        JSValue.number(Double(statusCode)),
        JSValue.string(headersJSON),
        JSValue.string(bodyText)
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
