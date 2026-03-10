import Foundation

public final class HTTPBody: @unchecked Sendable, AsyncSequence {
  public typealias ByteChunk = ArraySlice<UInt8>
  public typealias Element = ByteChunk
  public static let defaultMaximumCollectedBytes = 2 * 1024 * 1024

  public enum IterationBehavior: Sendable {
    case single
    case multiple
  }

  public enum Length: Sendable, Equatable {
    case unknown
    case known(Int64)
  }

  public struct TooManyBytesError: Error, Equatable, Sendable {
    public let maxBytes: Int

    public init(maxBytes: Int) {
      self.maxBytes = maxBytes
    }
  }

  public struct TooManyIterationsError: Error, Equatable, Sendable {
    public init() {}
  }

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

  public let length: Length
  public let iterationBehavior: IterationBehavior

  private let sequence: AnyAsyncSequence
  private let lock = NSLock()
  private var iteratorCreated = false

  public init() {
    self.sequence = .init(EmptyAsyncSequence<ByteChunk>())
    self.length = .known(0)
    self.iterationBehavior = .multiple
  }

  public convenience init(_ data: Data) {
    self.init(
      ArraySlice(data),
      length: .known(Int64(data.count)),
      iterationBehavior: .multiple
    )
  }

  public convenience init(_ string: some StringProtocol & Sendable) {
    self.init(Data(string.utf8))
  }

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

  public convenience init(
    _ bytes: some Collection<UInt8> & Sendable
  ) {
    self.init(
      bytes,
      length: .known(Int64(bytes.count)),
      iterationBehavior: .multiple
    )
  }

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

  public func makeAsyncIterator() -> AsyncIterator {
    do {
      try markIteratorCreated()
      return .init(sequence.makeAsyncIterator())
    } catch {
      return .init(throwing: error)
    }
  }

  public func collect(
    upTo maxBytes: Int = HTTPBody.defaultMaximumCollectedBytes
  ) async throws -> Data {
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

    for try await chunk in self {
      let (newCount, overflow) = data.count.addingReportingOverflow(chunk.count)
      guard overflow == false, newCount <= maxBytes else {
        throw TooManyBytesError(maxBytes: maxBytes)
      }
      data.append(contentsOf: chunk)
    }

    return data
  }

  public func text(
    upTo maxBytes: Int = HTTPBody.defaultMaximumCollectedBytes
  ) async throws -> String {
    String(decoding: try await collect(upTo: maxBytes), as: UTF8.self)
  }

  private func markIteratorCreated() throws {
    lock.lock()
    defer {
      iteratorCreated = true
      lock.unlock()
    }

    guard iterationBehavior == .single else {
      return
    }

    if iteratorCreated {
      throw TooManyIterationsError()
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

private struct EmptyAsyncSequence<Element: Sendable>: AsyncSequence, Sendable {
  struct AsyncIterator: AsyncIteratorProtocol {
    mutating func next() async throws -> Element? {
      nil
    }
  }

  func makeAsyncIterator() -> AsyncIterator {
    .init()
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
