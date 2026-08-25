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

    @Test func browserTransportFailsSafelyWhenTheRuntimeIsUnsupported() async throws {
      let harness = try BrowserTestHarness()

      try harness.reset()
      defer {
        try? harness.reset()
      }
      try harness.removeFetch()

      #expect(BrowserTransport.isSupportedRuntime == false)
      let transport = BrowserTransport()
      await #expect(throws: ClientError.unsupportedPlatform) {
        _ = try await transport.send(
          HTTPRequest(method: .get, url: exampleStatusURL),
          body: nil,
          timeout: nil
        )
      }
    }

    @Test func browserTransportFailsSafelyWithoutClearTimeout() async throws {
      let harness = try BrowserTestHarness()

      try harness.reset()
      defer {
        try? harness.reset()
      }
      try harness.removeClearTimeout()

      #expect(BrowserTransport.isSupportedRuntime == false)
      let transport = BrowserTransport()
      await #expect(throws: ClientError.unsupportedPlatform) {
        _ = try await transport.send(
          HTTPRequest(method: .get, url: exampleStatusURL),
          body: nil,
          timeout: nil
        )
      }
    }

    @Test func browserTransportDetectsRuntimeLossAfterInitialization() async throws {
      let harness = try BrowserTestHarness()

      try harness.reset()
      let transport = BrowserTransport()
      defer {
        try? harness.reset()
      }
      try harness.removeFetch()

      await #expect(throws: ClientError.invalidJavaScriptContext) {
        _ = try await transport.send(
          HTTPRequest(method: .get, url: exampleStatusURL),
          body: nil,
          timeout: nil
        )
      }
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

    @Test func browserTransportAppliesConfiguredFetchRequestOptions() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport(
        requestOptions: .init(
          credentials: .include,
          mode: .cors,
          cache: .noStore,
          redirect: .follow
        )
      )

      try harness.reset()
      try harness.configureResponse(statusCode: 204)

      _ = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )

      let request = try #require(harness.recordedRequests().first)
      #expect(request.credentials == "include")
      #expect(request.mode == "cors")
      #expect(request.cache == "no-store")
      #expect(request.redirect == "follow")
    }

    @Test func browserTransportOmitsUnsetFetchRequestOptions() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport(requestOptions: .init(credentials: .omit))

      try harness.reset()
      try harness.configureResponse(statusCode: 204)

      _ = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )

      let request = try #require(harness.recordedRequests().first)
      #expect(request.credentials == "omit")
      #expect(request.mode == nil)
      #expect(request.cache == nil)
      #expect(request.redirect == nil)
    }

    @Test func clientUsesInjectedBrowserTransportRequestOptions() async throws {
      let harness = try BrowserTestHarness()
      let client = Client(
        transport: BrowserTransport(
          requestOptions: .init(credentials: .include)
        )
      )

      try harness.reset()
      try harness.configureResponse(statusCode: 204)

      _ = try await client.send(
        .delete(exampleStatusURL),
        as: EmptyResponse.self
      )

      let request = try #require(harness.recordedRequests().first)
      #expect(request.credentials == "include")
    }

    @Test func browserTransportPreservesExplicitEmptyRequestBodies() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(statusCode: 204)

      _ = try await transport.send(
        HTTPRequest(method: .post, url: exampleGenerateURL),
        body: HTTPBody(),
        timeout: nil
      )

      let request = try #require(harness.recordedRequests().first)
      #expect(request.bodyText == "")
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

      let accepted = try await client.send(
        .get(exampleStatusURL),
        as: GenerateAccepted.self
      )

      #expect(accepted.value == GenerateAccepted(statusURL: exampleStatusURL))
      #expect(accepted.response.status.code == 200)
      #expect(accepted.response.headerFields[HTTPField.Name.contentType] == "application/json")
      #expect(accepted.url == exampleStatusURL)
    }

    @Test func clientDecodePathOverBrowserTransportUsesConfiguredBodyCodec() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let client = Client(transport: transport)

      try harness.reset()
      try harness.configureResponse(
        statusCode: 202,
        headers: ["content-type": "text/plain"],
        url: exampleStatusURL,
        bodyText: "accepted"
      )

      let accepted = try await client.send(
        .post(exampleGenerateURL, body: "publish"),
        as: String.self,
        codec: .plainText()
      )
      let recordedRequest = try #require(harness.recordedRequests().first)

      #expect(accepted.value == "accepted")
      #expect(recordedRequest.headers["Accept"] == "text/plain")
      #expect(recordedRequest.headers["Content-Type"] == "text/plain")
      #expect(recordedRequest.bodyText == "publish")
    }

    @Test func browserTransportPreservesDuplicateOutgoingHeadersSemantically() async throws {
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

      var headers = HTTPFields()
      headers.append(.init(name: .accept, value: "application/vnd.parcel+json"))
      headers.append(.init(name: .accept, value: "application/json"))

      let _ = try await client.send(
        .get(exampleStatusURL, headers: headers),
        as: GenerateAccepted.self
      )
      let recordedRequest = try #require(harness.recordedRequests().first)

      #expect(
        recordedRequest.headers["Accept"]
          == "application/vnd.parcel+json, application/json"
      )
    }

    @Test func browserTransportPreservesRawHeaderBytesAcrossTheJavaScriptBridge() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let rawValue: [UInt8] = [0x80, 0xFF]
      var requestHeaders = HTTPFields()
      requestHeaders.append(.init(name: .xBinary, value: rawValue))
      var responseHeaderValue = String()
      responseHeaderValue.unicodeScalars.append(UnicodeScalar(0x80)!)
      responseHeaderValue.unicodeScalars.append(UnicodeScalar(0xFF)!)

      try harness.reset()
      try harness.configureResponse(
        statusCode: 204,
        headers: ["x-binary": responseHeaderValue]
      )

      let response = try await transport.send(
        HTTPRequest(
          method: .get,
          url: exampleStatusURL,
          headerFields: requestHeaders
        ),
        body: nil,
        timeout: nil
      )
      let request = try #require(harness.recordedRequests().first)
      let recordedValue = try #require(request.headers["X-Binary"])
      let responseField = try #require(
        response.response.headerFields.first { $0.name == .xBinary }
      )
      let responseBytes = responseField.withUnsafeBytesOfValue(Array.init)

      #expect(recordedValue.unicodeScalars.map(\.value) == [0x80, 0xFF])
      #expect(responseBytes == rawValue)
    }

    @Test func browserTransportSendsPerRequestHeaderOverridesOfDefaults() async throws {
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

      let _ = try await client.send(
        .get(exampleStatusURL, headers: [.accept: "application/json"]),
        as: GenerateAccepted.self
      )
      let recordedRequest = try #require(harness.recordedRequests().first)

      #expect(recordedRequest.headers["Accept"] == "application/json")
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
        let _: Client.Response<GenerateAccepted> = try await client.send(
          .get(exampleStatusURL),
          as: GenerateAccepted.self
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
        let _: Client.Response<GenerateAccepted> = try await client.send(
          .get(exampleStatusURL),
          as: GenerateAccepted.self
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
        let _: Client.Response<GenerateAccepted> = try await client.send(
          .get(exampleStatusURL),
          as: GenerateAccepted.self
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

      let response = try await client.send(
        .delete(exampleStatusURL),
        as: EmptyResponse.self
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
        let _: Client.Response<EmptyResponse> = try await client.send(
          .get(exampleStatusURL),
          as: EmptyResponse.self
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
        behavior: .init(bodyReadDelayMilliseconds: 500)
      )

      let response = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )
      let task = Task {
        try await collectBodyData(response.body)
      }

      try await harness.waitForRequestState(.bodyReadStarted)
      task.cancel()

      do {
        _ = try await task.value
        Issue.record("Expected request to be cancelled")
      } catch is CancellationError {
      } catch {
        Issue.record("Expected cancellation, got \(error)")
      }

      try await harness.waitForRequestState(.readerReleased)

      let request = try #require(harness.recordedRequests().first)
      #expect(request.aborted)
      #expect(request.readerReleased)
    }

    @Test func browserTransportCancelsAbandonedResponseBodies() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        bodyText: "accepted",
        behavior: .init(bodyReadDelayMilliseconds: 500)
      )

      do {
        let response = try await transport.send(
          HTTPRequest(method: .get, url: exampleStatusURL),
          body: nil,
          timeout: nil
        )
        #expect(response.body != nil)
      }

      try await harness.waitForRequestState(.readerReleased)

      let request = try #require(harness.recordedRequests().first)
      #expect(request.bodyCancelled)
      #expect(request.aborted == false)
      #expect(request.readerReleased)
    }

    @Test func browserTransportSendTimesOutBodyReads() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        bodyText: "accepted",
        behavior: .init(bodyReadDelayMilliseconds: 500)
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

    @Test func browserTransportMapsFetchRejectionsToFetchFailure() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        behavior: .init(
          fetchErrorName: "TypeError",
          fetchErrorMessage: "Failed to fetch"
        )
      )

      do {
        _ = try await transport.send(
          HTTPRequest(method: .get, url: exampleStatusURL),
          body: nil,
          timeout: nil
        )
        Issue.record("Expected request to throw")
      } catch let error as ClientError {
        guard case .fetchFailure(let failure) = error else {
          Issue.record("Expected fetchFailure, got \(error)")
          return
        }

        #expect(failure.name == "TypeError")
        #expect(failure.message == "Failed to fetch")
      }
    }

    @Test func browserTransportThrowsInvalidFetchResponseForMissingStatus() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        behavior: .init(omitResponseStatus: true)
      )

      do {
        _ = try await transport.send(
          HTTPRequest(method: .get, url: exampleStatusURL),
          body: nil,
          timeout: nil
        )
        Issue.record("Expected request to throw")
      } catch let error as ClientError {
        #expect(error == .invalidFetchResponse)
      }
    }

    @Test func browserTransportRejectsNonByteResponseChunks() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        bodyText: "accepted",
        behavior: .init(invalidBodyChunk: true)
      )

      let response = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )

      do {
        _ = try await collectBodyData(response.body)
        Issue.record("Expected body read to throw")
      } catch let error as ClientError {
        #expect(error == .invalidResponseBody)
      }
    }

    @Test func browserTransportReleasesReadersWhenBodyCollectionExceedsItsLimit() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        bodyText: "accepted",
        behavior: .init(
          cancelErrorName: "TypeError",
          cancelErrorMessage: "Cancellation failed"
        )
      )

      let response = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )

      await #expect(throws: HTTPBody.TooManyBytesError.self) {
        _ = try await response.body?.collect(upTo: 4)
      }

      try await harness.waitForRequestState(.readerReleased)

      let request = try #require(harness.recordedRequests().first)
      #expect(request.bodyCancelled)
      #expect(request.readerReleased)
      #expect(request.aborted == false)
    }

    @Test func browserTransportReleasesReadersAfterResponseBodyFailures() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        bodyText: "accepted",
        behavior: .init(
          bodyReadErrorName: "TypeError",
          bodyReadErrorMessage: "Stream failed"
        )
      )

      let response = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )

      do {
        _ = try await response.body?.collect()
        Issue.record("Expected body collection to fail")
      } catch let error as ClientError {
        guard case .responseBodyFailure(let javaScriptError) = error else {
          Issue.record("Expected responseBodyFailure, got \(error)")
          return
        }
        #expect(javaScriptError.name == "TypeError")
        #expect(javaScriptError.message == "Stream failed")
      }

      try await harness.waitForRequestState(.readerReleased)

      let request = try #require(harness.recordedRequests().first)
      #expect(request.bodyCancelled)
      #expect(request.readerReleased)
    }

    @Test func browserTransportTimesOutStalledRequestBodyStreams() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(statusCode: 204)

      let stalledBody = HTTPBody(
        AsyncStream<HTTPBody.ByteChunk> { _ in },
        length: .unknown
      )

      do {
        _ = try await transport.send(
          HTTPRequest(method: .post, url: exampleGenerateURL),
          body: stalledBody,
          timeout: .milliseconds(50)
        )
        Issue.record("Expected request to time out")
      } catch let error as ClientError {
        #expect(error == .timedOut)
      }

      #expect(try harness.recordedRequests().isEmpty)
    }

    @Test func browserTransportTimeoutDoesNotWaitForNoncooperativeRequestBodyStreams()
      async throws
    {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let gate = BrowserTestGate()

      try harness.reset()
      try harness.configureResponse(statusCode: 204)

      do {
        _ = try await transport.send(
          HTTPRequest(method: .post, url: exampleGenerateURL),
          body: HTTPBody(
            NoncooperativeGatedBodySequence(gate: gate),
            length: .unknown,
            iterationBehavior: .single
          ),
          timeout: .milliseconds(50)
        )
        Issue.record("Expected request to time out")
      } catch let error as ClientError {
        #expect(error == .timedOut)
      }

      #expect(try harness.recordedRequests().isEmpty)
      await gate.open()
    }

    @Test func browserTransportRejectsPreCancelledTasksBeforeFetching() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()
      let gate = BrowserTestGate()

      try harness.reset()
      try harness.configureResponse(statusCode: 204)

      let task = Task {
        await gate.wait()
        return try await transport.send(
          HTTPRequest(method: .get, url: exampleStatusURL),
          body: nil,
          timeout: nil
        )
      }
      task.cancel()
      await gate.open()

      await #expect(throws: CancellationError.self) {
        _ = try await task.value
      }
      #expect(try harness.recordedRequests().isEmpty)
    }

    @Test func browserTransportReportsUnknownLengthForEncodedBodies() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        headers: [
          "content-encoding": "gzip",
          "content-length": "999",
        ],
        bodyText: "accepted"
      )

      let response = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )

      #expect(response.body?.length == .unknown)
      #expect(try await collectBodyText(response.body) == "accepted")
    }

    @Test func browserTransportReportsKnownLengthForIdentityBodies() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        headers: ["content-length": "8"],
        bodyText: "accepted"
      )

      let response = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )

      #expect(response.body?.length == .known(8))
    }

    @Test func browserTransportBodyIteratorsReturnNilAfterExhaustion() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(
        statusCode: 200,
        bodyText: "accepted"
      )

      let response = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )
      let body = try #require(response.body)

      var iterator = body.makeAsyncIterator()
      while try await iterator.next() != nil {}

      #expect(try await iterator.next() == nil)
    }

    @Test func browserTransportRejectsGetRequestBodiesBeforeFetching() async throws {
      let harness = try BrowserTestHarness()
      let transport = BrowserTransport()

      try harness.reset()
      try harness.configureResponse(statusCode: 200)

      do {
        _ = try await transport.send(
          HTTPRequest(method: .get, url: exampleStatusURL),
          body: HTTPBody("payload"),
          timeout: nil
        )
        Issue.record("Expected request to throw")
      } catch let error as ClientError {
        #expect(error == .requestBodyNotAllowed(.get))
      }

      #expect(try harness.recordedRequests().isEmpty)
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
        let _: Client.Response<GenerateAccepted> = try await client.send(
          .get(exampleStatusURL),
          as: GenerateAccepted.self
        )
        Issue.record("Expected request to throw")
      } catch let error as ClientError {
        #expect(error == .unsuccessfulStatusCode(503, body: "unavailable"))
      }
    }
  }
#endif
