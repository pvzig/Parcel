# Parcel

Parcel is a small browser HTTP client for SwiftWASM.

The goal is to wrap the browser `fetch` API with a Swifty surface that:

- encodes request bodies from `Encodable` models
- decodes responses into `Decodable` models
- stays small enough to feel like a browser-native helper instead of a full networking framework

## Status

This repo is intentionally starting small. The current commit sets up the package, docs, license, and a minimal public API surface for the client.

## Direction

The intended shape is something close to:

```swift
let client = ParcelClient()

let accepted: AcceptedResponse = try await client.post(
    GenerateRequest(context: context),
    to: functionURL
)
```

Under the hood, Parcel should use the browser Fetch API on SwiftWASM and handle the `Codable` JSON path cleanly.
