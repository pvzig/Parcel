#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

struct FormURLEncodedDecoder: Decoder {
  var codingPath: [any CodingKey]
  let userInfo: [CodingUserInfoKey: Any]

  private let values: [String: [String]]
  private let fieldName: String?
  private let elementValue: String?

  init(
    values: [String: [String]],
    codingPath: [any CodingKey] = [],
    userInfo: [CodingUserInfoKey: Any] = [:],
    fieldName: String? = nil,
    elementValue: String? = nil
  ) {
    self.values = values
    self.codingPath = codingPath
    self.userInfo = userInfo
    self.fieldName = fieldName
    self.elementValue = elementValue
  }

  static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    try Value(
      from: Self(values: try parse(data))
    )
  }

  func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    guard fieldName == nil, elementValue == nil else {
      throw DecodingError.typeMismatch(
        [String: String].self,
        .init(
          codingPath: codingPath,
          debugDescription:
            "FormURLEncodedBodyCodec does not support nested keyed containers."
        )
      )
    }

    return KeyedDecodingContainer(KeyedContainer<Key>(decoder: self))
  }

  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    guard elementValue == nil else {
      throw DecodingError.typeMismatch(
        [String].self,
        .init(
          codingPath: codingPath,
          debugDescription: "Form field arrays cannot contain nested arrays."
        )
      )
    }

    guard let fieldName else {
      throw DecodingError.typeMismatch(
        [String].self,
        .init(
          codingPath: codingPath,
          debugDescription:
            "FormURLEncodedBodyCodec only supports arrays nested under a keyed value."
        )
      )
    }

    guard let fieldValues = values[fieldName] else {
      throw DecodingError.valueNotFound(
        [String].self,
        .init(
          codingPath: codingPath,
          debugDescription: "No form field named '\(fieldName)'."
        )
      )
    }

    return UnkeyedContainer(decoder: self, values: fieldValues)
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    if let elementValue {
      return SingleValueContainer(decoder: self, values: [elementValue])
    }

    guard let fieldName else {
      throw DecodingError.typeMismatch(
        String.self,
        .init(
          codingPath: codingPath,
          debugDescription:
            "FormURLEncodedBodyCodec only supports top-level keyed values."
        )
      )
    }

    guard let fieldValues = values[fieldName] else {
      throw DecodingError.valueNotFound(
        String.self,
        .init(
          codingPath: codingPath,
          debugDescription: "No form field named '\(fieldName)'."
        )
      )
    }

    return SingleValueContainer(decoder: self, values: fieldValues)
  }

  fileprivate func childDecoder(for key: some CodingKey) -> Self {
    Self(
      values: values,
      codingPath: codingPath + [key],
      userInfo: userInfo,
      fieldName: key.stringValue
    )
  }

  fileprivate func elementDecoder(for value: String, at index: Int) -> Self {
    Self(
      values: values,
      codingPath: codingPath + [IndexCodingKey(index: index)],
      userInfo: userInfo,
      elementValue: value
    )
  }

  fileprivate func keyNotFound(_ key: some CodingKey) -> DecodingError {
    DecodingError.keyNotFound(
      key,
      .init(
        codingPath: codingPath,
        debugDescription: "No form field named '\(key.stringValue)'."
      )
    )
  }

  private static func parse(_ data: Data) throws -> [String: [String]] {
    guard let body = String(data: data, encoding: .utf8) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: [],
          debugDescription: "FormURLEncodedBodyCodec expects UTF-8 body data."
        )
      )
    }

    guard body.isEmpty == false else {
      return [:]
    }

    var decodedValues: [String: [String]] = [:]

    for pair in body.split(separator: "&", omittingEmptySubsequences: false) {
      let segments = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let name = try decodeComponent(String(segments[0]))
      let value = try decodeComponent(segments.count == 2 ? String(segments[1]) : "")
      decodedValues[name, default: []].append(value)
    }

    return decodedValues
  }

  private static func decodeComponent(_ component: String) throws -> String {
    let bytes = Array(component.utf8)
    var decodedBytes: [UInt8] = []
    decodedBytes.reserveCapacity(bytes.count)

    var index = 0
    while index < bytes.count {
      switch bytes[index] {
      case 0x2B:
        decodedBytes.append(0x20)
        index += 1
      case 0x25:
        guard
          index + 2 < bytes.count,
          let upper = hexValue(for: bytes[index + 1]),
          let lower = hexValue(for: bytes[index + 2])
        else {
          throw DecodingError.dataCorrupted(
            .init(
              codingPath: [],
              debugDescription: "Invalid percent-encoded form field component."
            )
          )
        }

        decodedBytes.append((upper << 4) | lower)
        index += 3
      default:
        decodedBytes.append(bytes[index])
        index += 1
      }
    }

    guard let decoded = String(bytes: decodedBytes, encoding: .utf8) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: [],
          debugDescription: "Decoded form field component was not valid UTF-8."
        )
      )
    }

    return decoded
  }

  private static func hexValue(for byte: UInt8) -> UInt8? {
    switch byte {
    case 0x30...0x39:
      byte - 48
    case 0x41...0x46:
      byte - 55
    case 0x61...0x66:
      byte - 87
    default:
      nil
    }
  }
}

extension FormURLEncodedDecoder {
  private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    var codingPath: [any CodingKey] { decoder.codingPath }
    var allKeys: [Key] { decoder.values.keys.compactMap(Key.init(stringValue:)) }

    let decoder: FormURLEncodedDecoder

    func contains(_ key: Key) -> Bool {
      decoder.values[key.stringValue] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
      contains(key) == false
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
      try decodeValue(type, forKey: key)
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
      try decodeValue(type, forKey: key)
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
      guard contains(key) else {
        throw decoder.keyNotFound(key)
      }

      return try T(from: decoder.childDecoder(for: key))
    }

    func nestedContainer<NestedKey: CodingKey>(
      keyedBy type: NestedKey.Type,
      forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
      guard contains(key) else {
        throw decoder.keyNotFound(key)
      }

      return try decoder.childDecoder(for: key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
      guard contains(key) else {
        throw decoder.keyNotFound(key)
      }

      return try decoder.childDecoder(for: key).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
      decoder
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
      guard contains(key) else {
        throw decoder.keyNotFound(key)
      }

      return decoder.childDecoder(for: key)
    }

    private func decodeValue<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
      try decode(type, forKey: key)
    }
  }

  private struct UnkeyedContainer: UnkeyedDecodingContainer {
    var codingPath: [any CodingKey] { decoder.codingPath }
    let count: Int?

    let decoder: FormURLEncodedDecoder
    let values: [String]
    var currentIndex = 0

    init(decoder: FormURLEncodedDecoder, values: [String]) {
      self.decoder = decoder
      self.values = values
      self.count = values.count
    }

    var isAtEnd: Bool {
      currentIndex >= values.count
    }

    mutating func decodeNil() throws -> Bool {
      isAtEnd
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool {
      try decodeValue(type)
    }

    mutating func decode(_ type: String.Type) throws -> String {
      try decodeValue(type)
    }

    mutating func decode(_ type: Double.Type) throws -> Double {
      try decodeValue(type)
    }

    mutating func decode(_ type: Float.Type) throws -> Float {
      try decodeValue(type)
    }

    mutating func decode(_ type: Int.Type) throws -> Int {
      try decodeValue(type)
    }

    mutating func decode(_ type: Int8.Type) throws -> Int8 {
      try decodeValue(type)
    }

    mutating func decode(_ type: Int16.Type) throws -> Int16 {
      try decodeValue(type)
    }

    mutating func decode(_ type: Int32.Type) throws -> Int32 {
      try decodeValue(type)
    }

    mutating func decode(_ type: Int64.Type) throws -> Int64 {
      try decodeValue(type)
    }

    mutating func decode(_ type: UInt.Type) throws -> UInt {
      try decodeValue(type)
    }

    mutating func decode(_ type: UInt8.Type) throws -> UInt8 {
      try decodeValue(type)
    }

    mutating func decode(_ type: UInt16.Type) throws -> UInt16 {
      try decodeValue(type)
    }

    mutating func decode(_ type: UInt32.Type) throws -> UInt32 {
      try decodeValue(type)
    }

    mutating func decode(_ type: UInt64.Type) throws -> UInt64 {
      try decodeValue(type)
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
      try T(from: try nextDecoder())
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
      keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
      try nextDecoder().container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
      try nextDecoder().unkeyedContainer()
    }

    mutating func superDecoder() throws -> any Decoder {
      try nextDecoder()
    }

    private mutating func decodeValue<T: Decodable>(_ type: T.Type) throws -> T {
      try decode(type)
    }

    private mutating func nextDecoder() throws -> FormURLEncodedDecoder {
      guard isAtEnd == false else {
        throw DecodingError.valueNotFound(
          String.self,
          .init(
            codingPath: codingPath,
            debugDescription: "Unkeyed form value index \(currentIndex) was out of bounds."
          )
        )
      }

      let decoder = self.decoder.elementDecoder(for: values[currentIndex], at: currentIndex)
      currentIndex += 1
      return decoder
    }
  }

  private struct SingleValueContainer: SingleValueDecodingContainer {
    var codingPath: [any CodingKey] { decoder.codingPath }

    let decoder: FormURLEncodedDecoder
    let values: [String]

    func decodeNil() -> Bool {
      values.isEmpty
    }

    func decode(_ type: Bool.Type) throws -> Bool {
      let rawValue = try scalarValue()

      switch rawValue.lowercased() {
      case "true", "1":
        return true
      case "false", "0":
        return false
      default:
        throw DecodingError.typeMismatch(
          type,
          .init(
            codingPath: codingPath,
            debugDescription:
              "Expected a boolean-compatible form field value but found '\(rawValue)'."
          )
        )
      }
    }

    func decode(_ type: String.Type) throws -> String {
      try scalarValue()
    }

    func decode(_ type: Double.Type) throws -> Double {
      try parse(type)
    }

    func decode(_ type: Float.Type) throws -> Float {
      try parse(type)
    }

    func decode(_ type: Int.Type) throws -> Int {
      try parse(type)
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
      try parse(type)
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
      try parse(type)
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
      try parse(type)
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
      try parse(type)
    }

    func decode(_ type: UInt.Type) throws -> UInt {
      try parse(type)
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
      try parse(type)
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
      try parse(type)
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
      try parse(type)
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
      try parse(type)
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
      try T(from: decoder)
    }

    private func scalarValue() throws -> String {
      guard let value = values.first else {
        throw DecodingError.valueNotFound(
          String.self,
          .init(
            codingPath: codingPath,
            debugDescription: "Expected a form field value."
          )
        )
      }

      guard values.count == 1 else {
        throw DecodingError.typeMismatch(
          String.self,
          .init(
            codingPath: codingPath,
            debugDescription:
              "Expected a single form field value but found \(values.count) values."
          )
        )
      }

      return value
    }

    private func parse<T>(_ type: T.Type) throws -> T where T: LosslessStringConvertible {
      let rawValue = try scalarValue()

      guard let value = T(rawValue) else {
        throw DecodingError.typeMismatch(
          type,
          .init(
            codingPath: codingPath,
            debugDescription:
              "Could not convert form field value '\(rawValue)' to \(String(describing: type))."
          )
        )
      }

      return value
    }
  }

  private struct IndexCodingKey: CodingKey {
    let intValue: Int?
    let stringValue: String

    init(index: Int) {
      intValue = index
      stringValue = String(index)
    }

    init?(intValue: Int) {
      self.init(index: intValue)
    }

    init?(stringValue: String) {
      guard let index = Int(stringValue) else {
        return nil
      }

      self.init(index: index)
    }
  }
}
