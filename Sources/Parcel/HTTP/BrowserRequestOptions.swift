/// Fetch request options that Parcel's browser transport applies to every request it sends.
///
/// Each property is optional; `nil` leaves the option off the Fetch init dictionary entirely so
/// the browser applies its own default. The type is available on every platform so shared code
/// can construct transport options without conditional compilation, but only `BrowserTransport`
/// consumes it.
public struct BrowserRequestOptions: Sendable, Equatable {
  /// Whether the browser sends credentials (cookies, TLS client certificates, `Authorization`
  /// headers populated by the browser) with cross-origin requests.
  ///
  /// The Fetch default is `.sameOrigin`, so cross-origin cookie authentication requires
  /// `.include` plus a server that answers with `Access-Control-Allow-Credentials`.
  public enum Credentials: String, Sendable, Equatable {
    case omit
    case sameOrigin = "same-origin"
    case include
  }

  /// The request mode, which determines how the browser handles cross-origin responses.
  public enum Mode: String, Sendable, Equatable {
    case cors
    case noCORS = "no-cors"
    case sameOrigin = "same-origin"
  }

  /// How the request interacts with the browser's HTTP cache.
  public enum CachePolicy: String, Sendable, Equatable {
    case `default`
    case noStore = "no-store"
    case reload
    case noCache = "no-cache"
    case forceCache = "force-cache"
    case onlyIfCached = "only-if-cached"
  }

  /// How the browser handles redirect responses.
  ///
  /// `.follow` (the Fetch default) resolves redirects before Parcel sees the response, which is
  /// why `TransportResponse.url` can differ from the requested URL.
  public enum Redirect: String, Sendable, Equatable {
    case follow
    case error
    case manual
  }

  /// The Fetch `credentials` option, or `nil` to use the browser default.
  public let credentials: Credentials?

  /// The Fetch `mode` option, or `nil` to use the browser default.
  public let mode: Mode?

  /// The Fetch `cache` option, or `nil` to use the browser default.
  public let cache: CachePolicy?

  /// The Fetch `redirect` option, or `nil` to use the browser default.
  public let redirect: Redirect?

  /// Creates request options. Omitted options are left to the browser.
  public init(
    credentials: Credentials? = nil,
    mode: Mode? = nil,
    cache: CachePolicy? = nil,
    redirect: Redirect? = nil
  ) {
    self.credentials = credentials
    self.mode = mode
    self.cache = cache
    self.redirect = redirect
  }

  /// The options as `(fetch init key, value)` pairs, skipping options left to the browser.
  var fetchInitEntries: [(key: String, value: String)] {
    var entries: [(key: String, value: String)] = []
    if let credentials {
      entries.append((key: "credentials", value: credentials.rawValue))
    }
    if let mode {
      entries.append((key: "mode", value: mode.rawValue))
    }
    if let cache {
      entries.append((key: "cache", value: cache.rawValue))
    }
    if let redirect {
      entries.append((key: "redirect", value: redirect.rawValue))
    }
    return entries
  }
}
