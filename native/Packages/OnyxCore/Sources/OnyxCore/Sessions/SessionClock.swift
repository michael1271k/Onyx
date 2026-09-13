import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The session clock — one running timer in two modes. The MODEL half of
// the web app's `lib/sessions/sessionClock.ts`; the store (localStorage, subscribers) is
// OnyxData's.
//
// It stores TIMESTAMPS, not an elapsed count: elapsed is derived from the wall
// clock, so a clock that survived a reload is still right. Pause is
// ACCUMULATED, not re-based — a run is a sum of segments. A clock older than an
// hour is discarded on read rather than restored. The countdown's remainder is
// rounded UP so a 1:00 timer reads 1:00 for the whole of its first second.
// ─────────────────────────────────────────────────────────────────────────────

public enum ClockMode: String, Codable, Sendable { case timer, stopwatch }

public struct SessionClock: Codable, Equatable, Sendable {
    public var mode: ClockMode
    /// Epoch ms the OPEN segment began, or nil when idle or paused.
    public var startedAt: Double?
    /// Milliseconds banked by segments already paused.
    public var accumulatedMs: Double
    /// How long the countdown runs for, in seconds. Survives a reset.
    public var durationSec: Double

    public init(mode: ClockMode = .timer, startedAt: Double? = nil, accumulatedMs: Double = 0, durationSec: Double = Clock.defaultDurationSec) {
        self.mode = mode; self.startedAt = startedAt; self.accumulatedMs = accumulatedMs; self.durationSec = durationSec
    }

    public static let idle = SessionClock()
}

public enum Clock {
    public static let defaultDurationSec: Double = 60
    public static let durationStepSec: Double = 15
    public static let minDurationSec: Double = 15
    public static let maxDurationSec: Double = 60 * 60
    /// Longer than any real rest. A clock this old was left running by accident.
    public static let staleAfterMs: Double = 60 * 60 * 1000

    public static func clampDuration(_ sec: Double) -> Double {
        Swift.min(maxDurationSec, Swift.max(minDurationSec, jsRound(sec)))
    }

    /// `typeof v === 'number' && Number.isFinite(v)` over a JSON value.
    private static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    /// Tolerant read of the stored row: unknown mode → timer, non-number
    /// `startedAt` → nil, `accumulatedMs` ≥ 0, duration clamped with the v1
    /// `targetSec` honoured. Garbage → idle.
    public static func parse(_ raw: String?) -> SessionClock {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let v = any as? [String: Any]
        else { return .idle }
        return SessionClock(
            mode: (v["mode"] as? String) == "stopwatch" ? .stopwatch : .timer,
            startedAt: number(v["startedAt"]),
            accumulatedMs: Swift.max(0, number(v["accumulatedMs"]) ?? 0),
            durationSec: clampDuration(number(v["durationSec"]) ?? number(v["targetSec"]) ?? defaultDurationSec)
        )
    }

    public static func isStale(_ c: SessionClock, now: Double) -> Bool {
        guard let s = c.startedAt else { return false }
        return now - s > staleAfterMs
    }

    /// What `getSessionClock` hands back: the stored clock, stopped if it went stale.
    public static func settle(_ c: SessionClock, now: Double) -> SessionClock {
        guard isStale(c, now: now) else { return c }
        var next = c
        next.startedAt = nil
        next.accumulatedMs = 0
        return next
    }

    /// Read the stored row at `now` — parse, then settle.
    public static func read(_ raw: String?, now: Double) -> SessionClock { settle(parse(raw), now: now) }

    // MARK: - Transitions (each over an already-settled clock)

    /// Switch tabs. The running clock is STOPPED rather than carried across.
    public static func setMode(_ c: SessionClock, _ mode: ClockMode) -> SessionClock {
        if c.mode == mode { return c }
        return SessionClock(mode: mode, startedAt: nil, accumulatedMs: 0, durationSec: c.durationSec)
    }

    /// Begin, or resume after a pause. Idempotent while already running.
    public static func start(_ c: SessionClock, mode: ClockMode? = nil, now: Double) -> SessionClock {
        let next = mode ?? c.mode
        if next != c.mode { return SessionClock(mode: next, startedAt: now, accumulatedMs: 0, durationSec: c.durationSec) }
        if c.startedAt != nil { return c }
        var out = c
        out.startedAt = now
        return out
    }

    /// Fold the open segment into the accumulator and hold.
    public static func pause(_ c: SessionClock, now: Double) -> SessionClock {
        guard let s = c.startedAt else { return c }
        var out = c
        out.startedAt = nil
        out.accumulatedMs = c.accumulatedMs + Swift.max(0, now - s)
        return out
    }

    /// Back to zero, keeping the mode and the chosen duration.
    public static func reset(_ c: SessionClock) -> SessionClock {
        SessionClock(mode: c.mode, startedAt: nil, accumulatedMs: 0, durationSec: c.durationSec)
    }

    /// Restart from zero and run.
    public static func restart(_ c: SessionClock, now: Double) -> SessionClock {
        SessionClock(mode: c.mode, startedAt: now, accumulatedMs: 0, durationSec: c.durationSec)
    }

    /// Change the countdown's length. Resets a countdown that is mid-flight.
    public static func setDuration(_ c: SessionClock, _ sec: Double) -> SessionClock {
        SessionClock(mode: c.mode, startedAt: nil, accumulatedMs: 0, durationSec: clampDuration(sec))
    }

    // MARK: - Readings

    /// Milliseconds run so far — banked segments plus the one currently open.
    public static func elapsedMs(_ c: SessionClock, now: Double) -> Double {
        let open = c.startedAt.map { Swift.max(0, now - $0) } ?? 0
        return c.accumulatedMs + open
    }

    public static func elapsedSec(_ c: SessionClock, now: Double) -> Double {
        (elapsedMs(c, now: now) / 1000).rounded(.down)
    }

    /// Seconds left on the countdown, floored at zero and rounded UP.
    public static func remainingSec(_ c: SessionClock, now: Double) -> Double {
        Swift.max(0, c.durationSec - (elapsedMs(c, now: now) / 1000).rounded(.down))
    }

    /// The countdown has run out. Never true for a stopwatch.
    public static func isTimerDone(_ c: SessionClock, now: Double) -> Bool {
        c.mode == .timer && elapsedMs(c, now: now) >= c.durationSec * 1000
    }

    /// What the header button shows: the countdown's remainder, or the stopwatch's elapsed.
    public static func readingSec(_ c: SessionClock, now: Double) -> Double {
        c.mode == .timer ? remainingSec(c, now: now) : elapsedSec(c, now: now)
    }

    /// Is there anything on the clock — running, or paused with a reading?
    public static func isLive(_ c: SessionClock) -> Bool {
        c.startedAt != nil || c.accumulatedMs > 0
    }

    /// "1:30", "0:45", "12:04", "1:02:03" — m:ss always, hours only when there are hours.
    public static func format(_ sec: Double) -> String {
        let s = Swift.max(0, sec.rounded(.down))
        let h = (s / 3600).rounded(.down)
        let m = (s.truncatingRemainder(dividingBy: 3600) / 60).rounded(.down)
        let r = s.truncatingRemainder(dividingBy: 60)
        func pad(_ x: Double) -> String { var t = jsIntegerString(x); while t.count < 2 { t = "0" + t }; return t }
        return h > 0 ? "\(jsIntegerString(h)):\(pad(m)):\(pad(r))" : "\(jsIntegerString(m)):\(pad(r))"
    }
}
