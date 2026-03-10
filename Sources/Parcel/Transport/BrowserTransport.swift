import Foundation
import HTTPTypes

#if arch(wasm32) && canImport(JavaScriptEventLoop) && canImport(JavaScriptKit)
  import JavaScriptEventLoop
  @preconcurrency import JavaScriptKit

  public struct BrowserTransport: Transport {
    private struct FetchContext {
      let responseObject: JSObject
      let abortState: AbortState
    }

    private final class AbortState: @unchecked Sendable {
      private let controller: JSObject
      private var timedOut = false
      private var timeoutHandle: JSValue?
      private var timeoutClosure: JSClosure?

      init(controller: JSObject) {
        self.controller = controller
      }

      deinit {
        clearTimeout()
      }

      var signal: JSValue {
        controller.signal
      }

      var didTimeOut: Bool {
        timedOut
      }

      func armTimeout(_ timeout: Duration) throws {
        guard let setTimeout = JSObject.global["setTimeout"].function else {
          throw ClientError.invalidJavaScriptContext
        }

        clearTimeout()

        let timeoutClosure = JSClosure { [weak self] _ in
          self?.timedOut = true
          self?.abort()
          return .undefined
        }
        self.timeoutClosure = timeoutClosure
        timeoutHandle = setTimeout(timeoutClosure, timeoutMilliseconds(timeout))
      }

      func abort() {
        clearTimeout()
        _ = controller["abort"]?()
      }

      private func clearTimeout() {
        if let timeoutHandle {
          _ = JSObject.global["clearTimeout"]?(timeoutHandle)
          self.timeoutHandle = nil
        }

        if let timeoutClosure {
          #if JAVASCRIPTKIT_WITHOUT_WEAKREFS
            timeoutClosure.release()
          #endif
          self.timeoutClosure = nil
        }
      }

      private func timeoutMilliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        let seconds = Double(components.seconds) * 1_000
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000
        return max(0, seconds + attoseconds)
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

    public func send(
      _ request: HTTPRequest,
      body: Data?,
      timeout: Duration?
    ) async throws -> (response: HTTPResponse, body: Data?, url: URL?) {
      let context = try await fetchResponseObject(
        for: request,
        body: body,
        timeout: timeout
      )
      let responseObject = context.responseObject
      let statusCode = statusCode(from: responseObject)
      let headers = readHeaders(from: responseObject)
      let url = responseURL(from: responseObject)
      let responseBody = try await readBody(
        from: responseObject,
        abortState: context.abortState
      )

      return (
        response: HTTPResponse(
          status: .init(code: statusCode),
          headerFields: headers
        ),
        body: responseBody,
        url: url,
      )
    }

    private func fetchResponseObject(
      for request: HTTPRequest,
      body: Data?,
      timeout: Duration?
    ) async throws -> FetchContext {
      Self.installExecutorIfNeeded()
      guard let fetch = JSObject.global.fetch.function,
        let objectConstructor = JSObject.global.Object.function,
        let arrayConstructor = JSObject.global.Array.function
      else {
        throw ClientError.invalidJavaScriptContext
      }

      let abortState = try makeAbortController()
      if let timeout {
        try abortState.armTimeout(timeout)
      }
      let options = objectConstructor.new()
      options["method"] = .string(request.method.rawValue)
      options["signal"] = abortState.signal

      if request.headerFields.isEmpty == false {
        let headers = arrayConstructor.new()
        for (index, field) in request.headerFields.enumerated() {
          let entry = arrayConstructor.new()
          entry[0] = .string(field.name.rawName)
          entry[1] = .string(field.value)
          headers[index] = .object(entry)
        }
        options["headers"] = .object(headers)
      }

      if let body, body.isEmpty == false {
        options["body"] = JSTypedArray<UInt8>(body).jsValue
      }

      guard let requestURL = request.url,
        let responsePromiseObject = fetch(requestURL.absoluteString, options).object,
        let responsePromise = JSPromise(responsePromiseObject)
      else {
        throw ClientError.invalidFetchResponse
      }

      let responseValue = try await resolvePromise(
        responsePromise,
        abortState: abortState
      )
      guard let responseObject = responseValue.object else {
        throw ClientError.invalidFetchResponse
      }

      return FetchContext(
        responseObject: responseObject,
        abortState: abortState
      )
    }

    private func readHeaders(from responseObject: JSObject) -> HTTPFields {
      guard let headersObject = responseObject.headers.object else {
        return .init()
      }

      var headers = HTTPFields()
      let collector = JSClosure { arguments in
        guard arguments.count >= 2,
          let value = arguments[0].string,
          let key = arguments[1].string,
          let fieldName = HTTPField.Name(key)
        else {
          return .undefined
        }

        headers.append(.init(name: fieldName, value: value))
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
      abortState: AbortState
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
        abortState: abortState,
        operation: .bytes
      )
      let bytesArray = uint8ArrayConstructor.new(arrayBuffer)
      return JSTypedArray<UInt8>(unsafelyWrapping: bytesArray)
        .withUnsafeBytes(Data.init(buffer:))
    }

    private func readTextBody(
      from responseObject: JSObject,
      abortState: AbortState
    ) async throws -> String? {
      guard let textPromiseObject = responseObject["text"]?().object,
        let textPromise = JSPromise(textPromiseObject)
      else {
        return nil
      }

      return try await resolvePromise(
        textPromise,
        abortState: abortState,
        operation: .text
      ).string
    }

    private func makeStatusError(
      from responseObject: JSObject,
      statusCode: Int,
      abortState: AbortState
    ) async throws -> ClientError {
      do {
        let body = try await readTextBody(
          from: responseObject,
          abortState: abortState
        )
        return .unsuccessfulStatusCode(statusCode, body: body)
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as ClientError where error == .timedOut {
        throw error
      } catch {
        return .unsuccessfulStatusCode(statusCode, body: nil)
      }
    }

    private func makeAbortController() throws -> AbortState {
      guard let abortControllerConstructor = JSObject.global.AbortController.function else {
        throw ClientError.invalidJavaScriptContext
      }

      return AbortState(
        controller: abortControllerConstructor.new()
      )
    }

    private func resolvePromise(
      _ promise: JSPromise,
      abortState: AbortState,
      operation: ClientError.ResponseBodyFailure.Operation? = nil
    ) async throws -> JSValue {
      do {
        return try await withTaskCancellationHandler {
          try Task.checkCancellation()
          let value = try await promise.value
          try Task.checkCancellation()
          return value
        } onCancel: {
          abortState.abort()
        }
      } catch is CancellationError {
        abortState.abort()
        throw CancellationError()
      } catch let error as JSException {
        if isAbortError(error) {
          if abortState.didTimeOut {
            throw ClientError.timedOut
          }
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

    private func responseURL(from responseObject: JSObject) -> URL? {
      responseObject.url.string.flatMap(URL.init(string:))
    }
  }
#endif
