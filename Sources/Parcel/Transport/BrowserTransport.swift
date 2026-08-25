import HTTPTypes
import Synchronization

#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

#if arch(wasm32) && canImport(JavaScriptEventLoop) && canImport(JavaScriptKit)
  import JavaScriptEventLoop
  import JavaScriptKit

  public struct BrowserTransport: Transport {
    private enum BufferedRequestBodyOutcome: Sendable {
      case success(Data)
      case failure(any Error)
    }

    private actor AbortState {
      private let controller: JSRemote<JSObject>
      private let executor: JavaScriptEventLoop
      private var didTimeOut = false
      private var timer: JSTimer?

      nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
      }

      init(
        controller: JSRemote<JSObject>,
        executor: JavaScriptEventLoop
      ) {
        self.controller = controller
        self.executor = executor
      }

      func armTimeout(_ timeout: Duration) {
        timer = JSTimer(
          millisecondsDelay: max(0, timeout / .milliseconds(1))
        ) { [weak self] in
          Task {
            await self?.timeoutFired()
          }
        }
      }

      func abort() async {
        timer = nil
        await controller.withJSObject { controller in
          _ = controller["abort"]?()
        }
      }

      func complete() {
        timer = nil
      }

      func hasTimedOut() -> Bool {
        didTimeOut
      }

      private func timeoutFired() async {
        didTimeOut = true
        await abort()
      }
    }

    private actor ResponseBodyReader {
      private enum State: Sendable {
        case open
        case finished
        case cancelled
      }

      private let abortState: AbortState
      private let executor: JavaScriptEventLoop
      private let readerObject: JSObject
      private var lockReleased = false
      private var state = State.open

      nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
      }

      init(
        readerObject: JSObject,
        abortState: AbortState,
        executor: JavaScriptEventLoop
      ) {
        self.readerObject = readerObject
        self.abortState = abortState
        self.executor = executor
      }

      func nextChunk() async throws -> HTTPBody.ByteChunk? {
        guard state == .open else {
          return nil
        }

        do {
          try Task.checkCancellation()
          guard let readPromiseObject = readerObject["read"]?().object,
            let readPromise = JSPromise(readPromiseObject)
          else {
            throw ClientError.invalidResponseBody
          }

          let result = try await BrowserTransport.resolvePromise(
            readPromise,
            abortState: abortState
          ) { .responseBodyFailure(BrowserTransport.javaScriptError(from: $0)) }
          guard let resultObject = result.object else {
            throw ClientError.invalidResponseBody
          }

          if resultObject.done.boolean == true {
            await finish()
            return nil
          }

          guard let valueObject = resultObject.value.object,
            let uint8ArrayConstructor = JSObject.global.Uint8Array.object,
            valueObject.isInstanceOf(uint8ArrayConstructor)
          else {
            throw ClientError.invalidResponseBody
          }

          return JSUint8Array(unsafelyWrapping: valueObject)
            .withUnsafeBytes { ArraySlice($0) }
        } catch is CancellationError {
          await abortState.abort()
          await cancel()
          throw CancellationError()
        } catch {
          await cancel()
          throw error
        }
      }

      func cancel() async {
        guard state == .open else {
          return
        }

        state = .cancelled
        await abortState.complete()

        guard let cancelPromiseObject = readerObject["cancel"]?().object,
          let cancelPromise = JSPromise(cancelPromiseObject)
        else {
          releaseLock()
          return
        }

        do {
          _ = try await cancelPromise.value(isolation: self)
        } catch {
          // Cancellation is best-effort, but awaiting the rejection observes
          // it before the reader lock is released.
        }
        releaseLock()
      }

      private func finish() async {
        guard state == .open else {
          return
        }

        state = .finished
        releaseLock()
        await abortState.complete()
      }

      private func releaseLock() {
        guard lockReleased == false else {
          return
        }

        lockReleased = true
        _ = readerObject["releaseLock"]?()
      }
    }

    /// Cancels a response-body reader when the guard is released, unless `disarm()` recorded that
    /// the stream already reached end-of-stream.
    ///
    /// Two guards share one reader and deliberately have different lifetimes: the body's guard
    /// cancels a body dropped without ever being iterated, while a per-iterator guard cancels an
    /// abandoned iteration promptly, before the body itself is released.
    private final class ResponseBodyCancellationGuard: Sendable {
      let reader: ResponseBodyReader
      private let isDisarmed = Mutex(false)

      init(reader: ResponseBodyReader) {
        self.reader = reader
      }

      func disarm() {
        isDisarmed.withLock { $0 = true }
      }

      deinit {
        guard isDisarmed.withLock({ $0 == false }) else {
          return
        }

        let reader = reader
        Task {
          await reader.cancel()
        }
      }
    }

    private struct ResponseBodySequence: AsyncSequence, Sendable {
      typealias Element = HTTPBody.ByteChunk

      struct AsyncIterator: AsyncIteratorProtocol {
        // Retaining the body's guard keeps the reader alive for an iterator that outlives the
        // `HTTPBody` it came from.
        private let bodyGuard: ResponseBodyCancellationGuard
        private let iterationGuard: ResponseBodyCancellationGuard

        init(bodyGuard: ResponseBodyCancellationGuard) {
          self.bodyGuard = bodyGuard
          self.iterationGuard = .init(reader: bodyGuard.reader)
        }

        mutating func next() async throws -> Element? {
          let chunk = try await bodyGuard.reader.nextChunk()
          if chunk == nil {
            iterationGuard.disarm()
          }
          return chunk
        }
      }

      private let bodyGuard: ResponseBodyCancellationGuard

      init(reader: ResponseBodyReader) {
        self.bodyGuard = .init(reader: reader)
      }

      func makeAsyncIterator() -> AsyncIterator {
        .init(bodyGuard: bodyGuard)
      }
    }

    private actor BrowserRuntime {
      private let executor: JavaScriptEventLoop
      private let requestOptions: BrowserRequestOptions

      nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
      }

      init(
        executor: JavaScriptEventLoop,
        requestOptions: BrowserRequestOptions
      ) {
        self.executor = executor
        self.requestOptions = requestOptions
      }

      func send(
        _ request: HTTPRequest,
        body: Data?,
        timeout: Duration?
      ) async throws -> TransportResponse {
        guard let fetch = JSObject.global.fetch.function,
          let objectConstructor = JSObject.global.Object.function,
          let arrayConstructor = JSObject.global.Array.function,
          let abortControllerConstructor = JSObject.global.AbortController.function
        else {
          throw ClientError.invalidJavaScriptContext
        }

        try Task.checkCancellation()
        let controller = abortControllerConstructor.new()
        let options = objectConstructor.new()
        options["method"] = .string(request.method.rawValue)
        options["signal"] = controller.signal
        for entry in requestOptions.fetchInitEntries {
          options[entry.key] = .string(entry.value)
        }

        if request.headerFields.isEmpty == false {
          let headers = arrayConstructor.new()
          for (index, field) in request.headerFields.enumerated() {
            let entry = arrayConstructor.new()
            entry[0] = .string(field.name.rawName)
            entry[1] = .string(BrowserTransport.javaScriptHeaderValue(from: field))
            headers[index] = .object(entry)
          }
          options["headers"] = .object(headers)
        }

        if let body {
          options["body"] = JSUint8Array(body).jsValue
        }

        guard let requestURL = request.url else {
          throw ClientError.invalidRequestURL(request.path ?? "")
        }

        let abortState = AbortState(
          controller: JSRemote(controller),
          executor: executor
        )
        if let timeout {
          await abortState.armTimeout(timeout)
        }

        do {
          try Task.checkCancellation()
          guard let responsePromiseObject = fetch(requestURL.absoluteString, options).object,
            let responsePromise = JSPromise(responsePromiseObject)
          else {
            throw ClientError.invalidFetchResponse
          }

          let responseValue = try await BrowserTransport.resolvePromise(
            responsePromise,
            abortState: abortState
          ) { .fetchFailure(BrowserTransport.javaScriptError(from: $0)) }
          guard let responseObject = responseValue.object else {
            throw ClientError.invalidFetchResponse
          }

          let statusCode = try statusCode(from: responseObject)
          let headers = readHeaders(from: responseObject)
          let url = responseURL(from: responseObject)
          let body = try await makeBody(
            from: responseObject,
            headers: headers,
            abortState: abortState
          )

          return TransportResponse(
            response: HTTPResponse(
              status: .init(code: statusCode),
              headerFields: headers
            ),
            body: body,
            url: url
          )
        } catch {
          await abortState.complete()
          throw error
        }
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
            let fieldName = HTTPField.Name(key),
            let valueBytes = BrowserTransport.httpFieldValueBytes(from: value)
          else {
            return .undefined
          }

          headers.append(.init(name: fieldName, value: valueBytes))
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
      ) async throws -> HTTPBody? {
        guard let bodyObject = responseObject.body.object else {
          await abortState.complete()
          return nil
        }

        guard let readerObject = bodyObject["getReader"]?().object else {
          throw ClientError.invalidResponseBody
        }

        let reader = ResponseBodyReader(
          readerObject: readerObject,
          abortState: abortState,
          executor: executor
        )
        return HTTPBody(
          ResponseBodySequence(reader: reader),
          length: bodyLength(from: headers),
          iterationBehavior: .single
        )
      }

      private func bodyLength(from headers: HTTPFields) -> HTTPBody.Length {
        // Fetch streams decoded bytes, so an encoded transfer's Content-Length
        // does not describe the bytes this body will yield.
        if let contentEncoding = headers[.contentEncoding],
          contentEncoding.lowercased() != "identity"
        {
          return .unknown
        }

        guard let contentLength = headers[.contentLength],
          let length = Int64(contentLength)
        else {
          return .unknown
        }

        return .known(length)
      }

      private func statusCode(from responseObject: JSObject) throws -> Int {
        guard let status = responseObject.status.number,
          let code = Int(exactly: status),
          (0...999).contains(code)
        else {
          throw ClientError.invalidFetchResponse
        }

        return code
      }

      private func responseURL(from responseObject: JSObject) -> URL? {
        responseObject.url.string.flatMap(URL.init(string:))
      }
    }

    private let maximumBufferedRequestBodyBytes: Int
    private let runtime: BrowserRuntime?

    public static var isSupportedRuntime: Bool {
      let globalObject = JSObject.global
      let hasRuntimeGlobalScope =
        globalObject.window.object != nil
        || globalObject["self"].object != nil
      return hasRuntimeGlobalScope
        && globalObject.fetch.function != nil
        && globalObject.Object.function != nil
        && globalObject.Array.function != nil
        && globalObject.Promise.function != nil
        && globalObject.Uint8Array.object != nil
        && globalObject.AbortController.function != nil
        && globalObject["setTimeout"].function != nil
        && globalObject["clearTimeout"].function != nil
    }

    public init(
      maximumBufferedRequestBodyBytes: Int = HTTPBody.defaultMaximumCollectedBytes,
      requestOptions: BrowserRequestOptions = .init()
    ) {
      precondition(
        maximumBufferedRequestBodyBytes >= 0,
        "maximumBufferedRequestBodyBytes must be nonnegative"
      )
      self.maximumBufferedRequestBodyBytes = maximumBufferedRequestBodyBytes
      if Self.isSupportedRuntime {
        JavaScriptEventLoop.installGlobalExecutor()
        self.runtime = BrowserRuntime(
          executor: .shared,
          requestOptions: requestOptions
        )
      } else {
        self.runtime = nil
      }
    }

    public func send(
      _ request: HTTPRequest,
      body: HTTPBody?,
      timeout: Duration?
    ) async throws -> TransportResponse {
      try request.method.validateBodyAllowed(hasBody: body != nil)
      guard let runtime else {
        throw ClientError.unsupportedPlatform
      }

      try Task.checkCancellation()
      let clock = ContinuousClock()
      let deadline = timeout.map { clock.now.advanced(by: $0) }
      let bufferedBody = try await bufferedRequestBody(
        body,
        timeout: try remainingTimeout(until: deadline, clock: clock)
      )
      try Task.checkCancellation()

      return try await runtime.send(
        request,
        body: bufferedBody,
        timeout: try remainingTimeout(until: deadline, clock: clock)
      )
    }

    private func bufferedRequestBody(
      _ body: HTTPBody?,
      timeout: Duration?
    ) async throws -> Data? {
      guard let body else {
        return nil
      }

      let maxBytes = maximumBufferedRequestBodyBytes
      guard let timeout else {
        return try await body.collect(upTo: maxBytes)
      }

      // A task group cannot provide a hard deadline for a caller-supplied
      // iterator that ignores cancellation because the group waits for every
      // child before returning. Race unstructured tasks instead and cancel the
      // collector after the deadline; cooperative iterators still clean up
      // immediately, while a noncooperative iterator cannot hold up `send`.
      let (outcomes, continuation) = AsyncStream<BufferedRequestBodyOutcome>.makeStream(
        bufferingPolicy: .bufferingOldest(1)
      )
      let collectionTask = Task {
        do {
          continuation.yield(.success(try await body.collect(upTo: maxBytes)))
        } catch {
          continuation.yield(.failure(error))
        }
      }
      let timeoutTask = Task {
        do {
          try await Task.sleep(for: timeout)
          continuation.yield(.failure(ClientError.timedOut))
        } catch is CancellationError {
        } catch {
          continuation.yield(.failure(error))
        }
      }
      defer {
        collectionTask.cancel()
        timeoutTask.cancel()
        continuation.finish()
      }

      let outcome = await withTaskCancellationHandler {
        var iterator = outcomes.makeAsyncIterator()
        return await iterator.next()
      } onCancel: {
        collectionTask.cancel()
        timeoutTask.cancel()
        continuation.finish()
      }

      try Task.checkCancellation()
      guard let outcome else {
        throw CancellationError()
      }

      switch outcome {
      case .success(let data):
        return data
      case .failure(let error):
        throw error
      }
    }

    private func remainingTimeout(
      until deadline: ContinuousClock.Instant?,
      clock: ContinuousClock
    ) throws -> Duration? {
      guard let deadline else {
        return nil
      }

      let remaining = clock.now.duration(to: deadline)
      guard remaining > .zero else {
        throw ClientError.timedOut
      }
      return remaining
    }

    private static func javaScriptHeaderValue(from field: HTTPField) -> String {
      field.withUnsafeBytesOfValue { bytes in
        var value = String()
        value.unicodeScalars.reserveCapacity(bytes.count)
        for byte in bytes {
          value.unicodeScalars.append(UnicodeScalar(UInt32(byte))!)
        }
        return value
      }
    }

    private static func httpFieldValueBytes(from value: String) -> [UInt8]? {
      var bytes: [UInt8] = []
      bytes.reserveCapacity(value.unicodeScalars.count)
      for scalar in value.unicodeScalars {
        guard let byte = UInt8(exactly: scalar.value) else {
          return nil
        }
        bytes.append(byte)
      }
      return bytes
    }

    /// Awaits a JavaScript promise under the caller's actor isolation, mapping the ways it can
    /// fail onto Parcel's errors: task cancellation and an `AbortError` raised by an abort we
    /// requested both surface as `CancellationError`, an `AbortError` raised by the timeout timer
    /// surfaces as `ClientError.timedOut`, and any other rejection goes through `mapRejection`.
    private static func resolvePromise(
      _ promise: JSPromise,
      abortState: AbortState,
      isolation: isolated (any Actor)? = #isolation,
      mapRejection: (JSException) -> ClientError
    ) async throws -> JSValue {
      do {
        return try await withTaskCancellationHandler {
          try Task.checkCancellation()
          let value = try await promise.value(isolation: isolation)
          try Task.checkCancellation()
          return value
        } onCancel: {
          Task {
            await abortState.abort()
          }
        }
      } catch is CancellationError {
        await abortState.abort()
        throw CancellationError()
      } catch let error as JSException {
        guard isAbortError(error) else {
          throw mapRejection(error)
        }
        if await abortState.hasTimedOut() {
          throw ClientError.timedOut
        }
        throw CancellationError()
      }
    }

    private static func javaScriptError(
      from exception: JSException
    ) -> ClientError.JavaScriptError {
      .init(
        name: javaScriptErrorName(from: exception),
        message: javaScriptErrorMessage(from: exception),
        description: exception.description,
        stack: javaScriptErrorStack(from: exception)
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

  }
#endif
