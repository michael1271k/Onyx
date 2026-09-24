import Foundation
import CryptoKit
import OnyxCore

/// The NIH Dietary Supplement Label Database, over the network (overhaul C3,
/// decision Q11). The pure half — shapes, the label → sheet mapping — is
/// `OnyxCore.DSLD`; this is the transport and the cache.
///
/// ── FAST, RELIABLE, STABLE, IN THAT ORDER OF WHAT FAILS FIRST ───────────────
///   · 4 s per request, then up to 3 retries with doubling backoff (0.3 s,
///     0.6 s, 1.2 s) on a timeout, a dropped connection or a 5xx. Never on a
///     4xx (the request is wrong, asking again is the same answer) and never
///     on cancellation (a new keystroke already superseded it).
///   · Every answer is cached by URL for 7 days, in memory and on disk, so a
///     search typed twice, a label reopened or a brand paged back is instant
///     and works offline. Label data changes on the order of months.
///   · Twenty hits a page.
///
/// Offline or failed is a thrown error; the sheet answers it with the manual
/// form and one line of notice. Nothing here ever blocks the manual path.
public actor DSLDClient {

    /// Un-challenged host for the v9 API — see `DSLD`'s header for why not
    /// `dsld.od.nih.gov`.
    public static let base = URL(string: "https://api.ods.od.nih.gov/dsld/v9/")!
    public static let pageSize = 20
    public static let timeout: TimeInterval = 4
    public static let ttl: TimeInterval = 7 * 24 * 3600
    static let backoff: [UInt64] = [300, 600, 1_200]

    public enum Failure: Error, Equatable {
        case status(Int)
        case offline
        /// A 200 that is not JSON — a captive portal, a CDN interstitial.
        case notJSON
    }

    /// One client for the app, so its memory cache outlives a sheet.
    public static let shared = DSLDClient()

    private let session: URLSession
    private let cacheDirectory: URL?
    private var memory: [URL: (at: Date, data: Data)] = [:]
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - session: injected for tests (a mock `URLProtocol`); the default is
    ///     an ephemeral session whose own cache is off — this type IS the cache.
    ///   - cacheDirectory: nil disables the disk cache.
    public init(
        session: URLSession? = nil,
        cacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("dsld", isDirectory: true),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = Self.timeout
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
        self.cacheDirectory = cacheDirectory
        self.now = now
        if let cacheDirectory {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - The four reads

    /// Products whose name matches, twenty at a time.
    public func searchProducts(_ query: String, from: Int = 0) async throws -> DSLD.Page {
        try JSONDecoder().decode(DSLD.Page.self, from: await data(Self.url("search-filter", [
            "q": query, "size": "\(Self.pageSize)", "from": "\(from)",
        ])))
    }

    /// Brand names matching a company query, deduplicated (the endpoint
    /// answers one hit per label).
    public func brands(_ query: String) async throws -> [String] {
        DSLD.brands(try JSONDecoder().decode(DSLD.Page.self, from: await data(Self.url("browse-brands", [
            "method": "by_keyword", "q": query, "size": "200",
        ]))))
    }

    /// One brand's products, twenty at a time. `search-filter` with a brand
    /// filter rather than `brand-products`: the same hits at a fifth of the
    /// bytes, because `brand-products` returns every label WHOLE.
    public func products(brand: String, from: Int = 0) async throws -> DSLD.Page {
        try JSONDecoder().decode(DSLD.Page.self, from: await data(Self.url("search-filter", [
            "q": "*", "brand": brand, "size": "\(Self.pageSize)", "from": "\(from)",
        ])))
    }

    /// One label, whole.
    public func label(id: String) async throws -> DSLD.Label {
        try JSONDecoder().decode(DSLD.Label.self, from: await data(Self.url("label/\(id)", [:])))
    }

    /// A barcode's product name from Open Food Facts — the hop that turns a
    /// bottle in hand into a DSLD search. Nil when OFF does not know it.
    public func productName(barcode: String) async throws -> String? {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=product_name,brands")
        else { return nil }
        struct OFF: Decodable {
            struct Product: Decodable { let product_name: String?; let brands: String? }
            let product: Product?
        }
        let product = try JSONDecoder().decode(OFF.self, from: await data(url)).product
        let name = [product?.brands?.split(separator: ",").first.map(String.init), product?.product_name]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    // MARK: - Transport

    static func url(_ path: String, _ query: [String: String]) -> URL {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    /// Cache, then the network with retries, then the cache again.
    func data(_ url: URL) async throws -> Data {
        if let hit = memory[url], now().timeIntervalSince(hit.at) < Self.ttl { return hit.data }
        if let disk = readDisk(url) {
            memory[url] = disk
            return disk.data
        }
        var lastError: Error = Failure.offline
        for attempt in 0...Self.backoff.count {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: url, timeoutInterval: Self.timeout)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (body, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                if (200..<300).contains(status) {
                    // Never cache a page that is not JSON for a week.
                    guard (try? JSONSerialization.jsonObject(with: body)) != nil else { throw Failure.notJSON }
                    memory[url] = (now(), body)
                    writeDisk(url, body)
                    return body
                }
                lastError = Failure.status(status)
                guard status >= 500 else { throw lastError }
            } catch let error as URLError where Self.retryable(error) {
                lastError = error
            } catch {
                throw error
            }
            if attempt < Self.backoff.count {
                try await Task.sleep(nanoseconds: Self.backoff[attempt] * 1_000_000)
            }
        }
        // Offline after the week is up: an old label beats no label.
        if let stale = readDisk(url, ignoringAge: true) { return stale.data }
        throw lastError
    }

    static func retryable(_ error: URLError) -> Bool {
        [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
         .cannotFindHost, .dnsLookupFailed].contains(error.code)
    }

    private func file(_ url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory?.appendingPathComponent(digest + ".json")
    }

    private func readDisk(_ url: URL, ignoringAge: Bool = false) -> (at: Date, data: Data)? {
        guard let file = file(url),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              ignoringAge || now().timeIntervalSince(modified) < Self.ttl,
              let data = try? Data(contentsOf: file)
        else { return nil }
        return (modified, data)
    }

    private func writeDisk(_ url: URL, _ data: Data) {
        guard let file = file(url) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
