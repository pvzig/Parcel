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
}
