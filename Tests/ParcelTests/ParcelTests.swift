import Testing

@testable import Parcel

@Test func clientUsesEmptyDefaultHeaders() {
  let client = ParcelClient()

  #expect(client.configuration.defaultHeaders.isEmpty)
}

@Test func methodsUseHTTPVerbs() {
  #expect(ParcelMethod.post.rawValue == "POST")
  #expect(ParcelMethod.delete.rawValue == "DELETE")
}
