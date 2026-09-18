import Foundation
import OnyxCore
import OnyxUI

/// Effort, in words — the vocabulary the logger and the finish sheet share.
///
/// ── PORTED, NOT INVENTED ────────────────────────────────────────────────────
/// Every value here comes from the web app's `lib/training/effort.ts` and
/// the web app's `lib/training/setTags.ts` in the web app, unchanged. That matters more
/// than it looks: `workout_sets.rpe` is `numeric(3,1)` and holds 2,190 rows
/// rated on THAT ladder, `workout_sessions.session_rpe` holds the CR-10 the
/// battery reads, and `workout_sets.quality` has a CHECK constraint listing
/// exactly the six keys below. A second, prettier vocabulary on this side would
/// not be a redesign; it would be rows the two apps disagree about the meaning
/// of.
///
/// ── AND WHY THERE ARE THREE SCALES AND NOT ONE ──────────────────────────────
/// They answer different questions and the numbers say so.
///
///   · `RpeLadder`  — per SET, reps-in-reserve. Clusters at 8–9.5 on any
///     hypertrophy block, which is what makes its eight stops worth having.
///   · `Cr10`       — per SESSION, Borg's ratio scale. Its own anchors, because
///     "how hard was that set" and "how hard was the whole session" are not the
///     same question: across this athlete's log the mean per-set rating is 8.86
///     and the mean session rating 7.16.
///   · `SetQuality` — HOW it went, not how hard. A second axis on purpose: a
///     warm-up can be sloppy, and folding technique into `set_type` would give
///     every consumer of "is this a working set" an opinion about form.
enum RpeLadder {

    /// One rung. `value` is what lands in `workout_sets.rpe`.
    struct Stop: Identifiable, Hashable, Sendable {
        let value: Double
        let label: String
        /// Reps-in-reserve gloss — the question you can actually answer.
        let hint: String

        var id: Double { value }
    }

    /// The eight stops, hardest last.
    ///
    /// All already on the 0.5 grid the column stores, so this needed no
    /// migration and no backfill: a row holding a bare 8 lights the fourth rung
    /// and reads "Challenging" rather than borrowing CR-10's "Very hard". The
    /// stored number does not move.
    ///
    /// 8.0 exists because the seven-rung ladder was widest exactly where a
    /// hypertrophy block spends most of its sets — Medium 7.5 to Hard 8.5 was a
    /// full point, while the top crammed four rungs into the 1.5 above it. A
    /// set with three clean reps left and one with two are different sets.
    static let stops: [Stop] = [
        Stop(value: 5,   label: "Very Easy",  hint: "5+ reps left"),
        Stop(value: 6.5, label: "Easy",       hint: "~4 left"),
        Stop(value: 7.5, label: "Medium",     hint: "3 left"),
        Stop(value: 8,   label: "Challenging", hint: "2–3 left"),
        Stop(value: 8.5, label: "Hard",       hint: "2 left"),
        Stop(value: 9,   label: "Very Hard",  hint: "1 left"),
        Stop(value: 9.5, label: "Max Effort", hint: "0 left, form held"),
        Stop(value: 10,  label: "Failure",    hint: "missed or form broke"),
    ]

    /// The rung a stored value sits on, or nil for one between rungs.
    ///
    /// Off-ladder values are load-bearing, not an edge case: rows written before
    /// the ladder existed hold 6, 7 and 9.5-less halves, and none of them may
    /// render as a dash.
    static func stop(for value: Double?) -> Stop? {
        guard let value else { return nil }
        return stops.first { $0.value == value }
    }

    /// A word for every rating: the exact rung where there is one, the CR-10
    /// anchor otherwise.
    static func label(_ value: Double?) -> String? {
        guard let value else { return nil }
        return stop(for: value)?.label ?? Cr10.label(value)
    }

    /// `9 · Very Hard`, which is what the row prints. The number alone means
    /// nothing to anyone who has not memorised the ladder, and the word alone
    /// loses the half-steps.
    static func readout(_ value: Double?) -> String? {
        guard let value, let label = label(value) else { return nil }
        return "\(OnyxFormat.rpe(value)) · \(label)"
    }
}

// MARK: - CR-10

/// Borg CR-10 — the SESSION scale, shared with `cardio_logs.effort`.
enum Cr10 {

    static let min = 1.0
    static let max = 10.0

    /// Verbal anchors. Only the canonical CR-10 points are named; everything
    /// between them takes the nearest anchor at or BELOW it, so every rating
    /// gets a word and none of them overstates.
    static let anchors: [(value: Double, label: String)] = [
        (1, "Very light"),
        (2, "Light"),
        (3, "Moderate"),
        (4, "Somewhat hard"),
        (5, "Hard"),
        (7, "Very hard"),
        (9, "Extremely hard"),
        (10, "Maximal"),
    ]

    static func label(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        var out = anchors[0].label
        for anchor in anchors where value >= anchor.value { out = anchor.label }
        return out
    }

    /// Clamp and snap to the 0.5 grid the column stores.
    static func normalise(_ value: Double) -> Double {
        Swift.min(max, Swift.max(min, (value * 2).rounded() / 2))
    }
}

// MARK: - Set quality

/// A set's TECHNIQUE, when it was worth recording.
///
/// ── WHY NULL IS "CLEAN" ─────────────────────────────────────────────────────
/// Storing a default would make every set ever logged carry a claim about its
/// form that nobody made. Absence means "not reported", which is the truth —
/// the same rule as `weighin_skip_reason`, resolved on read.
///
/// A closed vocabulary because counting is the entire point: "swung the last
/// few" and "used a bit of body english" are the same observation and would
/// never group. The six below are the six the database's CHECK constraint
/// holds, in its order.
enum SetQuality: String, CaseIterable, Identifiable, Sendable {
    case momentum
    case partialRom = "partial_rom"
    case formBreakdown = "form_breakdown"
    case neededWarmup = "needed_warmup"
    case assisted
    case cutShort = "cut_short"

    var id: String { rawValue }

    /// Shown on the row and on the chip. Kept to two words.
    var label: String {
        switch self {
        case .momentum:      "Momentum"
        case .partialRom:    "Short ROM"
        case .formBreakdown: "Form broke"
        case .neededWarmup:  "Cold start"
        case .assisted:      "Assisted"
        case .cutShort:      "Cut short"
        }
    }

    /// The whole sentence, for the sheet's hint line and for VoiceOver.
    var full: String {
        switch self {
        case .momentum:      "Used body English to move the load"
        case .partialRom:    "Cut the range short to finish the set"
        case .formBreakdown: "The last reps lost position"
        case .neededWarmup:  "The first reps were poor — needed a longer warm-up"
        case .assisted:      "A spotter or the other arm helped"
        case .cutShort:      "Stopped before the target for a reason other than failure"
        }
    }

    // MARK: - More than one of them at a time

    /// A set can be several of these at once — "used momentum AND cut the range
    /// short" is one set, honestly described, and the sheet used to make you
    /// pick the half that mattered more.
    ///
    /// ── WHY THE COLUMN DID NOT HAVE TO CHANGE SHAPE ─────────────────────────
    /// `workout_sets.quality` is `text` with a CHECK constraint listing these
    /// six keys, and it holds rows on both clients. A second column would have
    /// meant a nullable array threaded through `SetSnapshot`, `SetPatch`,
    /// `SetEventFold`, the projection, the puller, the pusher and two sets of
    /// golden vectors — for a fact that is one short string.
    ///
    /// So the column keeps its shape and gains a grammar: keys joined by `+`,
    /// always in `allCases` order. A set with ONE tag is byte-identical to what
    /// this app has always written, which is what makes the change free — every
    /// existing row still parses, every existing reader still reads, and the
    /// only thing the database needs is a wider CHECK
    /// (`set-quality-tags.sql (git history)`). Until that is applied a combination is
    /// refused by Postgres and a single tag still syncs, which is the failure
    /// worth having: partial, loud, and never silently wrong.
    ///
    /// ── AND WHY `+` AND NOT `·` ─────────────────────────────────────────────
    /// The export's field separator is `·` and it has already produced two
    /// malformed-token bugs (P3 E5). A separator that cannot appear in a key
    /// AND cannot collide with a separator one layer up is the whole
    /// requirement; `+` is in neither alphabet.
    /// The grammar itself lives in `SetTags` (OnyxCore) — ONE parser for the
    /// column, shared with the store and the export. These two are the typed
    /// view over it and add nothing.
    static let separator: Character = SetTags.qualitySeparator

    /// The stored string, in canonical order. `nil` for an empty list.
    static func join(_ tags: [SetQuality]) -> String? {
        SetTags.joinQuality(tags.map(\.rawValue))
    }

    /// Read a stored value back. Unknown keys are dropped, never fatal.
    static func parse(_ raw: String?) -> [SetQuality] {
        SetTags.parseQuality(raw).compactMap(SetQuality.init(rawValue:))
    }

    /// What the row's dot and VoiceOver say when there are several.
    static func summary(_ tags: [SetQuality]) -> String? {
        let ordered = allCases.filter(tags.contains)
        guard !ordered.isEmpty else { return nil }
        return ordered.map(\.label).joined(separator: ", ")
    }
}

// ── SESSION EFFORT LIVES IN OnyxCore ────────────────────────────────────────
//
// `EffortWord` and `EffortWords.all` used to be declared here as well, byte for
// byte the same five rungs as `Effort.words` in OnyxCore — which is the copy
// the WEB is vector-equal with (the web app's `lib/training/effort.ts`, `EFFORT_WORDS`)
// and the one `Effort.suggestEffortWord` and `Effort.effortCr10` are written
// against. Nothing in the app target ever read the local pair, so it was five
// hard-coded CR-10 values waiting to disagree with the ones that are actually
// stored. Deleted in P3 U3, when the finish sheet started needing the
// suggestion: `import OnyxCore` and use `Effort.words`.
