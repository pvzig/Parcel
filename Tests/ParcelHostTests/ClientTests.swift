#if !arch(wasm32)
  import Foundation
  import HTTPTypes
  import Testing

  @testable import Parcel

  @Test func postEncodesJSONAndDecodesResponse() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 202,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(
      configuration: ClientConfiguration(defaultHeaders: [.xClient: "Parcel"]),
      transport: transport
    )

    let accepted: GenerateAccepted = try await client.post(
      GenerateRequest(pagePath: "/posts/example"),
      to: exampleGenerateURL,
      headers: [.xTrace: "123"]
    )

    let request = await transport.lastRequest
    let body = try #require(await transport.lastBody)
    let decodedBody = try JSONDecoder().decode(GenerateRequest.self, from: body)

    #expect(accepted.statusURL == exampleStatusURL)
    #expect(request?.method == .post)
    #expect(request?.url == exampleGenerateURL)
    #expect(request?.headerFields[.xClient] == "Parcel")
    #expect(request?.headerFields[.xTrace] == "123")
    #expect(request?.headerFields[.accept] == "application/json")
    #expect(request?.headerFields[.contentType] == "application/json")
    #expect(decodedBody == GenerateRequest(pagePath: "/posts/example"))
  }

  @Test func responseMethodsPreserveMetadata() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 202,
        headerFields: [.eTag: "abc123"],
        url: exampleStatusURL,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(transport: transport)

    let accepted = try await client.getResponse(
      from: exampleStatusURL,
      expecting: GenerateAccepted.self
    )
    let expectedBody = try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))

    #expect(accepted.value.statusURL == exampleStatusURL)
    #expect(accepted.response.status.code == 202)
    #expect(accepted.response.headerFields[.eTag] == "abc123")
    #expect(accepted.url == exampleStatusURL)
    #expect(accepted.body == expectedBody)
  }

  @Test func customDecoderAppliesToClientDecodePath() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: Data(#"{"generatedAt":"2026-03-09T18:00:00Z"}"#.utf8)
      )
    )
    let client = Client(
      configuration: ClientConfiguration(
        bodyCoding: .json(
          codec: JSONBodyCodec(
            makeDecoder: {
              let decoder = JSONDecoder()
              decoder.dateDecodingStrategy = .iso8601
              return decoder
            }
          )
        )
      ),
      transport: transport
    )

    let accepted: DatedAccepted = try await client.get(from: exampleStatusURL)

    #expect(accepted.generatedAt == Date(timeIntervalSince1970: 1_773_079_200))
  }

  @Test func customBodyCodecReplacesJSONForTypedRequestsAndResponses() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 202,
        body: Data("accepted".utf8)
      )
    )
    let client = Client(
      configuration: ClientConfiguration(
        bodyCoding: .init(
          codec: PlainTextCodec(),
          requestContentType: "text/plain",
          accept: ["text/plain"]
        )
      ),
      transport: transport
    )

    let accepted: String = try await client.post(
      "publish",
      to: exampleGenerateURL
    )

    let request = await transport.lastRequest
    let body = try #require(await transport.lastBody)

    #expect(accepted == "accepted")
    #expect(request?.headerFields[.accept] == "text/plain")
    #expect(request?.headerFields[.contentType] == "text/plain")
    #expect(String(decoding: body, as: UTF8.self) == "publish")
  }

  @Test func defaultAndAdditionalHeadersAreBothPreserved() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(
      configuration: ClientConfiguration(
        defaultHeaders: [HTTPField.Name("accept")!: "application/vnd.parcel+json"]
      ),
      transport: transport
    )

    let _: GenerateAccepted = try await client.get(
      from: exampleStatusURL,
      headers: [.accept: "application/json"]
    )

    let request = await transport.lastRequest

    #expect(
      request?.headerFields[values: .accept] == [
        "application/vnd.parcel+json",
        "application/json",
      ])
  }

  @Test func typedRequestsApplyBodyCodingAcceptHeaderByDefault() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(transport: transport)

    let _: GenerateAccepted = try await client.get(from: exampleStatusURL)
    let request = await transport.lastRequest

    #expect(request?.headerFields[.accept] == "application/json")
    #expect(request?.headerFields[.contentType] == nil)
  }

  @Test func rawRequestSendMergesDefaultHeadersWithoutAddingBodyCodingHeaders() async throws {
    let transport = RecordingTransport(response: fixtureResponse(statusCode: 204))
    let client = Client(
      configuration: ClientConfiguration(defaultHeaders: [.xClient: "Parcel"]),
      transport: transport
    )

    _ = try await client.send(
      HTTPRequest(
        method: .head,
        url: exampleStatusURL,
        headerFields: [.xTrace: "123"]
      )
    )

    let request = await transport.lastRequest

    #expect(request?.method == .head)
    #expect(request?.headerFields[.xClient] == "Parcel")
    #expect(request?.headerFields[.xTrace] == "123")
    #expect(request?.headerFields[.accept] == nil)
    #expect(request?.headerFields[.contentType] == nil)
  }

  @Test func typedRawRequestSendAddsAcceptWithoutAddingContentType() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(transport: transport)

    let _: DecodedResponse<GenerateAccepted> = try await client.sendResponse(
      HTTPRequest(method: .post, url: exampleGenerateURL),
      body: Data("publish".utf8),
      expecting: GenerateAccepted.self
    )
    let request = await transport.lastRequest

    #expect(request?.headerFields[.accept] == "application/json")
    #expect(request?.headerFields[.contentType] == nil)
  }

  @Test func headResponseSendsHEADRequests() async throws {
    let transport = RecordingTransport(response: fixtureResponse(statusCode: 204))
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
        HTTPRequest(method: .get, url: exampleStatusURL),
        body: nil,
        timeout: nil
      )
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .unsupportedPlatform)
    }
  }

  @Test func emptyResponseCanDecodeToEmptyResponse() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(statusCode: 204)
    )
    let client = Client(transport: transport)

    let response: EmptyResponse = try await client.delete(from: exampleStatusURL)

    #expect(response == EmptyResponse())
  }

  @Test func emptySuccessfulBodyThrowsEmptyResponseBodyWhenExpectingModel() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(statusCode: 200, body: Data())
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
      response: fixtureResponse(statusCode: 200, body: Data("accepted".utf8))
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
      response: fixtureResponse(statusCode: 503, body: Data("unavailable".utf8))
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
