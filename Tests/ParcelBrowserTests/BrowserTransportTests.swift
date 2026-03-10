#if arch(wasm32)
  import Foundation
  import JavaScriptEventLoopTestSupport
  import Testing

  @testable import Parcel

  @Suite(.serialized) struct BrowserTransportTestSuite {
    @Test func browserTransportIsSupportedByTheTestPrelude() throws {
      let harness = try BrowserTestHarness()

      try harness.reset()

      #expect(BrowserTransport.isSupportedRuntime)
    }

    @Test func browserTransportIsSupportedInWorkerScope() throws {
      let harness = try BrowserTestHarness()

      try harness.reset()
      try harness.configureRuntimeScope(.worker)

      #expect(BrowserTransport.isSupportedRuntime)
    }

    @Test func browserTransportSendReadsResponseMetadataAndBytes() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 202,
        headers: ["etag": "abc123"],
        url: "https://example.com/status",
        bodyText: "accepted"
      )

      let response = try await transport.send(
        HTTPRequest(
          method: .post,
          url: "https://example.com/generate",
          headers: [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Trace": "123",
          ],
          body: Data(#"{"pagePath":"/posts/example"}"#.utf8)
        )
      )
      let request = try #require(harness.recordedRequests().first)

      #expect(response.statusCode == 202)
      #expect(response.headers["etag"] == "abc123")
      #expect(response.url == "https://example.com/status")
      #expect(String(data: try #require(response.body), encoding: .utf8) == "accepted")
      #expect(request.method == "POST")
      #expect(request.url == "https://example.com/generate")
      #expect(request.headers["Accept"] == "application/json")
      #expect(request.headers["Content-Type"] == "application/json")
      #expect(request.headers["X-Trace"] == "123")
      #expect(request.bodyText == #"{"pagePath":"/posts/example"}"#)
    }

    @Test func browserTransportTypedSendDecodesJSONResponses() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        headers: ["content-type": "application/json"],
        url: "https://example.com/status",
        jsonBody: #"{"statusUrl":"https://example.com/status"}"#
      )

      let accepted = try await transport.sendResponse(
        HTTPRequest(method: .get, url: "https://example.com/status"),
        expecting: GenerateAccepted.self
      )

      #expect(accepted.value == GenerateAccepted(statusURL: "https://example.com/status"))
      #expect(accepted.response.statusCode == 200)
      #expect(accepted.response.headers["content-type"] == "application/json")
      #expect(accepted.response.url == "https://example.com/status")
    }

    @Test func browserTransportTypedSendPreservesJSONPromiseFailures() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        headers: ["content-type": "application/json"],
        bodyText: "not-json"
      )

      do {
        let _: DecodedResponse<GenerateAccepted> = try await transport.sendResponse(
          HTTPRequest(method: .get, url: "https://example.com/status"),
          expecting: GenerateAccepted.self
        )
        Issue.record("Expected request to throw")
      } catch let error as ClientError {
        guard case .responseBodyFailure(let failure) = error else {
          Issue.record("Expected response body failure, got \(error)")
          return
        }

        #expect(failure.operation == .json)
        #expect(failure.javaScriptError.name == "SyntaxError")
        #expect(failure.javaScriptError.message != nil)
      }
    }

    @Test func browserTransportSendCancelsBodyReads() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        bodyText: "accepted",
        behavior: .init(arrayBufferDelayMilliseconds: 500)
      )

      let task = Task {
        try await transport.send(
          HTTPRequest(method: .get, url: "https://example.com/status")
        )
      }

      for _ in 0..<20 {
        if try harness.recordedRequests().isEmpty == false {
          break
        }
        await Task.yield()
      }
      task.cancel()

      do {
        _ = try await task.value
        Issue.record("Expected request to be cancelled")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected cancellation, got \(error)")
      }

      let request = try #require(harness.recordedRequests().first)
      #expect(request.aborted)
    }

    @Test func browserTransportTypedSendTurnsFailingStatusesIntoClientErrors() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 503,
        url: "https://example.com/status",
        bodyText: "unavailable"
      )

      do {
        let _: DecodedResponse<GenerateAccepted> = try await transport.sendResponse(
          HTTPRequest(method: .get, url: "https://example.com/status"),
          expecting: GenerateAccepted.self
        )
        Issue.record("Expected request to throw")
      } catch let error as ClientError {
        #expect(error == .unsuccessfulStatusCode(503, body: "unavailable"))
      }
    }
  }
#endif
