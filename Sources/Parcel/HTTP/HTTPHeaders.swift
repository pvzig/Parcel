public struct HTTPHeaders: Equatable, ExpressibleByDictionaryLiteral, Sendable, Sequence {
  private var storage: [(name: String, value: String)]

  public init() {
    storage = []
  }

  public init(_ dictionary: [String: String]) {
    storage = dictionary.keys.sorted().compactMap { name in
      guard let value = dictionary[name] else {
        return nil
      }
      return (name: name, value: value)
    }
  }

  public init<S: Sequence>(_ headers: S) where S.Element == (String, String) {
    storage = headers.map { (name: $0.0, value: $0.1) }
  }

  public init(dictionaryLiteral elements: (String, String)...) {
    storage = elements.map { (name: $0.0, value: $0.1) }
  }

  public var count: Int {
    storage.count
  }

  public var isEmpty: Bool {
    storage.isEmpty
  }

  public var firstValues: [String: String] {
    var values: [String: String] = [:]
    for header in storage
    where values.keys.contains(where: { Self.normalized($0) == Self.normalized(header.name) })
      == false
    {
      values[header.name] = header.value
    }
    return values
  }

  public subscript(_ name: String) -> String? {
    firstValue(for: name)
  }

  public func makeIterator() -> IndexingIterator<[(name: String, value: String)]> {
    storage.makeIterator()
  }

  public func contains(_ name: String) -> Bool {
    storage.contains { Self.normalized($0.name) == Self.normalized(name) }
  }

  public func firstValue(for name: String) -> String? {
    storage.first { Self.normalized($0.name) == Self.normalized(name) }?.value
  }

  public func values(for name: String) -> [String] {
    storage.compactMap { header in
      guard Self.normalized(header.name) == Self.normalized(name) else {
        return nil
      }
      return header.value
    }
  }

  public mutating func add(name: String, value: String) {
    storage.append((name: name, value: value))
  }

  public mutating func merge(overridingWith headers: HTTPHeaders) {
    let overriddenNames = Set(headers.storage.map { Self.normalized($0.name) })
    for name in overriddenNames {
      remove(normalizedName: name)
    }
    storage.append(contentsOf: headers.storage)
  }

  public mutating func remove(_ name: String) {
    remove(normalizedName: Self.normalized(name))
  }

  public mutating func set(_ name: String, value: String) {
    remove(name)
    add(name: name, value: value)
  }

  public static func == (lhs: HTTPHeaders, rhs: HTTPHeaders) -> Bool {
    lhs.normalizedValues == rhs.normalizedValues
  }

  private var normalizedValues: [String: [String]] {
    storage.reduce(into: [String: [String]]()) { values, header in
      values[Self.normalized(header.name), default: []].append(header.value)
    }
  }

  private mutating func remove(normalizedName: String) {
    storage.removeAll { header in
      Self.normalized(header.name) == normalizedName
    }
  }

  private static func normalized(_ name: String) -> String {
    name.lowercased()
  }
}
