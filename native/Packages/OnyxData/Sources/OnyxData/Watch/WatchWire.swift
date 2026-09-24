import Foundation
import OnyxCore
import os

/// What arrived over the watch link, already decoded. The host does the
/// storing — the wire knows nothing about a database, which is what lets it
/// be tested with no store at all.
///
/// ── OUTSIDE `WatchLink`'S FENCE (overhaul Lane A) ───────────────────────────
/// It was `WatchLink.Inbound`, and `WatchLink.swift` is fenced
/// `#if canImport(WatchConnectivity)` — a framework macOS does not have. So
/// the one decode path both devices share could not run under `swift test`,
/// and W0 shipped `.effort` with no test of its receive. The type and the
/// decode live here now; `WatchLink.Inbound` is a typealias, so no host
/// spelling changed.
public enum WatchInbound: Sendable, Equatable {
    /// Events from the other device. Hand to `AppDatabase.ingest`.
    case events([SetEvent])
    /// A pencil claim. Hand to `AppDatabase.ingestOwnership`.
    case ownership(LiveSessionOwner)
    /// The phone's resolved schedule and user. Watch side only.
    case context(WatchContext)
    /// The rest clock started, changed or stopped on the other device.
    /// `nil` ends it.
    case rest(RestPulse?)
    /// Millilitres of water tapped on the WRIST (W4). Watch → phone only —
    /// see `WatchLink.send(waterMl:)`.
    case water(Double)
    /// A session opened, finished or discarded on the other device (App
    /// Store W4). Both directions. Hand to `AppDatabase.receiveSession`.
    case session(SessionPulse)
    /// A provisional RPE the wrist's Crown is scrubbing (overhaul W0).
    /// Watch → phone, message-only. NEVER persisted — see `EffortPulse`.
    case effort(EffortPulse)
}

/// The two-key envelope every WatchConnectivity payload rides in, and the one
/// decoder for it.
///
/// Free keys rather than a `Codable` envelope because WatchConnectivity
/// dictionaries are `[String: Any]` with a documented list of allowed value
/// types, and `Data` is on it — so one key naming the case and one carrying
/// JSON is the whole protocol.
public enum WatchWire {
    enum Key {
        static let kind = "k"
        static let payload = "p"
    }

    enum Kind {
        static let events = "events"
        static let ownership = "pencil"
        static let context = "context"
        static let rest = "rest"
        static let water = "water"
        static let session = "session"
        static let effort = "effort"
    }

    /// The one decode path, shared by all three delivery callbacks on both
    /// devices. Nil for anything that does not decode.
    ///
    /// Unknown kinds are ignored rather than treated as errors: a newer build
    /// on the other wrist may send something this one has never heard of, and
    /// the correct response to that is to carry on logging.
    public static func decode(_ message: [String: Any]) -> WatchInbound? {
        guard let kind = message[Key.kind] as? String else { return nil }
        let data = message[Key.payload] as? Data
        switch kind {
        case Kind.events:
            return data.flatMap { try? OnyxJSON.decoder.decode([SetEvent].self, from: $0) }.map { .events($0) }
        case Kind.ownership:
            return data.flatMap { try? OnyxJSON.decoder.decode(LiveSessionOwner.self, from: $0) }.map { .ownership($0) }
        case Kind.context:
            return data.flatMap { try? OnyxJSON.decoder.decode(WatchContext.self, from: $0) }.map { .context($0) }
        case Kind.rest:
            // No payload IS the message: the clock stopped.
            guard let data else { return .rest(nil) }
            return (try? OnyxJSON.decoder.decode(RestPulse.self, from: data)).map { .rest($0) }
        case Kind.water:
            // A bare `Double`, not JSON: `Double` is on WatchConnectivity's
            // documented list of allowed dictionary value types, and a
            // one-number payload does not need an encoder. The cast is where
            // a malformed transfer dies — quietly, like every other kind here.
            guard let ml = message[Key.payload] as? Double, ml > 0 else { return nil }
            return .water(ml)
        case Kind.session:
            // Logged, unlike the other kinds' quiet drops: a pulse that does
            // not decode is a session the other device will never follow.
            guard let data, let pulse = try? OnyxJSON.decoder.decode(SessionPulse.self, from: data) else {
                Logger(subsystem: "app.onyx.link", category: "wire").error("a session pulse arrived and did not decode")
                return nil
            }
            return .session(pulse)
        case Kind.effort:
            return data.flatMap { try? OnyxJSON.decoder.decode(EffortPulse.self, from: $0) }.map { .effort($0) }
        default:
            return nil
        }
    }
}
