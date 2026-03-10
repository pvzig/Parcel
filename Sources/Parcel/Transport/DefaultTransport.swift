import Foundation
import HTTPTypes

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
  func send(
    _ request: HTTPRequest,
    body: Data?,
    timeout: Duration?
  ) async throws -> (response: HTTPResponse, body: Data?, url: URL?) {
    throw ClientError.unsupportedPlatform
  }
}
