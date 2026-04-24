import HTTPTypes
import Synchronization

#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

#if arch(wasm32) && canImport(JavaScriptEventLoop) && canImport(JavaScriptKit)
  import JavaScriptEventLoop
  @preconcurrency import JavaScriptKit

  public struct BrowserTransport: Transport {
    private struct FetchContext {
      let responseObject: JSObject
      let abortState: AbortState
    }

    private final class ResponseBodyReader: @unchecked Sendable {
      private enum State: Sendable {
        case open
        case finished
        case cancelled
      }

      private let readerObject: JSObject
      private let abortState: AbortState
      private let state = Mutex(State.open)

      init(
        readerObject: JSObject,
        abortState: AbortState
      ) {
        self.readerObject = readerObject
        self.abortState = abortState
      }

      deinit {
        cancelIfNeeded()
      }

      func nextChunk() async throws -> HTTPBody.ByteChunk? {
        guard let readPromiseObject = readerObject["read"]?().object,
          let readPromise = JSPromise(readPromiseObject)
        else {
          throw ClientError.invalidResponseBody
        }

        let result = try await BrowserTransport.resolvePromise(
          readPromise,
          abortState: abortState,
          operation: .bytes
        )
        guard let resultObject = result.object else {
          throw ClientError.invalidResponseBody
        }

        if resultObject.done.boolean == true {
          finish()
          return nil
        }

        guard let valueObject = resultObject.value.object else {
          throw ClientError.invalidResponseBody
        }

        let chunk = JSTypedArray<UInt8>(unsafelyWrapping: valueObject)
          .withUnsafeBytes(Data.init(buffer:))
        return ArraySlice(chunk)
      }

      func finish() {
        state.withLock { state in
          guard state == .open else {
            return
          }

          _ = readerObject["releaseLock"]?()
          state = .finished
        }
      }

      private func cancelIfNeeded() {
        state.withLock { state in
          guard state == .open else {
            return
          }

          _ = readerObject["cancel"]?()
          state = .cancelled
        }
      }
    }

    private struct ResponseBodySequence: AsyncSequence, Sendable {
      typealias Element = HTTPBody.ByteChunk

      struct AsyncIterator: AsyncIteratorProtocol {
        private let reader: ResponseBodyReader

        init(reader: ResponseBodyReader) {
          self.reader = reader
        }

        mutating func next() async throws -> Element? {
          try await reader.nextChunk()
        }
      }

      private let reader: ResponseBodyReader

      init(reader: ResponseBodyReader) {
        self.reader = reader
      }

      func makeAsyncIterator() -> AsyncIterator {
        .init(reader: reader)
      }
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

    private let maximumBufferedRequestBodyBytes: Int

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

    public init(
      maximumBufferedRequestBodyBytes: Int = HTTPBody.defaultMaximumCollectedBytes
    ) {
      precondition(
        maximumBufferedRequestBodyBytes >= 0,
        "maximumBufferedRequestBodyBytes must be nonnegative"
      )
      self.maximumBufferedRequestBodyBytes = maximumBufferedRequestBodyBytes
      Self.installExecutorIfNeeded()
    }

    public func send(
      _ request: HTTPRequest,
      body: HTTPBody?,
      timeout: Duration?
    ) async throws -> TransportResponse {
      let context = try await fetchResponseObject(
        for: request,
        body: body,
        timeout: timeout
      )
      let responseObject = context.responseObject
      let statusCode = statusCode(from: responseObject)
      let headers = readHeaders(from: responseObject)
      let url = responseURL(from: responseObject)

      return TransportResponse(
        response: HTTPResponse(
          status: .init(code: statusCode),
          headerFields: headers
        ),
        body: try makeBody(
          from: responseObject,
          headers: headers,
          abortState: context.abortState
        ),
        url: url
      )
    }

    private func fetchResponseObject(
      for request: HTTPRequest,
      body: HTTPBody?,
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

      if let requestBody = try await bufferedRequestBody(body),
        requestBody.isEmpty == false
      {
        options["body"] = JSTypedArray<UInt8>(requestBody).jsValue
      }

      guard let requestURL = request.url,
        let responsePromiseObject = fetch(requestURL.absoluteString, options).object,
        let responsePromise = JSPromise(responsePromiseObject)
      else {
        throw ClientError.invalidFetchResponse
      }

      let responseValue = try await Self.resolvePromise(
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

    private func makeBody(
      from responseObject: JSObject,
      headers: HTTPFields,
      abortState: AbortState
    ) throws -> HTTPBody? {
      guard let bodyObject = responseObject.body.object else {
        return nil
      }

      guard let readerObject = bodyObject["getReader"]?().object else {
        throw ClientError.invalidResponseBody
      }

      return HTTPBody(
        ResponseBodySequence(
          reader: ResponseBodyReader(
            readerObject: readerObject,
            abortState: abortState
          )
        ),
        length: bodyLength(from: headers),
        iterationBehavior: .single
      )
    }

    private func bufferedRequestBody(_ body: HTTPBody?) async throws -> Data? {
      guard let body else {
        return nil
      }

      return try await body.collect(upTo: maximumBufferedRequestBodyBytes)
    }

    private func bodyLength(from headers: HTTPFields) -> HTTPBody.Length {
      guard let contentLength = headers[.contentLength],
        let length = Int64(contentLength)
      else {
        return .unknown
      }

      return .known(length)
    }

    private func makeAbortController() throws -> AbortState {
      guard let abortControllerConstructor = JSObject.global.AbortController.function else {
        throw ClientError.invalidJavaScriptContext
      }

      return AbortState(
        controller: abortControllerConstructor.new()
      )
    }

    private static func resolvePromise(
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

    private static func responseBodyFailure(
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

    private static func isAbortError(_ exception: JSException) -> Bool {
      javaScriptErrorName(from: exception) == "AbortError"
    }

    private static func javaScriptErrorName(from exception: JSException) -> String? {
      exception.thrownValue.object?.name.string
    }

    private static func javaScriptErrorMessage(from exception: JSException) -> String? {
      exception.thrownValue.object?.message.string
        ?? exception.thrownValue.string
    }

    private static func javaScriptErrorStack(from exception: JSException) -> String? {
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
