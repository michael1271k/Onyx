import Foundation
import Testing
import OnyxCore
@testable import OnyxData

/// A `URLProtocol` the client's session is handed, so no test touches the
/// network. One handler at a time — the suite is serialized.
final class DSLDStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        do {
            guard let handler = Self.handler else { throw URLError(.notConnectedToInternet) }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DSLDStub.self]
        return URLSession(configuration: config)
    }
}

@Suite("DSLD client", .serialized)
struct DSLDClientTests {

    private static let label = #"""
    {"id": 323076, "fullName": "Basic Nutrients 2/Day", "brandName": "Thorne",
     "physicalState": {"langualCodeDescription": "Capsule"},
     "servingSizes": [{"minQuantity": 2, "maxQuantity": 2, "unit": "Capsule(s)"}],
     "ingredientRows": [{"name": "Vitamin C", "quantity": [{"quantity": 250, "unit": "mg"}]}]}
    """#

    private func client() -> DSLDClient {
        DSLDStub.requests = []
        return DSLDClient(session: DSLDStub.session(), cacheDirectory: nil)
    }

    @Test("a label is read once, then answered from the cache")
    func labelIsCached() async throws {
        let dsld = client()
        DSLDStub.handler = { _ in (200, Data(Self.label.utf8)) }
        let first = try await dsld.label(id: "323076")
        let second = try await dsld.label(id: "323076")
        #expect(first == second)
        #expect(first.fullName == "Basic Nutrients 2/Day")
        #expect(DSLDStub.requests.count == 1, "the second read never reached the network")
        #expect(DSLDStub.requests.first?.url?.absoluteString == "https://api.ods.od.nih.gov/dsld/v9/label/323076")
    }

    @Test("a timeout retries three times with backoff, then fails")
    func timeoutRetriesThenThrows() async throws {
        let dsld = client()
        DSLDStub.handler = { _ in throw URLError(.timedOut) }
        await #expect(throws: URLError.self) { try await dsld.label(id: "1") }
        #expect(DSLDStub.requests.count == 4)
        #expect(DSLDStub.requests.first?.timeoutInterval == 4)
    }

    @Test("a 404 is an answer, not a flake: no retry")
    func clientErrorDoesNotRetry() async throws {
        let dsld = client()
        DSLDStub.handler = { _ in (404, Data()) }
        await #expect(throws: DSLDClient.Failure.status(404)) { try await dsld.label(id: "nope") }
        #expect(DSLDStub.requests.count == 1)
    }

    @Test("a 503 then a 200 is a success on the second try")
    func serverErrorRetries() async throws {
        let dsld = client()
        nonisolated(unsafe) var calls = 0
        DSLDStub.handler = { _ in
            calls += 1
            return calls == 1 ? (503, Data()) : (200, Data(Self.label.utf8))
        }
        _ = try await dsld.label(id: "323076")
        #expect(DSLDStub.requests.count == 2)
    }

    @Test("searches ask for twenty at a time, from an offset; a brand is a filter")
    func queriesArePaged() async throws {
        let dsld = client()
        DSLDStub.handler = { _ in (200, Data(#"{"hits": [], "stats": {"count": 0}}"#.utf8)) }
        _ = try await dsld.searchProducts("magnesium", from: 40)
        _ = try await dsld.products(brand: "Thorne")
        let urls = DSLDStub.requests.compactMap { $0.url?.absoluteString }
        #expect(urls == [
            "https://api.ods.od.nih.gov/dsld/v9/search-filter?from=40&q=magnesium&size=20",
            "https://api.ods.od.nih.gov/dsld/v9/search-filter?brand=Thorne&from=0&q=*&size=20",
        ])
    }

    @Test("a barcode becomes a name through Open Food Facts")
    func barcodeToName() async throws {
        let dsld = client()
        DSLDStub.handler = { _ in (200, Data(#"{"product": {"product_name": "Basic Nutrients 2/Day", "brands": "Thorne, Thorne Research"}}"#.utf8)) }
        #expect(try await dsld.productName(barcode: "6 93749 00287 1") == "Thorne Basic Nutrients 2/Day")
        #expect(DSLDStub.requests.first?.url?.path == "/api/v2/product/693749002871.json")
    }
}
