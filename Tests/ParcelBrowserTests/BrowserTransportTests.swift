#if arch(wasm32)
  import Foundation
  import HTTPTypes
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
        url: exampleStatusURL,
        bodyText: "accepted"
      )

      let request = HTTPRequest(
        method: .post,
        url: exampleGenerateURL,
        headerFields: [
          HTTPField.Name.accept: "application/json",
          HTTPField.Name.contentType: "application/json",
          HTTPField.Name.xTrace: "123",
        ]
      )
      let response = try await transport.send(
        request,
        body: HTTPBody(Data(#"{"pagePath":"/posts/example"}"#.utf8)),
        timeout: nil
      )
      let recordedRequest = try #require(harness.recordedRequests().first)

      #expect(response.response.status.code == 202)
      #expect(response.response.headerFields[HTTPField.Name.eTag] == "abc123")
      #expect(response.url == exampleStatusURL)
      #expect(try await collectBodyText(response.body) == "accepted")
      #expect(recordedRequest.method == "POST")
      #expect(recordedRequest.url == exampleGenerateURL)
      #expect(recordedRequest.headers["Accept"] == "application/json")
      #expect(recordedRequest.headers["Content-Type"] == "application/json")
      #expect(recordedRequest.headers["X-Trace"] == "123")
      #expect(recordedRequest.bodyText == #"{"pagePath":"/posts/example"}"#)
    }

    @Test func browserTransportHonorsMaximumBufferedRequestBodyBytes() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport(maximumBufferedRequestBodyBytes: 4)

      try harness.reset()
      try harness.configureResponse(statusCode: 204)

      do {
        _ = try await transport.send(
          HTTPRequest(method: .post, url: exampleGenerateURL),
          body: HTTPBody("hello"),
          timeout: nil
        )
        Issue.record("Expected request buffering to enforce the configured byte limit")
      } catch let error as HTTPBody.TooManyBytesError {
        #expect(error == .init(maxBytes: 4))
      }

      #expect(try harness.recordedRequests().isEmpty)
    }

    @Test func clientDecodePathOverBrowserTransportDecodesJSONResponses() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let client = Client(transport: transport)

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        headers: ["content-type": "application/json"],
        url: exampleStatusURL,
        jsonBody: #"{"statusUrl":"https://example.com/status"}"#
      )

      let accepted = try await client.sendResponse(
        HTTPRequest(method: .get, url: exampleStatusURL),
        expecting: GenerateAccepted.self
      )

      #expect(accepted.value == GenerateAccepted(statusURL: exampleStatusURL))
      #expect(accepted.response.status.code == 200)
      #expect(accepted.response.headerFields[HTTPField.Name.contentType] == "application/json")
      #expect(accepted.url == exampleStatusURL)
    }

    @Test func clientDecodePathOverBrowserTransportUsesConfiguredBodyCodec() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let client = Client(
        configuration: ClientConfiguration(
          bodyCoding: .plainText()
        ),
        transport: transport
      )

      try harness.reset()
      try harness.configureResponse(
        statusCode: 202,
        headers: ["content-type": "text/plain"],
        url: exampleStatusURL,
        bodyText: "accepted"
      )

      let accepted: String = try await client.post(
        "publish",
        to: exampleGenerateURL
      )
      let recordedRequest = try #require(harness.recordedRequests().first)

      #expect(accepted == "accepted")
      #expect(recordedRequest.headers["Accept"] == "text/plain")
      #expect(recordedRequest.headers["Content-Type"] == "text/plain")
      #expect(recordedRequest.bodyText == "publish")
    }

    @Test func browserTransportPreservesDuplicateOutgoingHeadersSemantically() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let client = Client(
        configuration: ClientConfiguration(
          defaultHeaders: [HTTPField.Name.accept: "application/vnd.parcel+json"]
        ),
        transport: transport
      )

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        headers: ["content-type": "application/json"],
        url: exampleStatusURL,
        jsonBody: #"{"statusUrl":"https://example.com/status"}"#
      )

      let _: GenerateAccepted = try await client.get(
        from: exampleStatusURL,
        headers: [.accept: "application/json"]
      )
      let recordedRequest = try #require(harness.recordedRequests().first)

      #expect(
        recordedRequest.headers["Accept"]
          == "application/vnd.parcel+json, application/json"
      )
    }

    @Test func clientDecodePathOverBrowserTransportUsesJSONDecoderForInvalidJSONPayloads()
      async throws
    {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let client = Client(transport: transport)

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        headers: ["content-type": "application/json"],
        bodyText: "not-json"
      )

      do {
        let _: DecodedResponse<GenerateAccepted> = try await client.sendResponse(
          HTTPRequest(method: .get, url: exampleStatusURL),
          expecting: GenerateAccepted.self
        )
        Issue.record("Expected request to throw")
      } catch is DecodingError {
      } catch {
        Issue.record("Expected decoding error, got \(error)")
      }
    }

    @Test func clientDecodePathOverBrowserTransportPreservesMissingErrorBodiesAsNil()
      async throws
    {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let client = Client(transport: transport)

      try harness.reset()
      try harness.configureResponse(statusCode: 503)

      do {
        let _: DecodedResponse<GenerateAccepted> = try await client.sendResponse(
          HTTPRequest(method: .get, url: exampleStatusURL),
          expecting: GenerateAccepted.self
        )
        Issue.record("Expected request to throw")
      } catch let error as ClientError {
        #expect(error == .unsuccessfulStatusCode(503, body: nil))
      }
    }

    @Test func clientDecodePathOverBrowserTransportThrowsEmptyResponseBodyForEmptySuccessBody()
      async throws
    {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let client = Client(transport: transport)

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        headers: ["content-type": "application/json"]
      )

      do {
        let _: DecodedResponse<GenerateAccepted> = try await client.sendResponse(
          HTTPRequest(method: .get, url: exampleStatusURL),
          expecting: GenerateAccepted.self
        )
        Issue.record("Expected request to throw")
      } catch let error as ClientError {
        #expect(error == .emptyResponseBody)
      }
    }

    @Test func clientDecodePathOverBrowserTransportReturnsEmptyResponseForEmptySuccessBody()
      async throws
    {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let client = Client(transport: transport)

      try harness.reset()
      try harness.configureResponse(statusCode: 204)

      let response = try await client.sendResponse(
        HTTPRequest(method: .delete, url: exampleStatusURL),
        expecting: EmptyResponse.self
      )

      #expect(response.value == EmptyResponse())
    }

    @Test func clientDecodePathOverBrowserTransportValidatesNonJSONPayloadForEmptyResponse()
      async throws
    {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let client = Client(transport: transport)

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        bodyText: "accepted"
      )

      do {
        let _: DecodedResponse<EmptyResponse> = try await client.sendResponse(
          HTTPRequest(method: .get, url: exampleStatusURL),
          expecting: EmptyResponse.self
        )
        Issue.record("Expected request to throw")
      } catch is DecodingError {
      } catch {
        Issue.record("Expected decoding error, got \(error)")
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

      let response = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )
      let task = Task {
        try await collectBodyData(response.body)
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

    @Test func browserTransportCancelsAbandonedResponseBodies() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        bodyText: "accepted",
        behavior: .init(arrayBufferDelayMilliseconds: 500)
      )

      do {
        let response = try await transport.send(
          HTTPRequest(method: .get, url: exampleStatusURL),
          body: nil,
          timeout: nil
        )
        #expect(response.body != nil)
      }

      for _ in 0..<20 {
        if let request = try harness.recordedRequests().first,
          request.bodyCancelled
        {
          break
        }
        await Task.yield()
      }

      let request = try #require(harness.recordedRequests().first)
      #expect(request.bodyCancelled)
      #expect(request.aborted == false)
    }

    @Test func browserTransportSendTimesOutBodyReads() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        bodyText: "accepted",
        behavior: .init(arrayBufferDelayMilliseconds: 500)
      )

      let response = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: .milliseconds(50)
      )

      do {
        _ = try await collectBodyData(response.body)
        Issue.record("Expected body read to time out")
      } catch let error as ClientError {
        #expect(error == .timedOut)
      }

      let request = try #require(harness.recordedRequests().first)
      #expect(request.aborted)
    }

    @Test func browserTransportSendTimesOutFetches() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        behavior: .init(fetchDelayMilliseconds: 500)
      )

      do {
        _ = try await transport.send(
          HTTPRequest(method: .get, url: exampleStatusURL),
          body: nil,
          timeout: .milliseconds(50)
        )
        Issue.record("Expected request to time out")
      } catch let error as ClientError {
        #expect(error == .timedOut)
      }

      let request = try #require(harness.recordedRequests().first)
      #expect(request.aborted)
    }

    @Test func clientDecodePathOverBrowserTransportTurnsFailingStatusesIntoClientErrors()
      async throws
    {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let client = Client(transport: transport)

      try harness.reset()
      try harness.configureResponse(
        statusCode: 503,
        url: exampleStatusURL,
        bodyText: "unavailable"
      )

      do {
        let _: DecodedResponse<GenerateAccepted> = try await client.sendResponse(
          HTTPRequest(method: .get, url: exampleStatusURL),
          expecting: GenerateAccepted.self
        )
        Issue.record("Expected request to throw")
      } catch let error as ClientError {
        #expect(error == .unsuccessfulStatusCode(503, body: "unavailable"))
      }
    }
  }
#endif
