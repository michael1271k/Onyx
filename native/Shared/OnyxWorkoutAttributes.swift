import Foundation
import ActivityKit

/// The shape of a running workout, on the Lock Screen and in the Dynamic Island.
///
/// ── THIS FILE IS IN TWO TARGETS, AND IT HAS TO BE ───────────────────────────
/// `Onyx` and `OnyxWidgets`. ActivityKit matches the app's
/// `Activity.request` to the extension's `ActivityConfiguration` **by the
/// attributes type**, and two identically-named structs compiled into two
/// modules are two different types. Getting this wrong does not fail to build:
/// the activity starts, and nothing draws.
///
/// `project.yml` lists `Shared/` as a source of both targets, which is the
/// generated-project equivalent of ticking two boxes — and the reason the
/// project file is generated at all.
///
/// ── AND WHY THIS ONE CROSSES A LINE `OnyxSnapshot` CANNOT ──────────────────
/// App Groups are a PAID capability, which is why the old web-shell widgets
/// fetched their own data over HTTP rather than reading anything the app wrote. That
/// constraint is about SHARED STORAGE, and a Live Activity uses none: the
/// content travels through ActivityKit itself, from `Activity.update` in the
/// app to the extension's view body, with no container in between. Nothing is
/// persisted, nothing is fetched, and there is no token to keep fresh.
struct OnyxWorkoutAttributes: ActivityAttributes {

    /// ── WHY ALMOST EVERY FIELD IS A STRING ──────────────────────────────────
    /// The consumer is a SwiftUI view whose whole job is to draw text, and the
    /// producer already owns the formatting rules — a cable stack really is
    /// 13.75 kg and rounding it to 13.8 on a Lock Screen means the number you
    /// read is not the number you logged. Re-deriving those rules on the far
    /// side of ActivityKit would be a second implementation allowed to
    /// disagree with the first.
    struct ContentState: Codable, Hashable {
        /// The movement you are walking towards. "Seated Cable Row (Wide Grip)".
        var exercise: String
        /// Which set of it, already composed: "Set 3 of 4".
        var setLabel: String
        /// THIS set's load, pre-formatted: "42.5 kg × 12".
        ///
        /// The card LEADS with this. History used to be the largest thing on
        /// the face while the set you were standing in front of went unnamed —
        /// history is context for a decision, not the decision itself. Empty
        /// while the row is blank, and weight-only while the reps are still
        /// being typed, which is the state the card is in during every set.
        var load: String
        /// THIS set's effort: "RPE 8". Empty until it is rated.
        var rpe: String
        /// What you did on this set number last time: "40 kg × 12". Empty when
        /// the movement is new — a Lock Screen has no room to say "no data"
        /// politely.
        var lastTime: String
        /// Live session tonnage, formatted. "1 074 kg".
        var volume: String
        /// Working sets ticked, and what the deck prescribes.
        ///
        /// ── WHY TWO INTEGERS AND NOT ONE STRING ─────────────────────────────
        /// Every other field here is pre-formatted because the card only ever
        /// draws it. These two are the exception on purpose: the card draws a
        /// PROGRESS — "9 of 22", a ring, a bar — and a progress needs the two
        /// numbers apart to divide them. "12" arriving as text was why the Lock
        /// Screen could say how much you had done and never how much was left.
        var setsDone: Int
        var setsPlanned: Int
        /// Records claimed in THIS session. Zero renders as NOTHING: a permanent
        /// gold zero is how gold stops meaning a personal record.
        var prsThisSession: Int
        /// The movement you are resting BEFORE, and what it asks for.
        ///
        /// ── WHY THE CARD CHANGES SUBJECT WHILE RESTING ──────────────────────
        /// The set you just finished is the one fact you already know — you
        /// were standing over it thirty seconds ago. What you cannot see from
        /// the rack is what is next and what it cost last time, which is the
        /// decision the rest period exists for. So while `restEndsAt` is set
        /// the card names the NEXT lift; the moment rest ends it goes back to
        /// the set in front of you.
        ///
        /// ── AND WHY ALL THREE ARE OPTIONAL ──────────────────────────────────
        /// The same reason `timerOrigin` is, and it is not a style choice: a
        /// running activity outlives an app update and ActivityKit decodes the
        /// card it already holds with the NEW type. A synthesized `Decodable`
        /// requires every non-optional key, so a required field added here
        /// would fail that decode, `Activity.activities` would not hand the
        /// card back, and the next launch would request a second card beside an
        /// orphan nothing can end.
        ///
        /// They are also nil on the LAST set of the session, which has no next
        /// lift — the card falls back to the current set, which is correct
        /// rather than a placeholder.
        var nextExercise: String?
        /// What that lift cost last time, as a rating: "RPE 9". Nil when the
        /// movement is new, or when the previous set was never rated.
        ///
        /// `lastTime` above already carries the previous LOAD and it has been
        /// computed since the card existed — the Lock Screen simply never drew
        /// it. The rating is the half that was genuinely missing: "40 kg × 12"
        /// tells you what you lifted and nothing about whether it was close.
        var lastRpe: String?
        /// When the current rest period ends, so the card can count it down
        /// itself with a `Text(_:style:)` timer. `nil` means not resting, which
        /// is not the same as a timer at zero.
        var restEndsAt: Date?
        /// The instant the elapsed clock counts UP from, pauses already
        /// subtracted — `startedAt + pausedTotal`, not `attributes.startedAt`.
        ///
        /// ── WHY THE ORIGIN AND NOT AN ELAPSED NUMBER ────────────────────────
        /// `attributes.startedAt` is fixed for the life of the activity, and a
        /// session that was paused for eleven minutes is eleven minutes younger
        /// than the wall clock says. Sending a MOVED origin keeps the card's
        /// clock a `Text(_:style:.timer)` — counted by the system, costing no
        /// updates — while still being the same number the phone shows. Sending
        /// elapsed seconds instead would need an update every second, which is
        /// exactly the budget ActivityKit rations.
        ///
        /// ── AND WHY ALL THREE ARE OPTIONAL ──────────────────────────────────
        /// A running activity outlives an app update, and ActivityKit decodes
        /// the card it already holds with the NEW type. A synthesized
        /// `Decodable` requires every non-optional key, so adding three of them
        /// would fail that decode — `Activity.activities` would not hand the
        /// card back, `start()` could not adopt it, and the next launch would
        /// request a SECOND card beside an orphan nothing can end. Optional is
        /// what makes the decoder tolerant of its own past.
        var timerOrigin: Date?
        /// Whether the session is stopped. A system timer cannot be, so the card
        /// draws `elapsed` instead while this is true.
        var isPaused: Bool?
        /// The frozen reading, pre-formatted — "48:12". Meaningful only while
        /// `isPaused`; the producer owns the formatting, as it does for every
        /// other string here.
        var elapsed: String?
        /// Cumulative session tonnage after each completed set, oldest first.
        ///
        /// The one non-scalar field, and the exception earns itself: a
        /// sparkline is a SHAPE and a shape cannot be pre-rendered into text
        /// the way a load can. Capped at 12 points by the producer —
        /// ActivityKit budgets updates by payload size as well as by frequency,
        /// and a chart that grew without bound would cost more the longer the
        /// session ran, which is exactly backwards.
        var spark: [Double]
        /// THIS set's effort as a NUMBER, so the badge can be tinted with the
        /// same ramp the effort picker uses.
        ///
        /// ── WHY BOTH THIS AND `rpe` ─────────────────────────────────────────
        /// `rpe` is the pre-formatted string and stays the thing that is DRAWN —
        /// the producer owns formatting, and "RPE 8.5" must not become "8.5" or
        /// "9" on the far side. This is the same fact in the one other register
        /// the card needs it in: `Color.onyx.effort` takes a Double, and parsing
        /// a number back out of a label the producer composed would be a second
        /// implementation of a formatting rule, allowed to disagree.
        ///
        /// Optional, like every field added after the first release — see
        /// `timerOrigin` for what a required key does to a running activity.
        var rpeValue: Double?
        /// How long the CURRENT rest was set to run, in seconds — the
        /// prescription plus whatever ±15 s has been applied to this set.
        ///
        /// Sent so the card can draw a bar that is honest about the whole
        /// period rather than about the slice it happened to be opened during.
        /// Nil while not resting, and on a card encoded before this existed.
        var restTotalSec: Int?
        /// The workout's own day key — "cb_b", "legs_a".
        ///
        /// ── WHY A KEY AND NOT A COLOUR ──────────────────────────────────────
        /// It used to be `ProgramDay.accent`, a raw `0xRRGGBB` from the Phase-1
        /// palette, sent so the card and the deck header could not drift. They
        /// drifted anyway the moment Onyx re-keyed the day colours (§3.2): the
        /// deck read `Color.onyx.day(key)` and the Lock Screen still carried
        /// last year's orange. Sending the KEY and letting both sides resolve it
        /// through the one token function is what actually makes drift
        /// impossible — the colour has exactly one definition again.
        var dayKey: String
    }

    /// The workout's name — fixed for the life of the activity, which is
    /// exactly what `ActivityAttributes` (as opposed to `ContentState`) is for.
    var title: String
    var startedAt: Date
}
