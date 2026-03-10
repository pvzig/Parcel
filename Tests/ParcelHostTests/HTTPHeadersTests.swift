#if !arch(wasm32)
  import Testing

  @testable import Parcel

  @Test func httpHeadersPreserveMultipleValuesCaseInsensitively() {
    var headers = HTTPHeaders()
    headers.add(name: "Set-Cookie", value: "a=1")
    headers.add(name: "set-cookie", value: "b=2")

    #expect(headers["SET-COOKIE"] == "a=1")
    #expect(headers.values(for: "set-cookie") == ["a=1", "b=2"])
  }

  @Test func httpHeadersMergeOverrideReplacesDefaultValuesCaseInsensitively() {
    var headers = HTTPHeaders(["Accept": "application/json", "X-Trace": "default"])
    let overrides = HTTPHeaders([
      ("accept", "application/problem+json"),
      ("X-Trace", "custom-1"),
      ("x-trace", "custom-2"),
    ])

    headers.merge(overridingWith: overrides)

    #expect(headers.values(for: "accept") == ["application/problem+json"])
    #expect(headers.values(for: "X-Trace") == ["custom-1", "custom-2"])
  }
#endif
