import HTTPTypes

#if arch(wasm32) && canImport(JavaScriptEventLoop) && canImport(JavaScriptKit)
  enum DefaultTransport {
    static func make() -> any Transport {
      if BrowserTransport.isSupportedRuntime {
        BrowserTransport()
      } else {
        UnavailableTransport()
      }
    }
  }

  struct UnavailableTransport: Transport {
    func send(
      _ request: HTTPRequest,
      body: HTTPBody?,
      timeout: Duration?
    ) async throws -> TransportResponse {
      throw ClientError.unsupportedPlatform
    }
  }
#endif
