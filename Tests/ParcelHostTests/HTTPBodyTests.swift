#if !arch(wasm32)
  import Foundation
  import Testing

  @testable import Parcel

  @Test func bufferedHTTPBodyCanBeCollectedMultipleTimes() async throws {
    let body = HTTPBody("hello")

    #expect(try await body.collect() == Data("hello".utf8))
    #expect(try await body.collect() == Data("hello".utf8))
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
#endif
