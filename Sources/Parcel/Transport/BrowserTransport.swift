import Foundation

#if arch(wasm32) && canImport(JavaScriptEventLoop) && canImport(JavaScriptKit)
  import JavaScriptEventLoop
  @preconcurrency import JavaScriptKit

  public struct BrowserTransport: ResponseDecodingTransport {
    private struct FetchContext {
      let responseObject: JSObject
      let abortController: AbortControllerHandle
    }

    private final class AbortControllerHandle: @unchecked Sendable {
      private let controller: JSObject

      init(controller: JSObject) {
        self.controller = controller
      }

      var signal: JSValue {
        controller.signal
      }

      func abort() {
        _ = controller["abort"]?()
      }
    }

    public static var isSupportedRuntime: Bool {
      let globalObject = JSObject.global
      let hasRuntimeGlobalScope =
        globalObject.window.object != nil
        || globalObject["self"].object != nil
      return hasRuntimeGlobalScope
        && globalObject.fetch.function != nil
        && globalObject.Object.function != nil
        && globalObject.Uint8Array.object != nil
        && globalObject.AbortController.function != nil
    }

    public init() {
      Self.installExecutorIfNeeded()
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
      let context = try await fetchResponseObject(for: request)
      let responseObject = context.responseObject
      let statusCode = statusCode(from: responseObject)
      let headers = readHeaders(from: responseObject)
      let url = responseURL(from: responseObject)
      let body = try await readBody(
        from: responseObject,
        abortController: context.abortController
      )

      return HTTPResponse(
        statusCode: statusCode,
        headers: headers,
        url: url,
        body: body
      )
    }

    public func sendResponse<Response: Decodable>(
      _ request: HTTPRequest,
      expecting responseType: Response.Type
    ) async throws -> DecodedResponse<Response> {
      let context = try await fetchResponseObject(for: request)
      let responseObject = context.responseObject
      let statusCode = statusCode(from: responseObject)
      let headers = readHeaders(from: responseObject)
      let url = responseURL(from: responseObject)
      guard (200..<300).contains(statusCode) else {
        throw try await makeStatusError(
          from: responseObject,
          statusCode: statusCode,
          abortController: context.abortController
        )
      }

      let response = HTTPResponse(
        statusCode: statusCode,
        headers: headers,
        url: url
      )

      if responseType == EmptyResponse.self,
        let emptyResponse = EmptyResponse() as? Response
      {
        return DecodedResponse(value: emptyResponse, response: response)
      }

      let jsonValue = try await readJSONValue(
        from: responseObject,
        abortController: context.abortController
      )
      let value = try JSValueDecoder().decode(responseType, from: jsonValue)
      return DecodedResponse(value: value, response: response)
    }

    private func fetchResponseObject(for request: HTTPRequest) async throws -> FetchContext {
      Self.installExecutorIfNeeded()
      guard let fetch = JSObject.global.fetch.function,
        let objectConstructor = JSObject.global.Object.function
      else {
        throw ClientError.invalidJavaScriptContext
      }

      let abortController = try makeAbortController()
      let options = objectConstructor.new()
      options["method"] = .string(request.method.rawValue)
      options["signal"] = abortController.signal

      if request.headers.isEmpty == false {
        let headers = objectConstructor.new()
        for (name, value) in request.headers {
          headers[name] = .string(value)
        }
        options["headers"] = .object(headers)
      }

      if let body = request.body {
        options["body"] = JSTypedArray<UInt8>(body).jsValue
      }

      guard let responsePromiseObject = fetch(request.url, options).object,
        let responsePromise = JSPromise(responsePromiseObject)
      else {
        throw ClientError.invalidFetchResponse
      }

      let responseValue = try await resolvePromise(
        responsePromise,
        abortController: abortController
      )
      guard let responseObject = responseValue.object else {
        throw ClientError.invalidFetchResponse
      }

      return FetchContext(
        responseObject: responseObject,
        abortController: abortController
      )
    }

    private func readHeaders(from responseObject: JSObject) -> [String: String] {
      guard let headersObject = responseObject.headers.object else {
        return [:]
      }

      var headers: [String: String] = [:]
      let collector = JSClosure { arguments in
        guard arguments.count >= 2,
          let value = arguments[0].string,
          let key = arguments[1].string
        else {
          return .undefined
        }

        headers[key] = value
        return .undefined
      }
      #if JAVASCRIPTKIT_WITHOUT_WEAKREFS
        defer {
          collector.release()
        }
      #endif

      _ = headersObject["forEach"]?(collector)
      return headers
    }

    private func readBody(
      from responseObject: JSObject,
      abortController: AbortControllerHandle
    ) async throws -> Data? {
      guard let uint8ArrayConstructor = JSObject.global.Uint8Array.object else {
        throw ClientError.invalidJavaScriptContext
      }

      guard let arrayBufferPromiseObject = responseObject["arrayBuffer"]?().object,
        let arrayBufferPromise = JSPromise(arrayBufferPromiseObject)
      else {
        throw ClientError.invalidResponseBody
      }

      let arrayBuffer = try await resolvePromise(
        arrayBufferPromise,
        abortController: abortController,
        operation: .bytes
      )
      let bytesArray = uint8ArrayConstructor.new(arrayBuffer)
      return JSTypedArray<UInt8>(unsafelyWrapping: bytesArray)
        .withUnsafeBytes(Data.init(buffer:))
    }

    private func readJSONValue(
      from responseObject: JSObject,
      abortController: AbortControllerHandle
    ) async throws -> JSValue {
      guard let jsonPromiseObject = responseObject["json"]?().object,
        let jsonPromise = JSPromise(jsonPromiseObject)
      else {
        throw ClientError.invalidResponseBody
      }

      return try await resolvePromise(
        jsonPromise,
        abortController: abortController,
        operation: .json
      )
    }

    private func readTextBody(
      from responseObject: JSObject,
      abortController: AbortControllerHandle
    ) async throws -> String? {
      guard let textPromiseObject = responseObject["text"]?().object,
        let textPromise = JSPromise(textPromiseObject)
      else {
        return nil
      }

      return try await resolvePromise(
        textPromise,
        abortController: abortController,
        operation: .text
      ).string
    }

    private func makeStatusError(
      from responseObject: JSObject,
      statusCode: Int,
      abortController: AbortControllerHandle
    ) async throws -> ClientError {
      do {
        let body = try await readTextBody(
          from: responseObject,
          abortController: abortController
        )
        return .unsuccessfulStatusCode(statusCode, body: body)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        return .unsuccessfulStatusCode(statusCode, body: nil)
      }
    }

    private func makeAbortController() throws -> AbortControllerHandle {
      guard let abortControllerConstructor = JSObject.global.AbortController.function else {
        throw ClientError.invalidJavaScriptContext
      }

      return AbortControllerHandle(
        controller: abortControllerConstructor.new()
      )
    }

    private func resolvePromise(
      _ promise: JSPromise,
      abortController: AbortControllerHandle,
      operation: ClientError.ResponseBodyFailure.Operation? = nil
    ) async throws -> JSValue {
      do {
        return try await withTaskCancellationHandler {
          try Task.checkCancellation()
          let value = try await promise.value
          try Task.checkCancellation()
          return value
        } onCancel: {
          abortController.abort()
        }
      } catch is CancellationError {
        abortController.abort()
        throw CancellationError()
      } catch let error as JSException {
        if isAbortError(error) {
          throw CancellationError()
        }
        if let operation {
          throw responseBodyFailure(from: error, operation: operation)
        }
        throw error
      }
    }

    private func responseBodyFailure(
      from exception: JSException,
      operation: ClientError.ResponseBodyFailure.Operation
    ) -> ClientError {
      .responseBodyFailure(
        .init(
          operation: operation,
          javaScriptError: .init(
            name: javaScriptErrorName(from: exception),
            message: javaScriptErrorMessage(from: exception),
            description: exception.description,
            stack: javaScriptErrorStack(from: exception)
          )
        )
      )
    }

    private func isAbortError(_ exception: JSException) -> Bool {
      javaScriptErrorName(from: exception) == "AbortError"
    }

    private func javaScriptErrorName(from exception: JSException) -> String? {
      exception.thrownValue.object?.name.string
    }

    private func javaScriptErrorMessage(from exception: JSException) -> String? {
      exception.thrownValue.object?.message.string
        ?? exception.thrownValue.string
    }

    private func javaScriptErrorStack(from exception: JSException) -> String? {
      exception.stack
        ?? exception.thrownValue.object?.stack.string
    }

    private static func installExecutorIfNeeded() {
      guard isSupportedRuntime else {
        return
      }

      JavaScriptEventLoop.installGlobalExecutor()
    }

    private func statusCode(from responseObject: JSObject) -> Int {
      Int(responseObject.status.number ?? -1)
    }

    private func responseURL(from responseObject: JSObject) -> String? {
      responseObject.url.string
    }
  }
#else
  public struct BrowserTransport: ResponseDecodingTransport {
    public static let isSupportedRuntime = false

    public init() {}

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
      throw ClientError.unsupportedPlatform
    }

    public func sendResponse<Response: Decodable>(
      _ request: HTTPRequest,
      expecting responseType: Response.Type
    ) async throws -> DecodedResponse<Response> {
      throw ClientError.unsupportedPlatform
    }
  }
#endif
