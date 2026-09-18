import Foundation
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The two values that cross between the phone and the watch.
//
// ── WHY THEY ARE NOT IN `WatchLink.swift` ────────────────────────────────────
// That file is fenced `#if canImport(WatchConnectivity)`, because the framework
// exists only on iOS and watchOS. These are not transport — they are the wire
// FORMAT, and the wire format is the most version-sensitive thing in the wave:
// a watch routinely runs an older build than the phone paired to it, so a key
// that moves is a context that silently stops decoding on one wrist.
//
// Out here they compile and round-trip on macOS, which means `swift test` covers
// them on the command line with no simulator and no signing — the only
// continuously trustworthy signal this project has.
// ─────────────────────────────────────────────────────────────────────────────

/// What the watch needs to render a session before it has ever seen the network.
///
/// ── IT IS `ScheduleContext` PLUS TWO FIELDS, AND DELIBERATELY SO ────────────
/// `ScheduleContext` already resolves a date to a split — the plan, the phase,
/// the weekday layout and the dated overrides — and it is already `Codable` and
/// `Sendable` because the phone stores it. Since W2 it carries the decks
/// (`programs`), the plan rows and the phases too, so with these three values
/// the watch can name today's workout, list its movements and their prescribed
/// loads and rests, with no request to anything.
///
/// ponytail: every program rides along (~25 KB); send only the active deck
/// when the watch transfer ever gets slow.
///
/// The two extra fields are the ones a schedule cannot answer: whose data this
/// is, and what the phone believes today is. `today` travels rather than being
/// read from the watch's own clock because the two devices can disagree across
/// midnight, and a watch that decides it is already Tuesday would open the wrong
/// split.
public struct WatchContext: Codable, Sendable, Equatable {
    public var userId: String
    /// ISO `yyyy-MM-dd`, as the phone resolved it — `LogicalDay`, not midnight.
    public var today: String
    public var schedule: ScheduleContext
    /// The palette the phone is wearing, so the wrist matches without a second
    /// place to set it.
    ///
    /// OPTIONAL AND LAST, and that is the whole payload-versioning story: the
    /// synthesised `Codable` reads it with `decodeIfPresent`, so an old phone's
    /// context (no key) decodes on a new watch as nil — the watch reads nil as
    /// the default theme — and a new phone's context decodes on an old watch,
    /// which ignores the key it does not know. Neither side throws, and neither
    /// side stops receiving the context, which is the failure this file exists
    /// to prevent.
    public var theme: OnyxThemeSpec?
    /// The dozen numbers the complications draw (W7). OPTIONAL AND LAST, the
    /// same story as `theme` one field up: an old phone sends no key and a new
    /// watch reads nil (the complication says "—"), a new phone's key is
    /// ignored by an old watch. Never a second application-context kind — the
    /// channel is ONE slot, and a second kind would overwrite the schedule
    /// every time the numbers moved.
    public var tiles: WatchTiles?

    public init(userId: String, today: String, schedule: ScheduleContext, theme: OnyxThemeSpec? = nil, tiles: WatchTiles? = nil) {
        self.userId = userId
        self.today = today
        self.schedule = schedule
        self.theme = theme
        self.tiles = tiles
    }
}

/// A rest clock, as the other device sees it.
///
/// An END INSTANT rather than a remaining duration, for the same reason
/// `LoggerModel.restEndsAt` is: a duration decays in transit and again while the
/// receiving app is suspended, and both devices' `Date()` are close enough for a
/// three-minute countdown even when their clocks disagree by a second. A
/// remaining-seconds payload would arrive already wrong and would drift further
/// every time the watch slept.
public struct RestPulse: Codable, Sendable, Equatable, Identifiable {
    /// `Identifiable` so the watch can present it with `.fullScreenCover(item:)`
    /// — and keyed on the END INSTANT rather than on the session, so adding 15
    /// seconds re-presents the cover with a fresh countdown task instead of
    /// leaving the old one running against a moved target.
    public var id: Date { endsAt }

    public var sessionId: String
    /// When the countdown reaches zero.
    public var endsAt: Date
    /// The full length it started from, so the receiver can draw the arc.
    public var duration: TimeInterval
    /// The movement it follows — the watch prints "Next: …" under the clock.
    public var exercise: String?

    // ── THE FIVE BELOW ARE OPTIONAL AND LAST, WHICH IS THE WHOLE ────────────
    // ── PAYLOAD-VERSIONING STORY — THE SAME ONE `WatchContext.theme` TELLS ──
    // The synthesised `Codable` reads an optional with `decodeIfPresent` and
    // writes it with `encodeIfPresent`. So an OLD phone's pulse — none of these
    // keys on the wire — decodes on a NEW watch with all five nil, and a NEW
    // phone's pulse decodes on an OLD watch, because a keyed container ignores
    // every key nobody asked it for. Neither side throws and neither side stops
    // seeing the rest clock, which is the failure this file exists to prevent.
    //
    // OPTIONAL is the load-bearing half, and not only for old builds: the watch
    // fills none of these when IT starts a rest (`WatchModel.startRest`), and
    // "not sent" has to stay distinguishable from a value. A non-optional
    // `loadKg = 0` would say ZERO KILOS — which is a real bodyweight set —
    // where nil says "this device did not tell you". The day one of them stops
    // being optional is the day every pulse from an older phone throws
    // `keyNotFound` and the rest cover silently stops appearing on the wrist.
    //
    // LAST is the cheap half, and it is about Swift and not JSON: the keys are
    // names and the encoder sorts them, so declaration order is invisible on
    // the wire. It is the `init` that cares — five trailing parameters
    // defaulted to nil are what let every existing caller keep spelling
    // `RestPulse(sessionId:endsAt:duration:exercise:)` untouched.

    /// What was just lifted, in kilograms — so the wrist can read the set back
    /// without waking the phone.
    ///
    /// Nil twice over: a bodyweight set has no load, and a build that predates
    /// this field sends nothing. Both mean "print no number", so one nil serves.
    public var loadKg: Double?
    /// How many reps that set was.
    public var reps: Int?
    /// The effort logged against it, on the ten-point scale with half rungs
    /// that `Effort.ladder` scrubs — `Double` and not `Int`, because 8.5 is a
    /// rung and 8 is a different one.
    ///
    /// Nil is NOT RATED, which is the outcome of doing nothing on the rest
    /// screen and a legitimate state rather than a missing value to paper over.
    public var rpe: Double?
    /// The instant the session's elapsed clock counts UP from, pauses already
    /// subtracted.
    ///
    /// ── WHY IT IS AN ORIGIN AND NOT `session.startedAt` ─────────────────────
    /// Same field, same name and same reason as
    /// `OnyxWorkoutAttributes.ContentState.timerOrigin` and
    /// `PauseControlling.timerOrigin`: a session paused for eleven minutes is
    /// eleven minutes younger than the wall clock says, and `started_at` on the
    /// row is the wall clock. Sending the MOVED origin is what lets the watch
    /// draw `Text(_:style:.timer)` — ticked by the system, costing nothing
    /// while the wrist is down — and still read the same number as the phone's
    /// hero. An elapsed-seconds payload would arrive stale and drift further
    /// every time the watch slept, which is the argument `endsAt` above already
    /// makes for the rest clock.
    ///
    /// The watch cannot derive this: it may have joined the session late, come
    /// back from a sleep, or never have been the device that started it. Nil
    /// from a phone that predates the field — the wrist then shows no session
    /// timer until the phone updates, which is a missing reading rather than a
    /// wrong one.
    public var timerOrigin: Date?
    /// The wearer's heart rate at the instant this pulse was sent, in beats per
    /// minute — the ONE reading only the wrist can take (W10, decision 3).
    ///
    /// ── WHY IT TRAVELS ON THE REST PULSE AND NOT ON A CHANNEL OF ITS OWN ────
    /// `sendMessage` is immediate-or-not-at-all and needs reachability, which
    /// is exactly right for a number that is worthless four minutes late — and
    /// the rest pulse is already that message. A second kind would be a second
    /// per-second message budget for a reading nobody reads per second: the
    /// phone's deck shows it while you are resting, which is when the pulse
    /// exists.
    ///
    /// It therefore travels in BOTH directions, unlike the four fields above
    /// it. The watch fills it on the pulses it sends itself, and answers a
    /// phone-driven rest with one echo carrying it — see
    /// `WatchModel.receive(_:)`. The phone takes the number and nothing else
    /// (`PhoneWatchBridge.receive`): it does not adopt the watch's clock, and
    /// it never sends in reply, so there is no loop.
    ///
    /// Nil twice over, and both mean "print no number": the sensor has not
    /// settled yet (`WorkoutSessionController.heartRate` is nil before the
    /// first sample), or the build on the other wrist predates this field. A
    /// non-optional 0 would claim a stopped heart.
    public var bpm: Int?

    public init(
        sessionId: String,
        endsAt: Date,
        duration: TimeInterval,
        exercise: String? = nil,
        loadKg: Double? = nil,
        reps: Int? = nil,
        rpe: Double? = nil,
        timerOrigin: Date? = nil,
        bpm: Int? = nil
    ) {
        self.sessionId = sessionId
        self.endsAt = endsAt
        self.duration = duration
        self.exercise = exercise
        self.loadKg = loadKg
        self.reps = reps
        self.rpe = rpe
        self.timerOrigin = timerOrigin
        self.bpm = bpm
    }
}
