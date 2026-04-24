#if canImport(FoundationEssentials)
  import FoundationEssentials
#else
  import Foundation
#endif

struct FormURLEncodedEncoder: Encoder {
  private final class Storage {
    var fields: [(name: String, value: String)] = []

    func append(name: String, value: String) {
      fields.append((name: name, value: value))
    }

    func serializedData() -> Data {
      let body =
        fields
        .map { Self.encodeComponent($0.name) + "=" + Self.encodeComponent($0.value) }
        .joined(separator: "&")
      return Data(body.utf8)
    }

    private static func encodeComponent(_ string: String) -> String {
      var encoded = ""
      encoded.reserveCapacity(string.utf8.count)

      for byte in string.utf8 {
        switch byte {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x2E, 0x5F, 0x7E:
          encoded.unicodeScalars.append(UnicodeScalar(byte))
        case 0x20:
          encoded.append("+")
        default:
          encoded.append("%")
          encoded.append(Self.hexCharacter(for: byte >> 4))
          encoded.append(Self.hexCharacter(for: byte & 0x0F))
        }
      }

      return encoded
    }

    private static func hexCharacter(for nibble: UInt8) -> Character {
      Character(UnicodeScalar(nibble < 10 ? nibble + 48 : nibble + 55))
    }
  }

  var codingPath: [any CodingKey]
  let userInfo: [CodingUserInfoKey: Any]

  private let storage: Storage
  private let fieldName: String?

  private init(
    storage: Storage = .init(),
    codingPath: [any CodingKey] = [],
    userInfo: [CodingUserInfoKey: Any] = [:],
    fieldName: String? = nil
  ) {
    self.storage = storage
    self.codingPath = codingPath
    self.userInfo = userInfo
    self.fieldName = fieldName
  }

  static func encode<Value: Encodable>(_ value: Value) throws -> Data {
    let encoder = Self()
    try value.encode(to: encoder)
    return encoder.storage.serializedData()
  }

  func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    KeyedEncodingContainer(KeyedContainer<Key>(encoder: self))
  }

  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    UnkeyedContainer(encoder: self)
  }

  func singleValueContainer() -> any SingleValueEncodingContainer {
    SingleValueContainer(encoder: self)
  }

  fileprivate func childEncoder(for key: some CodingKey) -> Self {
    Self(
      storage: storage,
      codingPath: codingPath + [key],
      userInfo: userInfo,
      fieldName: key.stringValue
    )
  }

  fileprivate func appendValue(_ value: String) throws {
    guard let fieldName else {
      throw EncodingError.invalidValue(
        value,
        .init(
          codingPath: codingPath,
          debugDescription:
            "FormURLEncodedBodyCodec only supports top-level keyed values."
        )
      )
    }

    storage.append(name: fieldName, value: value)
  }

  fileprivate func nestedKeyedContainerError() -> EncodingError {
    EncodingError.invalidValue(
      codingPath.last?.stringValue ?? "",
      .init(
        codingPath: codingPath,
        debugDescription:
          "FormURLEncodedBodyCodec does not support nested keyed containers."
      )
    )
  }
}

extension FormURLEncodedEncoder {
  private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [any CodingKey] { encoder.codingPath }

    let encoder: FormURLEncodedEncoder

    mutating func encodeNil(forKey key: Key) throws {}

    mutating func encode(_ value: Bool, forKey key: Key) throws {
      try encodeScalar(value ? "true" : "false", forKey: key)
    }

    mutating func encode(_ value: String, forKey key: Key) throws {
      try encodeScalar(value, forKey: key)
    }

    mutating func encode(_ value: Double, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: Int, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
      try encodeScalar(String(value), forKey: key)
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
      try ensureTopLevel()
      try value.encode(to: encoder.childEncoder(for: key))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
      keyedBy keyType: NestedKey.Type,
      forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
      encoder.childEncoder(for: key).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
      encoder.childEncoder(for: key).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
      encoder
    }

    mutating func superEncoder(forKey key: Key) -> any Encoder {
      encoder.childEncoder(for: key)
    }

    private func ensureTopLevel() throws {
      guard encoder.fieldName == nil else {
        throw encoder.nestedKeyedContainerError()
      }
    }

    private func encodeScalar(_ value: String, forKey key: Key) throws {
      try ensureTopLevel()
      try encoder.childEncoder(for: key).appendValue(value)
    }
  }

  private struct UnkeyedContainer: UnkeyedEncodingContainer {
    var codingPath: [any CodingKey] { encoder.codingPath }
    var count = 0

    let encoder: FormURLEncodedEncoder

    mutating func encodeNil() throws {
      count += 1
    }

    mutating func encode(_ value: Bool) throws {
      try encodeScalar(value ? "true" : "false")
    }

    mutating func encode(_ value: String) throws {
      try encodeScalar(value)
    }

    mutating func encode(_ value: Double) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: Float) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: Int) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: Int8) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: Int16) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: Int32) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: Int64) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: UInt) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: UInt8) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: UInt16) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: UInt32) throws {
      try encodeScalar(String(value))
    }

    mutating func encode(_ value: UInt64) throws {
      try encodeScalar(String(value))
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
      try ensureFieldName()
      try value.encode(to: encoder)
      count += 1
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
      keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
      encoder.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
      encoder.unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder {
      encoder
    }

    private mutating func encodeScalar(_ value: String) throws {
      try ensureFieldName()
      try encoder.appendValue(value)
      count += 1
    }

    private func ensureFieldName() throws {
      guard encoder.fieldName != nil else {
        throw EncodingError.invalidValue(
          codingPath.last?.stringValue ?? "",
          .init(
            codingPath: codingPath,
            debugDescription:
              "FormURLEncodedBodyCodec only supports arrays nested under a keyed value."
          )
        )
      }
    }
  }

  private struct SingleValueContainer: SingleValueEncodingContainer {
    var codingPath: [any CodingKey] { encoder.codingPath }

    let encoder: FormURLEncodedEncoder

    mutating func encodeNil() throws {}

    mutating func encode(_ value: Bool) throws {
      try encoder.appendValue(value ? "true" : "false")
    }

    mutating func encode(_ value: String) throws {
      try encoder.appendValue(value)
    }

    mutating func encode(_ value: Double) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: Float) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: Int) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: Int8) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: Int16) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: Int32) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: Int64) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: UInt) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: UInt8) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: UInt16) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: UInt32) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode(_ value: UInt64) throws {
      try encoder.appendValue(String(value))
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
      try value.encode(to: encoder)
    }
  }
}
