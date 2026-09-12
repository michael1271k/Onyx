import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// How long the workout has been running — PURE, no clock of its own. A port of
// the web app's `lib/sessions/sessionElapsed.ts`.
//
// Total elapsed is `now − startedAt`, derived, never stored: a timestamp
// survives the jetsam-and-reload iOS performs on a backgrounded app, a counter
// does not. It refuses to answer outside 0…6 h, because `startedAt` is not
// always a live reading (a back-dated log, an edit deck) and "4,317 min" is
// worse than nothing. A pause is two stored numbers — banked milliseconds and
// the open pause's start — and never rewrites `startedAt`.
// ─────────────────────────────────────────────────────────────────────────────

public struct SessionPause: Codable, Equatable, Sendable {
    /// Milliseconds already banked from completed pauses.
    public var pausedMs: Double?
    /// ISO timestamp of the pause in progress, or nil when running.
    public var pausedAt: String?
    public init(pausedMs: Double? = nil, pausedAt: String? = nil) { self.pausedMs = pausedMs; self.pausedAt = pausedAt }
}

public enum SessionElapsed {
    /// Longer than any real workout, and far shorter than a mis-dated draft.
    public static let maxSessionSec: Double = 6 * 60 * 60

    /// Seconds since the session began, or nil when that is not a real answer.
    public static func elapsedSec(startedAt: String?, now: Double) -> Double? {
        guard let startedAt, !startedAt.isEmpty, let began = ISODate.parseMillis(startedAt) else { return nil }
        let sec = ((now - began) / 1000).rounded(.down)
        if sec < 0 || sec > maxSessionSec { return nil }
        return sec
    }

    /// The elapsed reading as the whole minutes `duration_min` stores — rounded,
    /// and nil under 30 s rather than a stored zero.
    public static func durationMin(_ sec: Double?) -> Double? {
        guard let sec else { return nil }
        let min = jsRound(sec / 60)
        return min > 0 ? min : nil
    }

    /// Milliseconds of `now` that must NOT be counted — banked pauses plus the one open. Never negative.
    public static func pausedMs(_ pause: SessionPause?, now: Double) -> Double {
        guard let pause else { return 0 }
        let banked = (pause.pausedMs?.isFinite == true) ? Swift.max(0, pause.pausedMs!) : 0
        guard let at = pause.pausedAt, !at.isEmpty, let since = ISODate.parseMillis(at) else { return banked }
        return banked + Swift.max(0, now - since)
    }

    /// Seconds since the session began MINUS any time it was paused. The 6 h
    /// bound applies to the WALL clock, before the pause comes off.
    public static func activeSec(startedAt: String?, now: Double, pause: SessionPause? = nil) -> Double? {
        guard let startedAt, !startedAt.isEmpty, let began = ISODate.parseMillis(startedAt) else { return nil }
        let raw = now - began
        if raw < 0 || raw / 1000 > maxSessionSec { return nil }
        return Swift.max(0, ((raw - pausedMs(pause, now: now)) / 1000).rounded(.down))
    }
}
