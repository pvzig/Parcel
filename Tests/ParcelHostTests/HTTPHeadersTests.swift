#if !arch(wasm32)
  import HTTPTypes
  import Testing

  @testable import Parcel

  @Test func httpHeadersPreserveMultipleValuesCaseInsensitively() {
    var headers = HTTPFields()
    headers.append(.init(name: .setCookie, value: "a=1"))
    headers.append(.init(name: HTTPField.Name("set-cookie")!, value: "b=2"))

    #expect(headers[fields: .setCookie].first?.value == "a=1")
    #expect(headers[values: .setCookie] == ["a=1", "b=2"])
  }

  @Test func httpFieldsResolveLookupsCaseInsensitively() {
    var headers: HTTPFields = [
      .accept: "application/json",
      .xTrace: "default",
    ]
    headers.append(.init(name: HTTPField.Name("x-trace")!, value: "custom-1"))

    #expect(headers[HTTPField.Name("accept")!] == "application/json")
    #expect(headers[values: HTTPField.Name("X-Trace")!] == ["default", "custom-1"])
  }
#endif
