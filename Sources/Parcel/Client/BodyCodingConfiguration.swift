import HTTPTypes

public struct BodyCodingConfiguration: Sendable {
  public var codec: any BodyCodec
  public var requestContentType: String?
  public var accept: [String]

  public init(
    codec: any BodyCodec,
    requestContentType: String? = nil,
    accept: [String] = []
  ) {
    self.codec = codec
    self.requestContentType = requestContentType
    self.accept = accept
  }

  public static func json(
    codec: JSONBodyCodec = .init(),
    requestContentType: String? = "application/json",
    accept: [String] = ["application/json"]
  ) -> Self {
    Self(
      codec: codec,
      requestContentType: requestContentType,
      accept: accept
    )
  }

  public static func formURLEncoded(
    codec: FormURLEncodedBodyCodec = .init(),
    requestContentType: String? = "application/x-www-form-urlencoded",
    accept: [String] = ["application/x-www-form-urlencoded"]
  ) -> Self {
    Self(
      codec: codec,
      requestContentType: requestContentType,
      accept: accept
    )
  }

  public static func plainText(
    codec: PlainTextBodyCodec = .init(),
    requestContentType: String? = "text/plain",
    accept: [String] = ["text/plain"]
  ) -> Self {
    Self(
      codec: codec,
      requestContentType: requestContentType,
      accept: accept
    )
  }

  public static func rawData(
    codec: RawDataBodyCodec = .init(),
    requestContentType: String? = "application/octet-stream",
    accept: [String] = ["application/octet-stream"]
  ) -> Self {
    Self(
      codec: codec,
      requestContentType: requestContentType,
      accept: accept
    )
  }
}
