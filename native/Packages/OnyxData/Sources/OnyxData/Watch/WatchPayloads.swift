import Foundation
import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The values that cross between the phone and the watch.
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
/// ── THE CATALOGUE IS ON A DIET (W6) ─────────────────────────────────────────
/// Every program used to ride along — three decks × six days × seven
/// movements, each with its resolved movers, on every push, for a wrist that
/// renders ONE of those days. `WatchContext.init` now keeps the active program
/// in `schedule.programs` and moves everything else into `swapPool`: a flat,
/// name-deduplicated list of the movements the swap sheet may offer, with no
/// program and no day wrapped around them. The watch is the only reader of
/// the rest of the catalogue and the swap sheet is the only thing it does with
/// it (`WatchModel.swapCandidates`), so nothing else notices.
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
    /// EVERY movement in the catalogue, flat and deduplicated by name — the
    /// swap sheet's whole input, without the decks around it.
    ///
    /// ── WHY IT INCLUDES THE ACTIVE PROGRAM'S OWN MOVEMENTS ──────────────
    /// A first draft seeded the dedupe with today's deck and carried only the
    /// other programs, on the reasoning that the active program is already on
    /// the wire. It is — but the watch then read the two lists in the order
    /// `[active] + pool`, and a movement whose NAME appears in both the active
    /// program and an earlier one resolved to the active program's copy where
    /// the old code resolved to whichever came first in `schedule.programs`.
    /// Those two copies can carry different set counts, seed loads and rest
    /// targets, and `swap` installs whichever it is handed — so the diet would
    /// have quietly changed a prescription. Built off the whole list in its
    /// original order, first occurrence winning, it is the same list the watch
    /// always had, minus the `Program`/`ProgramDay` shells.
    ///
    /// OPTIONAL AND LAST, the third time this file tells that story. An old
    /// phone sends no key, and a new watch falls back to `schedule.programs`,
    /// which that phone still fills. A new phone's key is ignored by an old
    /// watch, which then offers swaps only from the active program — fewer
    /// candidates, never a wrong one, and never a decode failure.
    public var swapPool: [ProgramExercise]?
    /// Is a session live, finished or thrown away — the PHONE's answer
    /// (overhaul W0, decision Q1: the phone owns the lifecycle). The watch
    /// reads it at launch and after any missed pulse, so "Start" is never
    /// offered for a session the phone already closed. OPTIONAL AND LAST, the
    /// fourth time: an old phone sends no key (nil = "no word", the watch
    /// falls back to its own rows), an old watch ignores it. No sender yet —
    /// Lane A pushes it, unthrottled, on open/finish/discard.
    public var session: SessionLifecycle?

    /// Trims the schedule on the way in: nothing outside this initialiser has
    /// to remember the diet, and nothing can send the full catalogue by
    /// accident.
    public init(userId: String, today: String, schedule: ScheduleContext, theme: OnyxThemeSpec? = nil,
                tiles: WatchTiles? = nil, session: SessionLifecycle? = nil) {
        self.userId = userId
        self.today = today
        self.session = session
        var trimmed = schedule
        let active = schedule.activeProgram
        // `activeProgram` synthesises an EMPTY program when the id matches
        // nothing. Keeping the list as it was in that case is the safe read:
        // trimming to that empty one would leave the watch with no deck.
        if schedule.programs.contains(where: { $0.id == active.id }) {
            trimmed.programs = [active]
        }
        self.schedule = trimmed
        self.theme = theme
        self.tiles = tiles
        // Deduplicated on `ProgramExercise.id`, which IS the name (see its
        // header) — the same key the swap sheet already dedupes on, so a
        // movement that appears in four days crosses the wire once. The order
        // is `schedule.programs`' own, unsorted, because that order IS the
        // tie-break the watch has always resolved duplicate names by.
        var seen = Set<String>()
        var pool: [ProgramExercise] = []
        for exercise in schedule.programs.flatMap(\.days).flatMap(\.exercises)
        where seen.insert(exercise.id).inserted {
            pool.append(exercise)
        }
        self.swapPool = pool.isEmpty ? nil : pool
    }
}

/// A session opening, finishing or being thrown away on the other device
/// (App Store W4).
///
/// ── IT CARRIES THE ROW, BECAUSE THE EVENTS NEED ONE ─────────────────────────
/// `set_events.session_id` is a foreign key to `workout_sessions`. The watch
/// has no Supabase to pull a session row from, and before this the link
/// carried events and nothing else — so every set the other device logged was
/// refused by the receiving store's constraint (a `try?` on the wrist). A
/// signal saying "a workout started" would not have fixed that. The row's
/// identity travels, the receiver inserts it under the SAME id
/// (`AppDatabase.receiveSession`), and the events behind it have a parent.
///
/// ── ONE TYPE FOR EVERY PHASE, AND WHY ───────────────────────────────────────
/// A finish and a discard both have to name a row the receiver may never
/// have seen, so they carry the same fields an open does. One struct and a
/// phase is one decoder for the version-skew story `WatchContext` tells.
public struct SessionPulse: Codable, Sendable, Equatable {
    public enum Phase: String, Codable, Sendable {
        case open, finished, discarded
        /// Watch → phone only: "my `HKWorkoutSession` is running for this
        /// session". Sent on every adoption whose workout session actually
        /// started, and it never creates a row — see `PhoneWatchBridge.joined`
        /// for the duplicate `HKWorkout` it prevents.
        case joined
    }

    public var phase: Phase
    public var sessionId: String
    public var userId: String
    public var dayKey: String?
    public var date: String
    public var startedAt: Date?
    /// The sender's finish instant. Nil on an open and a discard.
    public var endedAt: Date?
    /// The rest the last movement prescribed, for `closeSession`'s long-idle
    /// guard — the one input to `duration_min` the receiver cannot read off
    /// its own copy of the log. Nil takes the default, as it does locally.
    public var restTargetSec: Double?
    /// How many `set_events` the SENDER holds for this session when it
    /// finished it (overhaul Lane A, decision Q1). Set on a phone finish only,
    /// and that is what lets the finish ALSO travel as a message: the
    /// receiver applies a finish that carries it only once its own log has
    /// caught up to the count (`AppDatabase.finishIsReady`) or after
    /// `finishGrace` — so the rule "a finish never overtakes the queued sets"
    /// still holds while the wrist hears about it in a second instead of
    /// whenever the queue drains. OPTIONAL AND LAST: an old peer sends and
    /// reads none, and a nil finish is applied at once, as it always was.
    public var expectedEventCount: Int?

    /// The longest a messaged finish waits for the queue behind it. Five
    /// seconds, the brief's number: long enough for a queue that IS draining,
    /// and short enough that a simulator — whose queue never drains — still
    /// shows the banner.
    public static let finishGrace: TimeInterval = 5

    public init(_ session: WorkoutSession, phase: Phase, restTargetSec: Double? = nil, expectedEventCount: Int? = nil) {
        self.phase = phase
        self.sessionId = session.id
        self.userId = session.userId
        self.dayKey = session.dayKey
        self.date = session.date
        self.startedAt = session.startedAt
        self.endedAt = phase == .finished ? session.endedAt : nil
        self.restTargetSec = restTargetSec
        self.expectedEventCount = phase == .finished ? expectedEventCount : nil
    }
}

/// The phone's word on today's session, as STATE (overhaul W0, decision Q1).
///
/// `SessionPulse` is the EVENT — queued, ordered behind the sets, and on a
/// simulator not delivered to a running app at all. This is the latest-state
/// slot that rides `WatchContext.session`: whatever the queue has or has not
/// delivered, the context says whether the session is open, finished or
/// discarded, and a finished one carries its `SessionMasthead` for the wrist's
/// banner. Its own `Phase` rather than `SessionPulse.Phase`, because `joined`
/// is a watch → phone event and never a state the phone publishes.
public struct SessionLifecycle: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, CaseIterable, Sendable {
        case open, finished, discarded
    }

    public var sessionId: String
    public var phase: Phase
    public var startedAt: Date
    /// Nil while open, and on a discard.
    public var endedAt: Date?
    /// The finished session in one line. Nil unless `phase == .finished`.
    public var summary: SessionMasthead?
    /// The row's `date` and `day_key` (overhaul Lane A). OPTIONAL AND LAST,
    /// the `WatchContext` story: what lets the wrist JOIN a session whose
    /// queued open never arrived — it can build the row from the context
    /// alone — and ask "is this today's?" by the phone's own date rather
    /// than by a clock reading of `startedAt`.
    public var date: String?
    public var dayKey: String?

    public init(sessionId: String, phase: Phase, startedAt: Date, endedAt: Date? = nil, summary: SessionMasthead? = nil,
                date: String? = nil, dayKey: String? = nil) {
        self.sessionId = sessionId
        self.phase = phase
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summary = summary
        self.date = date
        self.dayKey = dayKey
    }
}

/// A provisional RPE the watch's Crown is scrubbing during rest (overhaul W0,
/// decision Q2). Watch → phone, `sendMessage` only (`WatchLink.send(effort:)`):
/// worthless a second late, and NEVER persisted — the set's tick commits the
/// real `rpe` through the event log as it always has. The phone draws `band`
/// as provisional ink on the deck card.
public struct EffortPulse: Codable, Hashable, Sendable {
    public var sessionId: String
    public var exerciseId: String
    public var setIndex: Int
    /// On the 0.5 grid `Effort.ladder` scrubs.
    public var rpe: Double
    public var band: EffortBand

    /// `band` defaults to the ladder's own fold of `rpe`.
    public init(sessionId: String, exerciseId: String, setIndex: Int, rpe: Double, band: EffortBand? = nil) {
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.rpe = rpe
        self.band = band ?? EffortBand(rpe: rpe)
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
