#if !arch(wasm32)
  import Foundation
  import HTTPTypes
  import Testing

  @testable import Parcel

  @Test func namedOperationInfersOutputAndUsesDefaultJSONBodyCoding() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(
        statusCode: 202,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(
      configuration: ClientConfiguration(defaultHeaders: [.xClient: "Parcel"]),
      httpClient: httpClient
    )

    let accepted = try await client.send(
      .generate(
        GenerateRequest(pagePath: "/posts/example"),
        headers: [.xTrace: "123"]
      )
    )

    let request = await httpClient.lastRequest
    let body = try #require(await httpClient.lastBody)
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

  @Test func typedResponsesPreserveMetadata() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(
        statusCode: 202,
        headerFields: [.eTag: "abc123"],
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(httpClient: httpClient)

    let response: Client.Response<GenerateAccepted> = try await client.response(
      .get(exampleStatusURL)
    )

    #expect(response.value.statusURL == exampleStatusURL)
    #expect(response.response.status.code == 202)
    #expect(response.response.headerFields[.eTag] == "abc123")
  }

  @Test func customDefaultBodyCodingAppliesToClientDecodePath() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(
        statusCode: 200,
        body: Data(#"{"generatedAt":"2026-03-09T18:00:00Z"}"#.utf8)
      )
    )
    let client = Client(
      configuration: ClientConfiguration(
        defaultBodyCoding: .json(
          decoder: JSONBodyDecoder(
            makeDecoder: {
              let decoder = JSONDecoder()
              decoder.dateDecodingStrategy = .iso8601
              return decoder
            }
          )
        )
      ),
      httpClient: httpClient
    )

    let accepted: DatedAccepted = try await client.send(.get(exampleStatusURL))

    #expect(accepted.generatedAt == Date(timeIntervalSince1970: 1_773_079_200))
  }

  @Test func perOperationPlainTextBodyCodingUsesBuiltInComponents() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(
        statusCode: 202,
        body: Data("accepted".utf8)
      )
    )
    let client = Client(httpClient: httpClient)

    let accepted = try await client.send(
      Client.Request<String>.post(
        exampleGenerateURL,
        body: "publish",
        bodyCoding: .plainText()
      )
    )

    let request = await httpClient.lastRequest
    let body = try #require(await httpClient.lastBody)

    #expect(accepted == "accepted")
    #expect(request?.headerFields[.accept] == "text/plain")
    #expect(request?.headerFields[.contentType] == "text/plain")
    #expect(String(decoding: body, as: UTF8.self) == "publish")
  }

  @Test func perOperationFormBodyCodingEncodesFormAndDecodesJSON() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(httpClient: httpClient)
    let payload = TokenExchangePayload(
      grantType: "client_credentials",
      scope: "read write",
      expiresIn: 3600,
      active: true,
      tags: ["fast", "beta"]
    )

    let accepted = try await client.send(
      Client.Request<GenerateAccepted>.post(
        exampleGenerateURL,
        body: payload,
        bodyCoding: .formURLEncoded()
      )
    )

    let request = await httpClient.lastRequest
    let body = try #require(await httpClient.lastBody)
    let fields = try decodeFormFields(body)

    #expect(accepted == GenerateAccepted(statusURL: exampleStatusURL))
    #expect(request?.headerFields[.accept] == "application/json")
    #expect(request?.headerFields[.contentType] == "application/x-www-form-urlencoded")
    #expect(fields["grant_type"] == ["client_credentials"])
    #expect(fields["scope"] == ["read write"])
    #expect(fields["expires_in"] == ["3600"])
    #expect(fields["active"] == ["true"])
    #expect(fields["tag"] == ["fast", "beta"])
  }

  @Test func perOperationRawDataBodyCodingPassesThroughBinaryBodies() async throws {
    let responseBody = Data([0xDE, 0xAD, 0xBE, 0xEF])
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(
        statusCode: 200,
        body: responseBody
      )
    )
    let client = Client(httpClient: httpClient)
    let payload = Data([0x00, 0x01, 0x7F])

    let accepted = try await client.send(
      Client.Request<Data>.post(
        exampleGenerateURL,
        body: payload,
        bodyCoding: .rawData()
      )
    )

    let request = await httpClient.lastRequest
    let body = try #require(await httpClient.lastBody)

    #expect(accepted == responseBody)
    #expect(body == payload)
    #expect(request?.headerFields[.accept] == "application/octet-stream")
    #expect(request?.headerFields[.contentType] == "application/octet-stream")
  }

  @Test func perRequestHeadersOverrideSameNamedDefaultHeaders() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(
      configuration: ClientConfiguration(
        defaultHeaders: [
          HTTPField.Name("accept")!: "application/vnd.parcel+json",
          .xClient: "Parcel",
        ]
      ),
      httpClient: httpClient
    )

    let _ = try await client.send(
      Client.Request<GenerateAccepted>.get(
        exampleStatusURL,
        headers: [.accept: "application/json"]
      )
    )

    let request = await httpClient.lastRequest

    #expect(request?.headerFields[values: .accept] == ["application/json"])
    #expect(request?.headerFields[.xClient] == "Parcel")
  }

  @Test func repeatedPerRequestHeaderValuesArePreserved() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(httpClient: httpClient)

    var headers = HTTPFields()
    headers.append(.init(name: .accept, value: "application/vnd.parcel+json"))
    headers.append(.init(name: .accept, value: "application/json"))

    let _ = try await client.send(
      Client.Request<GenerateAccepted>.get(exampleStatusURL, headers: headers)
    )

    let request = await httpClient.lastRequest

    #expect(
      request?.headerFields[values: .accept] == [
        "application/vnd.parcel+json",
        "application/json",
      ])
  }

  @Test func typedRequestsApplyDefaultBodyCodingAcceptHeader() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(
        statusCode: 200,
        body: try JSONEncoder().encode(GenerateAccepted(statusURL: exampleStatusURL))
      )
    )
    let client = Client(httpClient: httpClient)

    let _ = try await client.send(
      Client.Request<GenerateAccepted>.get(exampleStatusURL)
    )
    let request = await httpClient.lastRequest

    #expect(request?.headerFields[.accept] == "application/json")
    #expect(request?.headerFields[.contentType] == nil)
  }

  @Test func rawRequestMergesDefaultsWithoutAddingBodyCodingHeaders() async throws {
    let httpClient = RecordingHTTPClient(response: fixtureResponse(statusCode: 204))
    let client = Client(
      configuration: ClientConfiguration(defaultHeaders: [.xClient: "Parcel"]),
      httpClient: httpClient
    )

    _ = try await client.raw(
      HTTPRequest(
        method: .head,
        url: exampleStatusURL,
        headerFields: [.xTrace: "123"]
      )
    )

    let request = await httpClient.lastRequest

    #expect(request?.method == .head)
    #expect(request?.headerFields[.xClient] == "Parcel")
    #expect(request?.headerFields[.xTrace] == "123")
    #expect(request?.headerFields[.accept] == nil)
    #expect(request?.headerFields[.contentType] == nil)
  }

  @Test func rawRequestsReturnBufferedBodiesAndNonSuccessStatuses() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(statusCode: 418, body: Data("teapot".utf8))
    )
    let client = Client(httpClient: httpClient)

    let response = try await client.raw(
      HTTPRequest(method: .get, url: exampleStatusURL)
    )

    #expect(response.response.status.code == 418)
    #expect(response.body == Data("teapot".utf8))
  }

  @Test func headRequestsSendHEADRequests() async throws {
    let httpClient = RecordingHTTPClient(response: fixtureResponse(statusCode: 204))
    let client = Client(httpClient: httpClient)

    let response = try await client.send(
      Client.Request<EmptyResponse>.head(exampleStatusURL)
    )
    let request = await httpClient.lastRequest

    #expect(response == EmptyResponse())
    #expect(request?.method == .head)
  }

  @Test func emptySuccessfulBodyThrowsEmptyResponseBodyWhenExpectingModel() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(statusCode: 200, body: Data())
    )
    let client = Client(httpClient: httpClient)

    do {
      let _ = try await client.send(
        Client.Request<GenerateAccepted>.get(exampleStatusURL)
      )
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .emptyResponseBody)
    }
  }

  @Test func invalidJSONBodyDoesNotSilentlyDecodeAsEmptyResponse() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(statusCode: 200, body: Data("accepted".utf8))
    )
    let client = Client(httpClient: httpClient)

    do {
      let _ = try await client.send(
        Client.Request<EmptyResponse>.get(exampleStatusURL)
      )
      Issue.record("Expected request to throw")
    } catch is DecodingError {
    } catch {
      Issue.record("Expected decoding error, got \(error)")
    }
  }

  @Test func unsuccessfulStatusThrowsClientError() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(statusCode: 503, body: Data("unavailable".utf8))
    )
    let client = Client(httpClient: httpClient)

    do {
      let _ = try await client.send(
        Client.Request<GenerateAccepted>.get(exampleStatusURL)
      )
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .unsuccessfulStatusCode(503, body: "unavailable"))
    }
  }

  @Test func relativeURLsThrowInvalidRequestURLInsteadOfTrapping() async throws {
    let httpClient = RecordingHTTPClient(response: fixtureResponse(statusCode: 200))
    let client = Client(httpClient: httpClient)

    do {
      let _ = try await client.send(
        Client.Request<EmptyResponse>.get(fixtureURL("/api/items"))
      )
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .invalidRequestURL("/api/items"))
    }

    #expect(await httpClient.lastRequest == nil)
  }

  @Test func hostlessURLsThrowInvalidRequestURLInsteadOfFailingLate() async throws {
    // These have a scheme, so they survive `HTTPRequest`'s schemeless precondition, but they
    // have no authority, which leaves `HTTPRequest.url` nil for the HTTP client.
    for urlString in ["mailto:someone@example.com", "file:///tmp/example", "https:///path"] {
      let httpClient = RecordingHTTPClient(response: fixtureResponse(statusCode: 200))
      let client = Client(httpClient: httpClient)

      do {
        let _ = try await client.send(
          Client.Request<EmptyResponse>.get(fixtureURL(urlString))
        )
        Issue.record("Expected \(urlString) to throw")
      } catch let error as ClientError {
        #expect(error == .invalidRequestURL(urlString))
      }

      #expect(await httpClient.lastRequest == nil)
    }
  }

  @Test func typedGetRequestsRejectBodies() async throws {
    let httpClient = RecordingHTTPClient(response: fixtureResponse(statusCode: 200))
    let client = Client(httpClient: httpClient)

    do {
      let _ = try await client.send(
        Client.Request<EmptyResponse>(
          method: .get,
          url: exampleStatusURL,
          body: GenerateRequest(pagePath: "/posts/example")
        )
      )
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .requestBodyNotAllowed(.get))
    }

    #expect(await httpClient.lastRequest == nil)
  }

  @Test func rawHeadRequestsRejectBodies() async throws {
    let httpClient = RecordingHTTPClient(response: fixtureResponse(statusCode: 200))
    let client = Client(httpClient: httpClient)

    do {
      _ = try await client.raw(
        HTTPRequest(method: .head, url: exampleStatusURL),
        body: Data("payload".utf8)
      )
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .requestBodyNotAllowed(.head))
    }

    #expect(await httpClient.lastRequest == nil)
  }

  @Test func oversizedErrorBodiesStillReportTheStatusCode() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(statusCode: 503, body: Data("unavailable".utf8))
    )
    let client = Client(
      configuration: ClientConfiguration(maximumBufferedBodyBytes: 4),
      httpClient: httpClient
    )

    do {
      let _ = try await client.send(
        Client.Request<GenerateAccepted>.get(exampleStatusURL)
      )
      Issue.record("Expected request to throw")
    } catch let error as ClientError {
      #expect(error == .unsuccessfulStatusCode(503, body: nil))
    }
  }

  @Test func emptySuccessfulBodiesDecodeThroughRawDataBodyCoding() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(statusCode: 200, body: Data())
    )
    let client = Client(httpClient: httpClient)

    let response = try await client.send(
      Client.Request<Data>.get(
        exampleStatusURL,
        bodyCoding: .rawData()
      )
    )

    #expect(response == Data())
  }

  @Test func missingSuccessfulBodiesDecodeThroughPlainTextBodyCoding() async throws {
    let httpClient = RecordingHTTPClient(response: fixtureResponse(statusCode: 204))
    let client = Client(httpClient: httpClient)

    let response = try await client.send(
      Client.Request<String>.get(
        exampleStatusURL,
        bodyCoding: .plainText()
      )
    )

    #expect(response == "")
  }

  @Test func clientDecodeHonorsMaximumBufferedBodyBytes() async throws {
    let httpClient = RecordingHTTPClient(
      response: fixtureResponse(statusCode: 200, body: Data("hello".utf8))
    )
    let client = Client(
      configuration: ClientConfiguration(
        maximumBufferedBodyBytes: 4
      ),
      httpClient: httpClient
    )

    do {
      let _ = try await client.send(
        Client.Request<String>.get(
          exampleStatusURL,
          bodyCoding: .plainText()
        )
      )
      Issue.record("Expected request to enforce the configured body limit")
    } catch let error as ClientError {
      #expect(error == .responseBodyTooLarge(maximumBytes: 4))
    }

    #expect(await httpClient.responseBodyReadCount == 1)
  }
#endif
