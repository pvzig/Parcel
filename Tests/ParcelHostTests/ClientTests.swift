#if !arch(wasm32)
  import Foundation
  import HTTPTypes
  import Testing

  @testable import Parcel

  @Test func sendEncodesJSONAndDecodesResponse() async throws {
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

    let accepted = try await client.send(
      .post(
        exampleGenerateURL,
        body: GenerateRequest(pagePath: "/posts/example"),
        headers: [.xTrace: "123"]
      ),
      as: GenerateAccepted.self
    )

    let request = await transport.lastRequest
    let body = try #require(await transport.lastBody)
    let decodedBody = try JSONDecoder().decode(GenerateRequest.self, from: body)

    #expect(accepted.value.statusURL == exampleStatusURL)
    #expect(request?.method == .post)
    #expect(request?.url == exampleGenerateURL)
    #expect(request?.headerFields[.xClient] == "Parcel")
    #expect(request?.headerFields[.xTrace] == "123")
    #expect(request?.headerFields[.accept] == "application/json")
    #expect(request?.headerFields[.contentType] == "application/json")
    #expect(decodedBody == GenerateRequest(pagePath: "/posts/example"))
  }

  @Test func typedResponsesPreserveMetadata() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 202,
        headerFields: [.eTag: "abc123"],
        url: exampleStatusURL,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(transport: transport)

    let accepted = try await client.send(
      .get(exampleStatusURL),
      as: GenerateAccepted.self
    )

    #expect(accepted.value.statusURL == exampleStatusURL)
    #expect(accepted.response.status.code == 202)
    #expect(accepted.response.headerFields[.eTag] == "abc123")
    #expect(accepted.url == exampleStatusURL)
  }

  @Test func customDefaultCodecAppliesToClientDecodePath() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: Data(#"{"generatedAt":"2026-03-09T18:00:00Z"}"#.utf8)
      )
    )
    let client = Client(
      configuration: ClientConfiguration(
        defaultCodec: .json(
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

    let accepted = try await client.send(
      .get(exampleStatusURL),
      as: DatedAccepted.self
    )

    #expect(accepted.value.generatedAt == Date(timeIntervalSince1970: 1_773_079_200))
  }

  @Test func perCallPlainTextCodecUsesBuiltInCodec() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 202,
        body: Data("accepted".utf8)
      )
    )
    let client = Client(transport: transport)

    let accepted = try await client.send(
      .post(exampleGenerateURL, body: "publish"),
      as: String.self,
      codec: .plainText()
    )

    let request = await transport.lastRequest
    let body = try #require(await transport.lastBody)

    #expect(accepted.value == "accepted")
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

  @Test func perCallFormURLEncodedCodecAppliesHeadersAndEncodesTypedRequests() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: Data(
          "grant_type=client_credentials&scope=read+write&expires_in=3600&active=true&tag=fast&tag=beta"
            .utf8
        )
      )
    )
    let client = Client(transport: transport)
    let payload = TokenExchangePayload(
      grantType: "client_credentials",
      scope: "read write",
      expiresIn: 3600,
      active: true,
      tags: ["fast", "beta"]
    )

    let accepted = try await client.send(
      .post(exampleGenerateURL, body: payload),
      as: TokenExchangePayload.self,
      codec: .formURLEncoded()
    )

    let request = await transport.lastRequest
    let body = try #require(await transport.lastBody)
    let fields = decodeFormFields(body)

    #expect(accepted.value == payload)
    #expect(request?.headerFields[.accept] == "application/x-www-form-urlencoded")
    #expect(request?.headerFields[.contentType] == "application/x-www-form-urlencoded")
    #expect(fields["grant_type"] == ["client_credentials"])
    #expect(fields["scope"] == ["read write"])
    #expect(fields["expires_in"] == ["3600"])
    #expect(fields["active"] == ["true"])
    #expect(fields["tag"] == ["fast", "beta"])
  }

  @Test func perCallRawDataCodecPassesThroughBinaryBodies() async throws {
    let responseBody = Data([0xDE, 0xAD, 0xBE, 0xEF])
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: responseBody
      )
    )
    let client = Client(transport: transport)
    let payload = Data([0x00, 0x01, 0x7F])

    let accepted = try await client.send(
      .post(exampleGenerateURL, body: payload),
      as: Data.self,
      codec: .rawData()
    )

    let request = await transport.lastRequest
    let body = try #require(await transport.lastBody)

    #expect(accepted.value == responseBody)
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

    let _ = try await client.send(
      .get(exampleStatusURL, headers: [.accept: "application/json"]),
      as: GenerateAccepted.self
    )

    let request = await transport.lastRequest

    #expect(
      request?.headerFields[values: .accept] == [
        "application/vnd.parcel+json",
        "application/json",
      ])
  }

  @Test func typedRequestsApplyDefaultCodecAcceptHeaderByDefault() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(transport: transport)

    let _ = try await client.send(
      .get(exampleStatusURL),
      as: GenerateAccepted.self
    )
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

    let _ = try await client.send(
      .get(exampleStatusURL),
      as: GenerateAccepted.self
    )

    #expect(await transport.lastTimeout == .seconds(90))
  }

  @Test func rawRequestsLetPerCallTimeoutOverrideTheDefaultTimeout() async throws {
    let transport = RecordingTransport(response: fixtureResponse(statusCode: 204))
    let client = Client(
      configuration: ClientConfiguration(defaultTimeout: .seconds(90)),
      transport: transport
    )

    _ = try await client.raw(
      HTTPRequest(method: .head, url: exampleStatusURL),
      timeout: .seconds(3)
    )

    #expect(await transport.lastTimeout == .seconds(3))
  }

  @Test func rawRequestSendMergesDefaultHeadersWithoutAddingCodecHeaders() async throws {
    let transport = RecordingTransport(response: fixtureResponse(statusCode: 204))
    let client = Client(
      configuration: ClientConfiguration(defaultHeaders: [.xClient: "Parcel"]),
      transport: transport
    )

    _ = try await client.raw(
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

  @Test func headRequestsSendHEADRequests() async throws {
    let transport = RecordingTransport(response: fixtureResponse(statusCode: 204))
    let client = Client(transport: transport)

    let response = try await client.send(
      .head(exampleStatusURL),
      as: EmptyResponse.self
    )
    let request = await transport.lastRequest

    #expect(response.value == EmptyResponse())
    #expect(request?.method == .head)
  }

  @Test func emptyResponseCanDecodeToEmptyResponse() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(statusCode: 204)
    )
    let client = Client(transport: transport)

    let response = try await client.send(
      .delete(exampleStatusURL),
      as: EmptyResponse.self
    )

    #expect(response.value == EmptyResponse())
  }

  @Test func emptySuccessfulBodyThrowsEmptyResponseBodyWhenExpectingModel() async throws {
    let transport = RecordingTransport(
      response: fixtureResponse(statusCode: 200, body: Data())
    )
    let client = Client(transport: transport)

    do {
      let _ = try await client.send(
        .get(exampleStatusURL),
        as: GenerateAccepted.self
      )
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
      let _ = try await client.send(
        .get(exampleStatusURL),
        as: EmptyResponse.self
      )
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
      let _ = try await client.send(
        .get(exampleStatusURL),
        as: GenerateAccepted.self
      )
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
        maximumBufferedBodyBytes: 4
      ),
      transport: transport
    )

    do {
      let _ = try await client.send(
        .get(exampleStatusURL),
        as: String.self,
        codec: .plainText()
      )
      Issue.record("Expected request to enforce the configured body limit")
    } catch let error as HTTPBody.TooManyBytesError {
      #expect(error == .init(maxBytes: 4))
    }
  }
#endif
