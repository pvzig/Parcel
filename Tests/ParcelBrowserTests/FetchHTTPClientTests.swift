#if arch(wasm32)
    import Foundation
    import HTTPTypes
    import Testing

    @testable import Parcel

    enum FetchHTTPClientScenario: CaseIterable, Sendable {
        case boundedBody
        case plainTextBodyCoding
        case rawResponse
        case rejectsHeadBody
        case typedJSON
        case unsuccessfulStatus
    }

    @Test(.serialized, arguments: FetchHTTPClientScenario.allCases)
    func fetchHTTPClientIntegration(_ scenario: FetchHTTPClientScenario) async throws {
        let harness = try BrowserTestHarness()
        try harness.reset()

        switch scenario {
        case .boundedBody:
            try harness.configureResponse(statusCode: 200, bodyText: "hello")
            let client = Client(
                configuration: ClientConfiguration(maximumBufferedBodyBytes: 4)
            )

            do {
                let _: String = try await client.send(
                    .get(exampleStatusURL, bodyCoding: .plainText())
                )
                Issue.record("Expected the configured response-body limit to be enforced")
            } catch let error as ClientError {
                #expect(error == .responseBodyTooLarge(maximumBytes: 4))
            }

        case .plainTextBodyCoding:
            try harness.configureResponse(statusCode: 202, bodyText: "accepted")

            let response: String = try await Client().send(
                .post(
                    exampleGenerateURL,
                    body: "publish",
                    bodyCoding: .plainText()
                )
            )
            let request = try #require(harness.recordedRequests().first)

            #expect(response == "accepted")
            #expect(request.headers["accept"] == "text/plain")
            #expect(request.headers["content-type"] == "text/plain")
            #expect(request.bodyText == "publish")

        case .rawResponse:
            try harness.configureResponse(
                statusCode: 206,
                headers: ["content-type": "application/octet-stream"],
                bodyText: "part"
            )

            let response = try await Client().raw(
                HTTPRequest(method: .get, url: exampleStatusURL)
            )

            #expect(response.response.status.code == 206)
            #expect(response.response.headerFields[.contentType] == "application/octet-stream")
            #expect(response.body == Data("part".utf8))

        case .rejectsHeadBody:
            let client = Client()

            do {
                _ = try await client.raw(
                    HTTPRequest(method: .head, url: exampleStatusURL),
                    body: Data("payload".utf8)
                )
                Issue.record("Expected a HEAD request body to be rejected")
            } catch let error as ClientError {
                #expect(error == .requestBodyNotAllowed(.head))
            }

            #expect(try harness.recordedRequests().isEmpty)

        case .typedJSON:
            try harness.configureResponse(
                statusCode: 202,
                headers: ["etag": "abc123"],
                bodyText: #"{"statusUrl":"https://example.com/status"}"#
            )

            let response: Client.Response<GenerateAccepted> = try await Client().response(
                .post(
                    exampleGenerateURL,
                    body: GenerateRequest(pagePath: "/posts/example"),
                    headers: [.xTrace: "123"]
                )
            )
            let request = try #require(harness.recordedRequests().first)
            let requestBodyText = try #require(request.bodyText)
            let requestBody = try JSONDecoder().decode(
                GenerateRequest.self,
                from: Data(requestBodyText.utf8)
            )

            #expect(response.value == GenerateAccepted(statusURL: exampleStatusURL))
            #expect(response.response.status.code == 202)
            #expect(response.response.headerFields[.eTag] == "abc123")
            #expect(request.url == exampleGenerateURL)
            #expect(request.method == "POST")
            #expect(request.headers["accept"] == "application/json")
            #expect(request.headers["content-type"] == "application/json")
            #expect(request.headers["x-trace"] == "123")
            #expect(requestBody == GenerateRequest(pagePath: "/posts/example"))

        case .unsuccessfulStatus:
            try harness.configureResponse(statusCode: 503, bodyText: "unavailable")

            do {
                let _: GenerateAccepted = try await Client().send(
                    .get(exampleStatusURL)
                )
                Issue.record("Expected a non-success status to throw")
            } catch let error as ClientError {
                #expect(error == .unsuccessfulStatusCode(503, body: "unavailable"))
            }
        }
    }
#endif
