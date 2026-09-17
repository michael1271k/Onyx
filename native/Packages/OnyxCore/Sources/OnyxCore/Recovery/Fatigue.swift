import Foundation

/// The fatigue scale — the pure half of the web app's `lib/hooks/useFatigue.ts`.
///
/// ── THREE READINGS A DAY, AND THE MIDDLE TWO MOVE WITH THE DAY ───────────────
/// The old vocabulary was four clock anchors (`morning · noon · evening · eod`)
/// on a day whose shape is set by training. "Evening" on a leg day and
/// "Evening" on a rest day are not the same question, so the slots depend on
/// the day: a training day asks Waking · Before training · After training, a
/// rest day Waking · Midday · Night. What that buys is `delta` — post minus
/// pre, the cost of the session in the only unit the wearer feels.
///
/// It does NOT feed the score: a self-report that moved the daily score would
/// be a number you can talk yourself into. This is a record, not an input.
///
/// The vocabulary is IN THE ORDER A DAY HAPPENS, so `latest` is correct for
/// both day types at once: training reads waking(0) → pre(2) → post(3), rest
/// reads waking(0) → midday(1) → night(4), and both ascend.
/// `CodingKeyRepresentable` so a `[FatigueSlot: Int]` crosses as a JSON OBJECT
/// (`{"pre": 3}`), the shape the web's `FatigueDay` has — without it Swift
/// encodes an enum-keyed dictionary as a flat array.
public enum FatigueSlot: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case waking, midday, pre, post, night

    /// `SLOT_LABEL`.
    public var label: String {
        switch self {
        case .waking: "Waking"
        case .midday: "Midday"
        case .pre:    "Before training"
        case .post:   "After training"
        case .night:  "Night"
        }
    }

    /// One word, for a segmented control — three segments across a phone give
    /// "Before training" about 47 points and it truncates to "Before tr…".
    /// Never used where the slot has to stand on its own; the full `label` is
    /// what a row, a sheet header and VoiceOver say.
    public var short: String {
        switch self {
        case .waking: "Waking"
        case .midday: "Midday"
        case .pre:    "Pre"
        case .post:   "Post"
        case .night:  "Night"
        }
    }
}

/// One level of the scale. The WORD is the control, the SENTENCE is the
/// definition — "Could train the plan, would not chase a record" gives the same
/// answer in March as in August; "moderately tired" does not. Stored 1..5.
/// (The web's `color` is OnyxUI's business and is not carried here.)
public struct FatigueLevel: Codable, Equatable, Sendable {
    public var value: Int
    public var label: String
    /// Short form, for a row that has no space for the sentence.
    public var hint: String
    /// The definition. What you could or would DO at this level.
    public var detail: String
}

/// A stored `fatigue_logs` row, as the fold needs to see it.
public struct FatigueRow: Codable, Equatable, Sendable {
    public var slot: String
    public var level: Int
    public init(slot: String, level: Int) { self.slot = slot; self.level = level }
}

/// The day's summary reading.
public struct FatigueReading: Codable, Equatable, Sendable {
    public var slot: FatigueSlot
    public var level: Int
}

/// A day's readings, slot → level. Absent slots simply were not logged.
public typealias FatigueDay = [FatigueSlot: Int]

public enum Fatigue {

    /// `FATIGUE_SLOTS` — the whole vocabulary, in the order a day happens.
    public static let slots: [FatigueSlot] = FatigueSlot.allCases
    /// What a rest day asks.
    public static let restSlots: [FatigueSlot] = [.waking, .midday, .night]
    /// What a training day asks.
    public static let trainingSlots: [FatigueSlot] = [.waking, .pre, .post]

    /// The three slots a day of this kind asks for, in the order it asks them.
    public static func slotsForDay(isTraining: Bool) -> [FatigueSlot] {
        isTraining ? trainingSlots : restSlots
    }

    /// The old keys, and the slot each one stands in for. `noon` and `evening`
    /// resolve DIFFERENTLY on a training day — a reading taken at noon on a leg
    /// day was taken before training, whatever the row happens to be called.
    private static let legacySlots: [String: (rest: FatigueSlot, training: FatigueSlot)] = [
        "morning": (.waking, .waking),
        "noon": (.midday, .pre),
        "evening": (.night, .post),
        // `eod` folds onto the same slot as `evening` and WINS when both exist:
        // it is the later reading, and the later reading is the one the day ended on.
        "eod": (.night, .post),
    ]

    /// Stored keys that fold onto the same slot, later-wins. Higher = later.
    private static let legacyRank: [String: Int] = ["morning": 0, "noon": 1, "evening": 2, "eod": 3]

    /// The modern slot a stored key means on a day of this kind, or nil if unknown.
    public static func normalizeSlot(_ raw: String, isTraining: Bool) -> FatigueSlot? {
        if let modern = FatigueSlot(rawValue: raw) { return modern }
        guard let legacy = legacySlots[raw] else { return nil }
        return isTraining ? legacy.training : legacy.rest
    }

    /// `foldFatigueRows` — a day's stored rows → one reading per slot.
    ///
    /// Which stored key won each slot is tracked, so a fold (`evening` + `eod`
    /// → `night`) resolves to the LATER reading rather than to whichever row
    /// the database happened to hand back second. A modern key always outranks
    /// a legacy one; an equal rank does not displace (`>=`), so the first of
    /// two identical modern keys wins.
    public static func foldRows(_ rows: [FatigueRow], isTraining: Bool) -> FatigueDay {
        var out: FatigueDay = [:]
        var wonBy: [FatigueSlot: Int] = [:]
        for r in rows {
            guard let slot = normalizeSlot(r.slot, isTraining: isTraining) else { continue }
            let rank = legacyRank[r.slot] ?? 99
            if let won = wonBy[slot], won >= rank { continue }
            wonBy[slot] = rank
            out[slot] = r.level
        }
        return out
    }

    /// `FATIGUE_LEVELS`.
    public static let levels: [FatigueLevel] = [
        FatigueLevel(value: 1, label: "Amazing", hint: "could add a rep", detail: "Could add a rep to everything today."),
        FatigueLevel(value: 2, label: "Good", hint: "nothing would stop a session", detail: "Normal. Nothing here would stop a planned session."),
        FatigueLevel(value: 3, label: "Okay", hint: "the plan, not a PR", detail: "Could train the plan, would not chase a record."),
        FatigueLevel(value: 4, label: "Tired", hint: "stairs register", detail: "Stairs register. The warm-up would decide whether to train."),
        FatigueLevel(value: 5, label: "Exhausted", hint: "would cancel", detail: "Would cancel."),
    ]

    /// `fatigueLevel` — nil for an unlogged slot or a value off the scale.
    public static func level(_ value: Int?) -> FatigueLevel? {
        levels.first { $0.value == value }
    }

    /// `fatigueDelta` — the session's cost, `post` − `pre`. Nil on a rest day
    /// and on any training day missing either end: a delta against an absent
    /// reading looks like a measurement and is not one.
    public static func delta(_ day: FatigueDay) -> Int? {
        guard let pre = day[.pre], let post = day[.post] else { return nil }
        return post - pre
    }

    /// `latestFatigue` — the LATEST slot logged, not the mean. A mean of "Fresh
    /// at 7am, Empty at 9pm" is "Worn", which describes neither moment.
    public static func latest(_ day: FatigueDay) -> FatigueReading? {
        for slot in slots.reversed() {
            if let level = day[slot] { return FatigueReading(slot: slot, level: level) }
        }
        return nil
    }

    // MARK: - The clock (W10)

    /// Where a rest day's Waking ends and its Night begins, in minutes since
    /// local midnight. 18:30 also stands in for a session that never ended.
    public static let morningEndsMinutes = 11 * 60
    public static let eveningFromMinutes = 18 * 60 + 30

    /// Which of the day's slots the card is ASKING for now.
    ///
    /// ── THE QUESTION FOLLOWS THE SESSION, NOT THE CLOCK ─────────────────────
    /// A training day is shaped by its session: it asks "Before training"
    /// until the session ends and "After training" from then on, whatever the
    /// hour. Only when no session has ended does the clock stand in — 18:30,
    /// past which a day without a session is being asked how it finished.
    /// A rest day has no session to follow, so it reads the clock alone:
    /// Waking until 11:00, Midday until 18:30, Night after; it never asks the
    /// pre-session question. A day that has already happened asks its LAST
    /// slot — the day ended, and a late reading is about how it finished.
    ///
    /// `sessionEndedMinutes` is the session's end as minutes since local
    /// midnight, derived by the caller from the stored row — never from
    /// `Date()` — so the shot loop and the tests read one day twice and get
    /// one answer. This picks the QUESTION only. `dayMean` still reads every
    /// slot the day holds (`STRESS_MODEL.md` §2), and nothing here feeds it.
    public static func askingSlot(isTraining: Bool, clock: DayClock, sessionEndedMinutes: Int? = nil) -> FatigueSlot {
        let slots = slotsForDay(isTraining: isTraining)
        guard let now = clock.nowMinutes else { return slots.last ?? .night }
        if isTraining {
            return now >= (sessionEndedMinutes ?? eveningFromMinutes) ? .post : .pre
        }
        if now < morningEndsMinutes { return .waking }
        return now < eveningFromMinutes ? .midday : .night
    }

    /// The end `delta` is missing for want of — when exactly one end is
    /// logged. Nil when the delta exists, and nil when neither end is: there
    /// is nothing to compare yet, and naming one of two absent readings would
    /// be a guess. A rest day's fold yields `pre`/`post` only from a MODERN row
    /// written while the day was still a training day, so the card also checks
    /// the named slot is one the day has.
    public static func deltaMissing(_ day: FatigueDay) -> FatigueSlot? {
        switch (day[.pre], day[.post]) {
        case (nil, .some): .pre
        case (.some, nil): .post
        default: nil
        }
    }

    /// `fatigueDayMean` — the mean over every slot logged: the stress index's
    /// self-report term (E3), and deliberately NOT the tracker's summary. The
    /// index asks how heavy the whole day felt; the shape of the curve is that
    /// answer. Nil when nothing was logged; never a zero standing in.
    public static func dayMean(_ day: FatigueDay) -> Double? {
        let levels = slots.compactMap { day[$0] }
        return levels.isEmpty ? nil : Double(levels.reduce(0, +)) / Double(levels.count)
    }
}
