#if canImport(WatchConnectivity)
import Foundation
import OnyxCore
import WatchConnectivity

/// The phone↔watch link.
///
/// ── ONE FILE, BOTH SIDES, AND THAT IS THE POINT ─────────────────────────────
/// The phone half and the watch half do the same three things — encode an
/// event, hand it to WatchConnectivity, decode what arrives and give it to
/// `ingest`. Two copies of that would be two decoders for one wire format, and
/// the wire format outlives the build on both ends: a watch routinely runs an
/// older binary than the phone paired to it. So there is one implementation,
/// compiled into both targets, and the only asymmetry is which side sends the
/// context (§`send(context:)`).
///
/// ── WHAT IS AUTHORITATIVE, AND WHAT IS NOT ──────────────────────────────────
/// **Nothing here is a source of truth.** Every path below hands what it
/// receives to `AppDatabase.ingest` or `ingestOwnership`, both of which are
/// idempotent, both of which pull the Lamport clock up, and neither of which
/// re-queues what it took in. A message that never arrives costs latency and
/// nothing else — the event is already committed to the local log and the local
/// outbox before this type is asked to do anything, and Supabase carries it
/// through `set_events` on whatever schedule the network allows.
///
/// That ordering is the whole durability argument, and it is why `send` returns
/// nothing and throws nothing worth handling.
///
/// ── THE THREE CHANNELS ──────────────────────────────────────────────────────
/// | channel | carries | why that one |
/// |---|---|---|
/// | `updateApplicationContext` | the schedule context and the signed-in user | ONE slot, replaced by the newest, delivered on next wake even if the app was never launched. It is STATE, and a queue of stale states is worse than one current one. |
/// | `transferUserInfo` | `SetEvent`s | queued, persisted across relaunch and reboot, FIFO, delivered when the counterpart is not running. The delivery guarantee a set needs. |
/// | `sendMessage` | the pencil claim, and the live rest timer | immediate, needs reachability — which is correct: a rest timer that arrives four minutes late is noise, and a pencil claim that cannot reach the other device should fall back to the log's own resolution. |
///
/// `transferUserInfo` for a set and `sendMessage` for a timer is not a
/// preference. `sendMessage` fails outright when the counterpart is unreachable
/// and has no queue behind it; using it for a set would lose the set every time
/// the phone was in a locker. `transferUserInfo` for a timer would deliver a
/// countdown that expired minutes ago.
public final class WatchLink: NSObject, Sendable {

    /// What arrived, already decoded. The host does the storing — this type
    /// knows about a wire and nothing about a database, which is what lets it
    /// be tested with no store at all.
    public enum Inbound: Sendable, Equatable {
        /// Events from the other device. Hand to `AppDatabase.ingest`.
        case events([SetEvent])
        /// A pencil claim. Hand to `AppDatabase.ingestOwnership`.
        case ownership(LiveSessionOwner)
        /// The phone's resolved schedule and user. Watch side only.
        case context(WatchContext)
        /// The rest clock started, changed or stopped on the other device.
        /// `nil` ends it.
        case rest(RestPulse?)
        /// Millilitres of water tapped on the WRIST (W4). Watch → phone only.
        ///
        /// ── WHY THE WATCH CANNOT JUST LOG IT ────────────────────────────────
        /// It has no water to log into. The wrist's store holds sets and
        /// nothing else (`OnyxWatchApp`'s header), the day's ledger lives in
        /// the phone's `water_intake`, and an App Group is per DEVICE — so the
        /// `PendingWater` mailbox the phone's Control Center button drops a
        /// glass into is a container on a different chip. The wrist's button
        /// therefore posts the millilitres and the phone drops them in the
        /// SAME mailbox, drained by the same `drainPendingWater` through the
        /// same `addWaterGlass`. One row, one code path, two devices.
        case water(Double)
    }

    /// A payload key. Free functions rather than a `Codable` envelope because
    /// WatchConnectivity dictionaries are `[String: Any]` with a documented list
    /// of allowed value types, and `Data` is on it — so one key naming the case
    /// and one carrying JSON is the whole protocol.
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
    }

    private let onInbound: @Sendable (Inbound) -> Void

    /// - Parameter onInbound: called on WatchConnectivity's own queue, NOT the
    ///   main actor. The host hops if it needs to; `ingest` is a database write
    ///   and wants to stay off the main thread anyway.
    ///
    /// ── THERE IS NO INJECTED SESSION, AND THAT IS NOT AN OVERSIGHT ──────────
    /// `WCSession` is not `Sendable`, so storing one would make this class
    /// un-`Sendable` — and `@preconcurrency` on the import only downgrades that
    /// to a warning, which is a latent error wearing a hat. It is also
    /// unnecessary: `receive(_:)` takes a plain dictionary and every delivery
    /// callback funnels through it, so a test exercises the whole decode with no
    /// session, no pairing and no simulator.
    public init(onInbound: @escaping @Sendable (Inbound) -> Void) {
        self.onInbound = onInbound
        super.init()
    }

    /// Activate the link. Safe to call more than once.
    ///
    /// `isSupported()` is false on iPad and on a Mac running an iOS app, and
    /// touching `WCSession.default` there traps. It is always true on watchOS.
    public func activate() {
        guard WCSession.isSupported() else { return }
        let wc = WCSession.default
        wc.delegate = self
        wc.activate()
    }

    // MARK: - Sending

    /// Queue events for the other device.
    ///
    /// Guaranteed, not immediate. One transfer per call rather than one per
    /// event: a workout logged in a lift with no phone in range arrives as a
    /// handful of transfers rather than sixty, and `ingest` takes an array
    /// natively.
    ///
    /// A transfer that cannot be created — no counterpart app installed — is
    /// silently dropped, and that is the correct behaviour: the events are in
    /// the local log and the outbox, and Supabase is the durable path.
    public func send(events: [SetEvent]) {
        guard !events.isEmpty, let wc = active() else { return }
        guard let data = try? OnyxJSON.encoder.encode(events) else { return }
        wc.transferUserInfo([Key.kind: Kind.events, Key.payload: data])
    }

    /// Tell the other device who holds the pencil.
    ///
    /// `sendMessage`, so a takeover the user just tapped is felt immediately —
    /// and unreachable is a legitimate outcome. `LiveSessionOwner.isSuperseded`
    /// settles a claim that never arrived the next time either device syncs,
    /// which is what makes this an optimisation rather than a requirement.
    public func send(ownership claim: LiveSessionOwner) {
        guard let wc = active(), wc.isReachable else { return }
        guard let data = try? OnyxJSON.encoder.encode(claim) else { return }
        wc.sendMessage([Key.kind: Kind.ownership, Key.payload: data], replyHandler: nil) { _ in }
    }

    /// Mirror the rest clock. `nil` stops it.
    ///
    /// Immediate or not at all, on purpose: a countdown is only worth anything
    /// while it is running, and the queue would deliver one that had already
    /// expired.
    public func send(rest: RestPulse?) {
        guard let wc = active(), wc.isReachable else { return }
        var body: [String: Any] = [Key.kind: Kind.rest]
        if let rest, let data = try? OnyxJSON.encoder.encode(rest) { body[Key.payload] = data }
        wc.sendMessage(body, replyHandler: nil) { _ in }
    }

    /// Post a glass of water to the phone (W4). Watch → phone.
    ///
    /// ── `transferUserInfo`, LIKE A SET AND NOT LIKE A TIMER ─────────────────
    /// A glass is a FACT, and the wrist is the one device that knows it
    /// happened. `sendMessage` would drop it the moment the phone is in a
    /// locker — which is most of a workout — and there is no second road: the
    /// watch has no `water_intake` table to keep it in until the two meet
    /// (`Inbound.water` says why). Queued, persisted across relaunch and
    /// reboot, FIFO: the same guarantee a set gets, for the same reason.
    ///
    /// ── AND WHY THAT DOES NOT DOUBLE-COUNT ──────────────────────────────────
    /// `PendingWater` is a mailbox the phone ADDS to and empties under its own
    /// transaction, and WatchConnectivity delivers a `transferUserInfo`
    /// exactly once. A transfer that is never delivered is a glass that is
    /// lost, which is the honest failure here — the alternative, a queue the
    /// wrist replays, is a glass logged twice.
    /// - Returns: whether the transfer was CREATED. False means nothing is
    ///   queued and nothing ever will be — there is no counterpart app, or
    ///   `WCSession` has not finished activating, which is the state for the
    ///   first moment after launch and the Fuel page is two taps away.
    ///
    ///   The caller has to know, because the wrist draws the glass
    ///   optimistically: `WatchModel.addWaterGlass` incremented its own
    ///   figure whatever happened here, so a tap in that first moment played
    ///   the haptic, moved the number and queued nothing. A lost glass with
    ///   a confirmation is worse than a lost glass.
    @discardableResult
    public func send(waterMl ml: Double) -> Bool {
        guard ml > 0, let wc = active() else { return false }
        wc.transferUserInfo([Key.kind: Kind.water, Key.payload: ml])
        return true
    }

    /// Replace the watch's copy of "who is signed in and what is today".
    ///
    /// PHONE SIDE ONLY in practice — the watch has no plan resolution of its
    /// own to send back. One slot, overwritten: the newest context is the only
    /// one that has ever been wanted, and WatchConnectivity delivers it on the
    /// counterpart's next wake even if the app has never been launched.
    ///
    /// Throws only for an unencodable context, which would be a programming
    /// error; a failed *delivery* is not an error here, it is Tuesday.
    public func send(context: WatchContext) {
        guard let wc = active() else { return }
        guard let data = try? OnyxJSON.encoder.encode(context) else { return }
        try? wc.updateApplicationContext([Key.kind: Kind.context, Key.payload: data])
    }

    private func active() -> WCSession? {
        guard WCSession.isSupported() else { return nil }
        let wc = WCSession.default
        guard wc.activationState == .activated else { return nil }
        #if os(iOS)
        // A phone with no watch paired, or with the app not installed on it,
        // has nowhere to send. Checking here rather than at four call sites.
        guard wc.isPaired, wc.isWatchAppInstalled else { return nil }
        #endif
        return wc
    }

    // MARK: - Receiving

    /// The one decode path, shared by all three delivery callbacks.
    ///
    /// Unknown kinds are ignored rather than treated as errors: a newer build on
    /// the other wrist may send something this one has never heard of, and the
    /// correct response to that is to carry on logging.
    func receive(_ message: [String: Any]) {
        guard let kind = message[Key.kind] as? String else { return }
        let data = message[Key.payload] as? Data
        switch kind {
        case Kind.events:
            guard let data, let events = try? OnyxJSON.decoder.decode([SetEvent].self, from: data) else { return }
            onInbound(.events(events))
        case Kind.ownership:
            guard let data, let claim = try? OnyxJSON.decoder.decode(LiveSessionOwner.self, from: data) else { return }
            onInbound(.ownership(claim))
        case Kind.context:
            guard let data, let context = try? OnyxJSON.decoder.decode(WatchContext.self, from: data) else { return }
            onInbound(.context(context))
        case Kind.rest:
            guard let data else { return onInbound(.rest(nil)) }
            guard let pulse = try? OnyxJSON.decoder.decode(RestPulse.self, from: data) else { return }
            onInbound(.rest(pulse))
        case Kind.water:
            // A bare `Double`, not JSON: `Double` is on WatchConnectivity's
            // documented list of allowed dictionary value types, and a
            // one-number payload does not need an encoder. The cast is where
            // a malformed transfer dies — quietly, like every other kind here.
            guard let ml = message[Key.payload] as? Double, ml > 0 else { return }
            onInbound(.water(ml))
        default:
            return
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchLink: WCSessionDelegate {

    public func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?
    ) {}

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        receive(userInfo)
    }

    public func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        receive(context)
    }

    #if os(iOS)
    /// Both are required on iOS and both mean "the paired watch changed".
    ///
    /// Reactivating is the documented recovery and there is nothing else to do:
    /// this app holds no per-watch state, so a new watch simply starts from the
    /// application context the next `send(context:)` writes.
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#endif
