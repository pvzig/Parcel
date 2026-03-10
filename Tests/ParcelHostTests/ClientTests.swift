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

    #expect(accepted.value.statusURL == exampleStatusURL)
    #expect(accepted.response.status.code == 202)
    #expect(accepted.response.headerFields[.eTag] == "abc123")
    #expect(accepted.url == exampleStatusURL)
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

  @Test func plainTextBodyCodingUsesBuiltInCodec() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 202,
        body: Data("accepted".utf8)
      )
    )
    let client = Client(
      configuration: ClientConfiguration(
        bodyCoding: .plainText()
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

  @Test func formURLEncodedBodyCodecRoundTripsFlatPayloads() throws {
    let codec = FormURLEncodedBodyCodec()
    let payload = TokenExchangePayload(
      grantType: "client_credentials",
      scope: "read write",
      expiresIn: 3600,
      active: true,
      tags: ["fast", "beta"]
    )

    let body = try codec.encode(payload)
    let decoded = try codec.decode(TokenExchangePayload.self, from: body)
    let fields = decodeFormFields(body)

    #expect(fields["grant_type"] == ["client_credentials"])
    #expect(fields["scope"] == ["read write"])
    #expect(fields["expires_in"] == ["3600"])
    #expect(fields["active"] == ["true"])
    #expect(fields["tag"] == ["fast", "beta"])
    #expect(decoded == payload)
  }

  @Test func formURLEncodedBodyCodingAppliesHeadersAndEncodesTypedRequests() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: Data(
          "grant_type=client_credentials&scope=read+write&expires_in=3600&active=true&tag=fast&tag=beta"
            .utf8
        )
      )
    )
    let client = Client(
      configuration: ClientConfiguration(bodyCoding: .formURLEncoded()),
      transport: transport
    )
    let payload = TokenExchangePayload(
      grantType: "client_credentials",
      scope: "read write",
      expiresIn: 3600,
      active: true,
      tags: ["fast", "beta"]
    )

    let accepted: TokenExchangePayload = try await client.post(
      payload,
      to: exampleGenerateURL
    )

    let request = await transport.lastRequest
    let body = try #require(await transport.lastBody)
    let fields = decodeFormFields(body)

    #expect(accepted == payload)
    #expect(request?.headerFields[.accept] == "application/x-www-form-urlencoded")
    #expect(request?.headerFields[.contentType] == "application/x-www-form-urlencoded")
    #expect(fields["grant_type"] == ["client_credentials"])
    #expect(fields["scope"] == ["read write"])
    #expect(fields["expires_in"] == ["3600"])
    #expect(fields["active"] == ["true"])
    #expect(fields["tag"] == ["fast", "beta"])
  }

  @Test func rawDataBodyCodingPassesThroughBinaryBodies() async throws {
    let responseBody = Data([0xDE, 0xAD, 0xBE, 0xEF])
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: responseBody
      )
    )
    let client = Client(
      configuration: ClientConfiguration(bodyCoding: .rawData()),
      transport: transport
    )
    let payload = Data([0x00, 0x01, 0x7F])

    let accepted: Data = try await client.post(
      payload,
      to: exampleGenerateURL
    )

    let request = await transport.lastRequest
    let body = try #require(await transport.lastBody)

    #expect(accepted == responseBody)
    #expect(body == payload)
    #expect(request?.headerFields[.accept] == "application/octet-stream")
    #expect(request?.headerFields[.contentType] == "application/octet-stream")
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

  @Test func typedRequestsUseDefaultTimeoutWhenCallerOmitsOne() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(
      configuration: ClientConfiguration(defaultTimeout: .seconds(90)),
      transport: transport
    )

    let _: GenerateAccepted = try await client.get(from: exampleStatusURL)

    #expect(await transport.lastTimeout == .seconds(90))
  }

  @Test func rawRequestsLetPerCallTimeoutOverrideTheDefaultTimeout() async throws {
    let transport = RecordingTransport(response: fixtureResponse(statusCode: 204))
    let client = Client(
      configuration: ClientConfiguration(defaultTimeout: .seconds(90)),
      transport: transport
    )

    _ = try await client.send(
      HTTPRequest(method: .head, url: exampleStatusURL),
      timeout: .seconds(3)
    )

    #expect(await transport.lastTimeout == .seconds(3))
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
      body: HTTPBody(Data("publish".utf8)),
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

  @Test func clientDecodeHonorsMaximumBufferedBodyBytes() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(statusCode: 200, body: Data("hello".utf8))
    )
    let client = Client(
      configuration: ClientConfiguration(
        bodyCoding: .plainText(),
        maximumBufferedBodyBytes: 4
      ),
      transport: transport
    )

    do {
      let _: String = try await client.get(from: exampleStatusURL)
      Issue.record("Expected request to enforce the configured body limit")
    } catch let error as HTTPBody.TooManyBytesError {
      #expect(error == .init(maxBytes: 4))
    }
  }
#endif
