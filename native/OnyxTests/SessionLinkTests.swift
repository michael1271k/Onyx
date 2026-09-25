import Foundation
import Testing
@testable import Onyx

/// Precision B5 — `onyx://session/<uuid>`, the link a replay share carries.
/// A custom scheme is callable by anything on the device, so the parser is an
/// allow-list: this shape, one UUID, nothing else.
@Suite("Session link")
struct SessionLinkTests {

    @Test("a shared link parses to its session id, lower-cased")
    func parses() {
        let id = "9C1F2E4A-1B2C-4D3E-8F90-A1B2C3D4E5F6"
        #expect(SessionLink.sessionId(from: URL(string: "onyx://session/\(id)")!) == id.lowercased())
        #expect(SessionLink.sessionId(from: URL(string: "onyx://session/\(id.lowercased())")!) == id.lowercased())
    }

    @Test("the share text's own link round-trips")
    func roundTrips() {
        let id = "9c1f2e4a-1b2c-4d3e-8f90-a1b2c3d4e5f6"
        #expect(SessionLink.sessionId(from: SessionLink.url(sessionId: id)) == id)
    }

    @Test("anything else is refused", arguments: [
        "onyx://session/not-a-uuid",
        "onyx://session/",
        "onyx://session/9c1f2e4a-1b2c-4d3e-8f90-a1b2c3d4e5f6/extra",
        "onyx://open?path=/session",
        "https://session/9c1f2e4a-1b2c-4d3e-8f90-a1b2c3d4e5f6",
    ])
    func refuses(raw: String) {
        #expect(SessionLink.sessionId(from: URL(string: raw)!) == nil)
    }
}
