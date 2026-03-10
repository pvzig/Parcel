#if !arch(wasm32)
  import Foundation
  import Testing

  @testable import Parcel

  @Test func postEncodesJSONAndDecodesResponse() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(
        statusCode: 202,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(
      configuration: ClientConfiguration(defaultHeaders: ["X-Client": "Parcel"]),
      transport: transport
    )

    let accepted: GenerateAccepted = try await client.post(
      GenerateRequest(pagePath: "/posts/example"),
      to: exampleGenerateURL,
      headers: ["X-Trace": "123"]
    )

    let request = await transport.lastRequest
    let body = try #require(request?.body)
    let decodedBody = try JSONDecoder().decode(GenerateRequest.self, from: body)

    #expect(accepted.statusURL == exampleStatusURL)
    #expect(request?.method == .post)
    #expect(request?.url == exampleGenerateURL)
    #expect(request?.headers["X-Client"] == "Parcel")
    #expect(request?.headers["X-Trace"] == "123")
    #expect(request?.headers["Accept"] == nil)
    #expect(request?.headers["Content-Type"] == nil)
    #expect(decodedBody == GenerateRequest(pagePath: "/posts/example"))
  }

  @Test func responseMethodsPreserveMetadata() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(
        statusCode: 202,
        headers: ["etag": "abc123"],
        url: exampleStatusURL,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(transport: transport)

    let accepted = try await client.getResponse(
      from: exampleStatusURL,
      expecting: GenerateAccepted.self
    )

    #expect(accepted.value.statusURL == exampleStatusURL)
    #expect(accepted.response.statusCode == 202)
    #expect(accepted.response.headers["etag"] == "abc123")
    #expect(accepted.response.url == exampleStatusURL)
  }

  @Test func customDecoderAppliesToClientDecodePath() async throws {
    let transport = RecordingTransport(
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
          }
        )
      ),
      transport: transport
    )

    let accepted: DatedAccepted = try await client.get(from: exampleStatusURL)

    #expect(accepted.generatedAt == Date(timeIntervalSince1970: 1_773_079_200))
  }

  @Test func additionalHeadersOverrideDefaultHeadersCaseInsensitively() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(
      configuration: ClientConfiguration(
        defaultHeaders: ["accept": "application/vnd.parcel+json"]
      ),
      transport: transport
    )

    let _: GenerateAccepted = try await client.get(
      from: exampleStatusURL,
      headers: ["Accept": "application/json"]
    )

    let request = await transport.lastRequest

    #expect(request?.headers["Accept"] == "application/json")
    #expect(request?.headers.values(for: "accept") == ["application/json"])
  }

  @Test func typedRequestsDoNotAddJSONHeadersByDefault() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(transport: transport)

    let _: GenerateAccepted = try await client.get(from: exampleStatusURL)
    let request = await transport.lastRequest

    #expect(request?.headers["Accept"] == nil)
    #expect(request?.headers["Content-Type"] == nil)
  }

  @Test func rawRequestSendMergesDefaultHeadersWithoutAddingJSONHeaders() async throws {
    let transport = RecordingTransport(response: HTTPResponse(statusCode: 204))
    let client = Client(
      configuration: ClientConfiguration(defaultHeaders: ["X-Client": "Parcel"]),
      transport: transport
    )

    _ = try await client.send(
      HTTPRequest(
        method: .head,
        url: exampleStatusURL,
        headers: ["X-Trace": "123"]
      )
    )

    let request = await transport.lastRequest

    #expect(request?.method == .head)
    #expect(request?.headers["X-Client"] == "Parcel")
    #expect(request?.headers["X-Trace"] == "123")
    #expect(request?.headers["Accept"] == nil)
    #expect(request?.headers["Content-Type"] == nil)
  }

  @Test func headResponseSendsHEADRequests() async throws {
    let transport = RecordingTransport(response: HTTPResponse(statusCode: 204))
    let client = Client(transport: transport)

    let response: EmptyResponse = try await client.head(from: exampleStatusURL)
    let request = await transport.lastRequest

    #expect(response == EmptyResponse())
    #expect(request?.method == .head)
  }

  @Test func defaultClientUsesUnavailableTransportOnHostBuilds() async throws {
    let client = Client()

    do {
      let _: GenerateAccepted = try await client.get(from: exampleStatusURL)
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .unsupportedPlatform)
    }
  }

  @Test func browserTransportRawSendIsUnavailableOnHostBuilds() async throws {
    let transport = BrowserTransport()

    do {
      _ = try await transport.send(
        HTTPRequest(method: .get, url: exampleStatusURL)
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

    let response: EmptyResponse = try await client.delete(from: exampleStatusURL)

    #expect(response == EmptyResponse())
  }

  @Test func emptySuccessfulBodyThrowsEmptyResponseBodyWhenExpectingModel() async throws {
    let transport = RecordingTransport(
      response: HTTPResponse(statusCode: 200, body: Data())
    )
    let client = Client(transport: transport)

    do {
      let _: GenerateAccepted = try await client.get(from: exampleStatusURL)
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
      let _: EmptyResponse = try await client.get(from: exampleStatusURL)
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
      let _: GenerateAccepted = try await client.get(from: exampleStatusURL)
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .unsuccessfulStatusCode(503, body: "unavailable"))
    }
  }
#endif
