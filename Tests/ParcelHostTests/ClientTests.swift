#if !arch(wasm32)
  import Foundation
  import Testing

  @testable import Parcel

  @Test func postEncodesJSONAndDecodesResponse() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(
        statusCode: 202,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: "https://example.com/status"))
      )
    )
    let client = Client(
      configuration: ClientConfiguration(defaultHeaders: ["X-Client": "Parcel"]),
      transport: transport
    )

    let accepted: GenerateAccepted = try await client.post(
      GenerateRequest(pagePath: "/posts/example"),
      to: "https://example.com/generate",
      headers: ["X-Trace": "123"]
    )

    let request = await transport.lastRequest
    let body = try #require(request?.body)
    let decodedBody = try JSONDecoder().decode(GenerateRequest.self, from: body)

    #expect(accepted.statusURL == "https://example.com/status")
    #expect(request?.method == .post)
    #expect(request?.url == "https://example.com/generate")
    #expect(request?.headers["Accept"] == "application/json")
    #expect(request?.headers["Content-Type"] == "application/json")
    #expect(request?.headers["X-Client"] == "Parcel")
    #expect(request?.headers["X-Trace"] == "123")
    #expect(decodedBody == GenerateRequest(pagePath: "/posts/example"))
  }

  @Test func responseMethodsPreserveMetadata() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(
        statusCode: 202,
        headers: ["etag": "abc123"],
        url: "https://example.com/status",
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: "https://example.com/status"))
      )
    )
    let client = Client(transport: transport)

    let accepted = try await client.getResponse(
      from: "https://example.com/status",
      expecting: GenerateAccepted.self
    )

    #expect(accepted.value.statusURL == "https://example.com/status")
    #expect(accepted.response.statusCode == 202)
    #expect(accepted.response.headers["etag"] == "abc123")
    #expect(accepted.response.url == "https://example.com/status")
  }

  @Test func clientUsesResponseDecodingTransportWhenAvailable() async throws {
    let transport = ResponseDecodingRecordingTransport()
    let client = Client(transport: transport)

    let accepted: GenerateAccepted = try await client.post(
      GenerateRequest(pagePath: "/posts/example"),
      to: "https://example.com/generate"
    )

    let counts = await transport.counts()

    #expect(accepted.statusURL == "https://example.com/status")
    #expect(counts.rawSendCount == 0)
    #expect(counts.typedSendCount == 1)
  }

  @Test func customDecoderUsesDataPathWhenTransportOptimizationIsDisabled() async throws {
    let transport = ResponseDecodingRecordingTransport(
      response: HTTPResponse(
        statusCode: 200,
        body: Data(#"{"generatedAt":"2026-03-09T18:00:00Z"}"#.utf8)
      )
    )
    let client = Client(
      configuration: ClientConfiguration(
        jsonCoding: JSONCodingConfiguration(
          makeDecoder: {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
          },
          prefersTransportSpecificResponseDecoding: false
        )
      ),
      transport: transport
    )

    let accepted: DatedAccepted = try await client.get(from: "https://example.com/status")
    let counts = await transport.counts()

    #expect(accepted.generatedAt == Date(timeIntervalSince1970: 1_773_079_200))
    #expect(counts.rawSendCount == 1)
    #expect(counts.typedSendCount == 0)
  }

  @Test func additionalHeadersOverrideDefaultHeadersCaseInsensitively() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: "https://example.com/status"))
      )
    )
    let client = Client(
      configuration: ClientConfiguration(
        defaultHeaders: ["accept": "application/vnd.parcel+json"]
      ),
      transport: transport
    )

    let _: GenerateAccepted = try await client.get(
      from: "https://example.com/status",
      headers: ["Accept": "application/json"]
    )

    let request = await transport.lastRequest

    #expect(request?.headers["Accept"] == "application/json")
    #expect(request?.headers["accept"] == nil)
  }

  @Test func defaultClientUsesUnavailableTransportOnHostBuilds() async throws {
    let client = Client()

    do {
      let _: GenerateAccepted = try await client.get(from: "https://example.com/status")
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .unsupportedPlatform)
    }
  }

  @Test func browserTransportTypedSendIsUnavailableOnHostBuilds() async throws {
    let transport = BrowserTransport()

    do {
      let _: DecodedResponse<GenerateAccepted> = try await transport.sendResponse(
        HTTPRequest(method: .get, url: "https://example.com/status"),
        expecting: GenerateAccepted.self
      )
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .unsupportedPlatform)
    }
  }

  @Test func emptyResponseCanDecodeToEmptyResponse() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(statusCode: 204)
    )
    let client = Client(transport: transport)

    let response: EmptyResponse = try await client.delete(from: "https://example.com/status")

    #expect(response == EmptyResponse())
  }

  @Test func emptySuccessfulBodyThrowsEmptyResponseBodyWhenExpectingModel() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(statusCode: 200, body: Data())
    )
    let client = Client(transport: transport)

    do {
      let _: GenerateAccepted = try await client.get(from: "https://example.com/status")
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .emptyResponseBody)
    }
  }

  @Test func invalidJSONBodyDoesNotSilentlyDecodeAsEmptyResponse() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(statusCode: 200, body: Data("accepted".utf8))
    )
    let client = Client(transport: transport)

    do {
      let _: EmptyResponse = try await client.get(from: "https://example.com/status")
      Issue.record("Expected request to throw")
    } catch is DecodingError {
    } catch {
      Issue.record("Expected decoding error, got \(error)")
    }
  }

  @Test func unsuccessfulStatusThrowsClientError() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(statusCode: 503, body: Data("unavailable".utf8))
    )
    let client = Client(transport: transport)

    do {
      let _: GenerateAccepted = try await client.get(from: "https://example.com/status")
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .unsuccessfulStatusCode(503, body: "unavailable"))
    }
  }
#endif
