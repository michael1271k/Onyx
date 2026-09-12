import Foundation

/// `onyx://open?path=/nutrition` → a tab.
///
/// Port of the web app's `lib/native/deepLink.ts`. A custom URL scheme is callable by
/// anything on the device that can open a URL — another app, a web page, a QR
/// code — so the string arriving here is untrusted input. `safePath` is an
/// ALLOW-LIST, not a sanitiser: it names the routes that exist rather than
/// guessing at the tricks that do not.
public enum DeepLink {
    /// Only these prefixes may be routed. Matched against the clean path or its
    /// first segment root, so `/nutrition/micros` stays routable.
    public static let allowed: [String] = [
        "/", "/nutrition", "/pathfinder", "/reports", "/settings", "/workout", "/session", "/day",
    ]

    /// The path a `onyx://` URL asks for, or nil. The FULL path (query and all)
    /// is returned; only the allow-list check looks at the clean path.
    public static func safePath(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, let url = URLComponents(string: raw) else { return nil }
        guard url.scheme?.lowercased() == "onyx" else { return nil }
        let path = url.queryItems?.first(where: { $0.name == "path" })?.value ?? ""
        guard path.hasPrefix("/") else { return nil }
        // `//evil.example` is a protocol-relative URL, which a router will
        // happily treat as an external origin.
        guard !path.hasPrefix("//") else { return nil }
        let clean = cleanPath(path)
        let root = "/" + (clean.split(separator: "/", omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? "")
        guard allowed.contains(clean) || allowed.contains(root) else { return nil }
        return path
    }

    /// `safePath` as a `URL`, for callers that hand it to the system.
    public static func url(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "onyx"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url
    }

    /// Where a safe path lands in the native shell.
    public enum Destination: Equatable, Sendable {
        case today, train, fuel, body(date: String?), you, reports
    }

    /// The tab a (safe) path lands on, or nil for a path the shell has no
    /// screen for. Takes the output of `safePath`, so the allow-list has
    /// already run; an unknown root here is a list drifted out of sync.
    public static func destination(forPath path: String) -> Destination? {
        let segments = cleanPath(path).split(separator: "/").map(String.init)
        switch segments.first {
        case nil: return .today
        case "workout", "session": return .train
        case "nutrition": return .fuel
        case "pathfinder": return .body(date: nil)
        case "day": return .body(date: segments.dropFirst().first)
        case "settings": return .you
        case "reports": return .reports
        default: return nil
        }
    }

    /// The path with its query and fragment stripped.
    private static func cleanPath(_ path: String) -> String {
        String(path.prefix { $0 != "?" && $0 != "#" })
    }
}
