#if !arch(wasm32)
  import Foundation
  import Testing

  @testable import Parcel

  @Test func bufferedHTTPBodyCanBeCollectedMultipleTimes() async throws {
    let body = HTTPBody("hello")

    #expect(try await body.collect() == Data("hello".utf8))
    #expect(try await body.collect() == Data("hello".utf8))
  }

  @Test func emptyHTTPBodyUsesKnownZeroLengthAndSupportsMultipleIterations() async throws {
    let body = HTTPBody()

    #expect(body.length == .known(0))
    #expect(try await body.collect() == Data())
    #expect(try await body.collect() == Data())
  }

  @Test func byteCollectionHTTPBodyInfersLength() async throws {
    let body = HTTPBody([0x00, 0x7F, 0xFF])

    #expect(body.length == .known(3))
    #expect(try await body.collect() == Data([0x00, 0x7F, 0xFF]))
  }

  @Test func genericByteSequenceHTTPBodyMapsElementsToChunks() async throws {
    let stream = AsyncStream<[UInt8]> { continuation in
      continuation.yield([0x01, 0x02])
      continuation.yield([0x03])
      continuation.finish()
    }
    let body = HTTPBody(
      stream,
      length: .known(3),
      iterationBehavior: .single
    )

    #expect(try await body.collect() == Data([0x01, 0x02, 0x03]))
  }

  @Test func singleIterationHTTPBodyRejectsSecondCollection() async throws {
    let body = HTTPBody(
      AsyncStream<HTTPBody.ByteChunk> { continuation in
        continuation.yield(ArraySlice(Data("hello".utf8)))
        continuation.finish()
      },
      length: .known(5)
    )

    #expect(try await body.collect() == Data("hello".utf8))

    do {
      _ = try await body.collect()
      Issue.record("Expected second collection to throw")
    } catch let error as HTTPBody.TooManyIterationsError {
      #expect(error == .init())
    }
  }

  @Test func httpBodyCollectEnforcesMaximumByteLimit() async throws {
    let body = HTTPBody("hello")

    do {
      _ = try await body.collect(upTo: 4)
      Issue.record("Expected body collection to enforce byte limit")
    } catch let error as HTTPBody.TooManyBytesError {
      #expect(error == .init(maxBytes: 4))
    }
  }

  @Test func httpBodyCollectUsesASafeDefaultMaximumByteLimit() async throws {
    let body = HTTPBody(
      Data(
        repeating: 0x61,
        count: HTTPBody.defaultMaximumCollectedBytes + 1
      )
    )

    do {
      _ = try await body.collect()
      Issue.record("Expected body collection to enforce the default byte limit")
    } catch let error as HTTPBody.TooManyBytesError {
      #expect(error == .init(maxBytes: HTTPBody.defaultMaximumCollectedBytes))
    }
  }

  @Test func httpBodyTextCollectsUTF8() async throws {
    let body = HTTPBody("hello")

    #expect(try await body.text() == "hello")
  }

  @Test func httpBodyCollectionCooperatesWithCancellationBetweenChunks() async {
    struct InfiniteChunks: AsyncSequence, Sendable {
      typealias Element = [UInt8]

      struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async -> [UInt8]? {
          [0x61]
        }
      }

      func makeAsyncIterator() -> AsyncIterator {
        .init()
      }
    }

    let body = HTTPBody(
      InfiniteChunks(),
      length: .unknown,
      iterationBehavior: .single
    )
    let task = Task {
      try await body.collect(upTo: .max)
    }
    task.cancel()

    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
  }
#endif
