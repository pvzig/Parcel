public struct HTTPRequestOptions: Equatable, Sendable {
  public enum Mode: String, CaseIterable, Sendable {
    case cors = "cors"
    case noCORS = "no-cors"
    case sameOrigin = "same-origin"
  }

  public enum Credentials: String, CaseIterable, Sendable {
    case omit = "omit"
    case sameOrigin = "same-origin"
    case include = "include"
  }

  public enum Cache: String, CaseIterable, Sendable {
    case `default` = "default"
    case noStore = "no-store"
    case reload = "reload"
    case noCache = "no-cache"
    case forceCache = "force-cache"
    case onlyIfCached = "only-if-cached"
  }

  public var timeout: Duration?
  public var mode: Mode?
  public var credentials: Credentials?
  public var cache: Cache?

  public init(
    timeout: Duration? = nil,
    mode: Mode? = nil,
    credentials: Credentials? = nil,
    cache: Cache? = nil
  ) {
    self.timeout = timeout
    self.mode = mode
    self.credentials = credentials
    self.cache = cache
  }
}
