import Synchronization

#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

/// An async stream of body bytes for a request or a response.
///
/// A body is either buffered — created from `Data`, a `String`, or a byte collection, and safe to
/// iterate repeatedly — or streamed, created from an `AsyncSequence` such as a browser
/// `ReadableStream`. Streamed bodies are usually `.single`: iterating one a second time throws
/// `TooManyIterationsError`, so `collect(upTo:)` and `text(upTo:)` can only be called once.
///
/// `Client.send` collects the response body itself, so most callers meet `HTTPBody` only through
/// `Client.raw`.
public final class HTTPBody: Sendable, AsyncSequence {
  /// A single chunk of body bytes, as yielded by iteration.
  public typealias ByteChunk = ArraySlice<UInt8>
  public typealias Element = ByteChunk

  /// The 2 MiB cap `collect(upTo:)` and `text(upTo:)` apply when the caller does not pass one.
  public static let defaultMaximumCollectedBytes = 2 * 1024 * 1024

  /// How many times a body's bytes can be iterated.
  public enum IterationBehavior: Sendable {
    /// The bytes can be consumed only once; a second iterator throws `TooManyIterationsError`.
    case single
    /// The bytes are buffered and can be iterated any number of times.
    case multiple
  }

  /// The number of bytes a body will yield, when that is known up front.
  public enum Length: Sendable, Equatable {
    /// The length is not known, typically because the transfer is chunked or content-encoded.
    case unknown
    /// The body will yield exactly this many bytes.
    case known(Int64)
  }

  /// Thrown when a body carries more bytes than the caller's limit allows.
  public struct TooManyBytesError: Error, Equatable, Sendable {
    /// The limit that was exceeded.
    public let maxBytes: Int

    public init(maxBytes: Int) {
      self.maxBytes = maxBytes
    }
  }

  /// Thrown when a `.single` body is iterated more than once.
  public struct TooManyIterationsError: Error, Equatable, Sendable {
    public init() {}
  }

  /// An iterator over a body's byte chunks.
  public struct AsyncIterator: AsyncIteratorProtocol {
    private var iterator: AnyAsyncIterator

    fileprivate init(_ iterator: AnyAsyncIterator) {
      self.iterator = iterator
    }

    fileprivate init(throwing error: any Error) {
      self.iterator = .init(throwing: error)
    }

    public mutating func next() async throws -> Element? {
      try await iterator.next()
    }
  }

  /// The number of bytes this body will yield, if known.
  public let length: Length

  /// Whether this body's bytes can be iterated more than once.
  public let iterationBehavior: IterationBehavior

  private let sequence: AnyAsyncSequence
  private let iteratorCreated = Mutex(false)

  /// Creates an empty body of known zero length.
  public init() {
    self.sequence = .init(WrappedSyncSequence<[ByteChunk]>(sequence: []))
    self.length = .known(0)
    self.iterationBehavior = .multiple
  }

  /// Creates a buffered body from `data`.
  public convenience init(_ data: Data) {
    self.init(
      ArraySlice(data),
      length: .known(Int64(data.count)),
      iterationBehavior: .multiple
    )
  }

  /// Creates a buffered body from the UTF-8 bytes of `string`.
  public convenience init(_ string: some StringProtocol & Sendable) {
    self.init(Data(string.utf8))
  }

  /// Creates a body from a byte collection with an explicit length and iteration behavior.
  public convenience init(
    _ bytes: some Collection<UInt8> & Sendable,
    length: Length,
    iterationBehavior: IterationBehavior
  ) {
    self.init(
      AnyAsyncSequence(WrappedSyncSequence(sequence: [ArraySlice(bytes)])),
      length: length,
      iterationBehavior: iterationBehavior
    )
  }

  /// Creates a buffered body from a byte collection, inferring its length.
  public convenience init(
    _ bytes: some Collection<UInt8> & Sendable
  ) {
    self.init(
      bytes,
      length: .known(Int64(bytes.count)),
      iterationBehavior: .multiple
    )
  }

  /// Creates a single-iteration body that streams chunks from `stream`.
  public convenience init(
    _ stream: AsyncThrowingStream<ByteChunk, any Error>,
    length: Length
  ) {
    self.init(
      AnyAsyncSequence(stream),
      length: length,
      iterationBehavior: .single
    )
  }

  /// Creates a single-iteration body that streams chunks from `stream`.
  public convenience init(
    _ stream: AsyncStream<ByteChunk>,
    length: Length
  ) {
    self.init(
      AnyAsyncSequence(stream),
      length: length,
      iterationBehavior: .single
    )
  }

  /// Creates a body backed by an async sequence of byte chunks.
  public convenience init<Bytes: AsyncSequence>(
    _ sequence: Bytes,
    length: Length,
    iterationBehavior: IterationBehavior
  ) where Bytes: Sendable, Bytes.Element == ByteChunk {
    self.init(
      AnyAsyncSequence(sequence),
      length: length,
      iterationBehavior: iterationBehavior
    )
  }

  /// Creates a body backed by an async sequence of byte sequences, mapping each to a chunk.
  public convenience init<Bytes: AsyncSequence>(
    _ sequence: Bytes,
    length: Length,
    iterationBehavior: IterationBehavior
  ) where Bytes: Sendable, Bytes.Element: Sequence & Sendable, Bytes.Element.Element == UInt8 {
    self.init(
      AnyAsyncSequence(
        BodyChunkMappingSequence(sequence: sequence)
      ),
      length: length,
      iterationBehavior: iterationBehavior
    )
  }

  private init(
    _ sequence: AnyAsyncSequence,
    length: Length,
    iterationBehavior: IterationBehavior
  ) {
    self.sequence = sequence
    self.length = length
    self.iterationBehavior = iterationBehavior
  }

  /// Returns an iterator over the body's byte chunks.
  ///
  /// A `.single` body returns an iterator that throws `TooManyIterationsError` from its first
  /// `next()` call if the body has already been iterated.
  public func makeAsyncIterator() -> AsyncIterator {
    do {
      try markIteratorCreated()
      return .init(sequence.makeAsyncIterator())
    } catch {
      return .init(throwing: error)
    }
  }

  /// Buffers the whole body in memory.
  ///
  /// - Parameter maxBytes: The most bytes to buffer. Pass `.max` only for bodies whose size you
  ///   control; the default guards against a server streaming an unbounded response.
  /// - Throws: `TooManyBytesError` if the body exceeds `maxBytes`, `TooManyIterationsError` if a
  ///   `.single` body was already consumed, or `CancellationError` if the task is cancelled.
  public func collect(
    upTo maxBytes: Int = HTTPBody.defaultMaximumCollectedBytes
  ) async throws -> Data {
    try Task.checkCancellation()

    if case .known(let knownBytes) = length,
      knownBytes > maxBytes
    {
      throw TooManyBytesError(maxBytes: maxBytes)
    }

    var data = Data()
    if case .known(let knownBytes) = length,
      let capacity = Int(exactly: knownBytes)
    {
      data.reserveCapacity(capacity)
    }

    var chunksUntilYield = 64
    for try await chunk in self {
      try Task.checkCancellation()
      let (newCount, overflow) = data.count.addingReportingOverflow(chunk.count)
      guard overflow == false, newCount <= maxBytes else {
        throw TooManyBytesError(maxBytes: maxBytes)
      }
      data.append(contentsOf: chunk)

      chunksUntilYield -= 1
      if chunksUntilYield == 0 {
        await Task.yield()
        chunksUntilYield = 64
      }
    }

    return data
  }

  /// Buffers the whole body and decodes it as UTF-8, replacing any ill-formed bytes.
  ///
  /// - Parameter maxBytes: The most bytes to buffer, as in `collect(upTo:)`.
  public func text(
    upTo maxBytes: Int = HTTPBody.defaultMaximumCollectedBytes
  ) async throws -> String {
    String(decoding: try await collect(upTo: maxBytes), as: UTF8.self)
  }

  private func markIteratorCreated() throws {
    try iteratorCreated.withLock { iteratorCreated in
      guard iterationBehavior == .single else {
        return
      }

      if iteratorCreated {
        throw TooManyIterationsError()
      }

      iteratorCreated = true
    }
  }
}

private struct AnyAsyncIterator: AsyncIteratorProtocol {
  private let nextImpl: () async throws -> HTTPBody.ByteChunk?

  init<Iterator: AsyncIteratorProtocol>(_ iterator: Iterator)
  where Iterator.Element == HTTPBody.ByteChunk {
    var iterator = iterator
    self.nextImpl = {
      try await iterator.next()
    }
  }

  init(throwing error: any Error) {
    self.nextImpl = {
      throw error
    }
  }

  mutating func next() async throws -> HTTPBody.ByteChunk? {
    try await nextImpl()
  }
}

private struct AnyAsyncSequence: AsyncSequence, Sendable {
  typealias Element = HTTPBody.ByteChunk
  typealias AsyncIterator = AnyAsyncIterator

  private let makeIteratorImpl: @Sendable () -> AnyAsyncIterator

  init<Sequence: AsyncSequence>(_ sequence: Sequence)
  where Sequence: Sendable, Sequence.Element == HTTPBody.ByteChunk {
    self.makeIteratorImpl = {
      .init(sequence.makeAsyncIterator())
    }
  }

  func makeAsyncIterator() -> AnyAsyncIterator {
    makeIteratorImpl()
  }
}

private struct WrappedSyncSequence<Sequence: Swift.Sequence & Sendable>: AsyncSequence, Sendable
where Sequence.Element: Sendable {
  typealias Element = Sequence.Element

  struct AsyncIterator: AsyncIteratorProtocol {
    private var iterator: any IteratorProtocol<Element>

    init(iterator: any IteratorProtocol<Element>) {
      self.iterator = iterator
    }

    mutating func next() async throws -> Element? {
      iterator.next()
    }
  }

  let sequence: Sequence

  func makeAsyncIterator() -> AsyncIterator {
    .init(iterator: sequence.makeIterator())
  }
}

private struct BodyChunkMappingSequence<Upstream: AsyncSequence & Sendable>: AsyncSequence, Sendable
where Upstream.Element: Sequence & Sendable, Upstream.Element.Element == UInt8 {
  typealias Element = HTTPBody.ByteChunk

  struct AsyncIterator: AsyncIteratorProtocol {
    private var iterator: Upstream.AsyncIterator

    init(iterator: Upstream.AsyncIterator) {
      self.iterator = iterator
    }

    mutating func next() async throws -> Element? {
      guard let element = try await iterator.next() else {
        return nil
      }

      return ArraySlice(element)
    }
  }

  let sequence: Upstream

  func makeAsyncIterator() -> AsyncIterator {
    .init(iterator: sequence.makeAsyncIterator())
  }
}
