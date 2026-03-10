enum DefaultTransport {
  static func make() -> any Transport {
    #if arch(wasm32) && canImport(JavaScriptEventLoop) && canImport(JavaScriptKit)
      if BrowserTransport.isSupportedRuntime {
        BrowserTransport()
      } else {
        UnavailableTransport()
      }
    #else
      UnavailableTransport()
    #endif
  }
}

struct UnavailableTransport: Transport {
  func send(_ request: HTTPRequest) async throws -> HTTPResponse {
    throw ClientError.unsupportedPlatform
  }
}
