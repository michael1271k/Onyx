import Foundation

/// Psychological stress, self-reported — the `stress_logs` vocabulary.
///
/// ── WHY THIS IS NOT A SECOND FATIGUE SCALE ──────────────────────────────────
/// `Fatigue` asks what the BODY could do. This asks what is on your mind, and
/// the two answer differently on the same day — a calm week of heavy training
/// and a light week in the middle of a house move both exist, and one
/// self-report cannot separate them. Founder decision 3 gives psych stress its
/// own table and folds it into the Stress index's `self` term beside fatigue
/// (D6, `Stress.breakdown`), where the two are averaged over whichever
/// answered. It is NOT a battery input, and it moves no score.
///
/// ── AN EVENT LOG; THE SLOT IS DERIVED FROM THE EVENT'S TIME ─────────────────
/// Since Live UX W1 (decision A5) `stress_logs` is an event log: any number of
/// rows a day, each stamped `logged_at` with when it was felt, backdating
/// allowed. `StressInputsBuilder` takes the MEAN of the day's rows and does not
/// care how many there are. The three buckets stay because scoring, sorting
/// and the export's legacy rows still name them — but a slot is never chosen:
/// "which part of the day is this about" is a question about the time, and
/// the time already knows (`forMinutes`).
public enum StressSlot: String, Codable, Sendable, CaseIterable {
    case morning, midday, evening

    public var label: String {
        switch self {
        case .morning: "Morning"
        case .midday:  "Midday"
        case .evening: "Evening"
        }
    }

    /// Midday starts at noon, evening at 18:00.
    public static let middayFromMinutes = 12 * 60
    public static let eveningFromMinutes = 18 * 60

    /// Which bucket a minute of the day falls in — the one rule every slot on
    /// a stored row is derived from.
    public static func forMinutes(_ minutesSinceMidnight: Int) -> StressSlot {
        if minutesSinceMidnight < middayFromMinutes { return .morning }
        if minutesSinceMidnight < eveningFromMinutes { return .midday }
        return .evening
    }

    /// Which bucket a reading taken NOW belongs to.
    ///
    /// A day that has already happened files under `evening`: the day ended,
    /// and the answer being given is about the whole of it. A day that has not
    /// started cannot be selected at all (`DayModel.date` never runs ahead), so
    /// `.future` folds onto the same answer rather than inventing a fourth.
    public static func forClock(_ clock: DayClock) -> StressSlot {
        guard let minutes = clock.nowMinutes else { return .evening }
        return forMinutes(minutes)
    }

    /// The bucket's lower boundary in minutes since midnight — where a legacy
    /// row without a time sorts (`PsychStress.sorted`).
    public var startMinutes: Int {
        switch self {
        case .morning: 0
        case .midday:  Self.middayFromMinutes
        case .evening: Self.eveningFromMinutes
        }
    }
}

/// One rung of the 1–5 scale. Same three fields `FatigueLevel` carries, so one
/// control draws both scales (`FiveWordPicker`) — the WORD is what you tap and
/// the HINT is the definition that keeps it meaning the same thing in March as
/// in August.
public struct StressLevel: Codable, Equatable, Sendable {
    public var value: Int
    public var label: String
    public var hint: String

    public init(value: Int, label: String, hint: String) {
        self.value = value
        self.label = label
        self.hint = hint
    }
}

/// What a reading was about. Report-only: nothing scores a tag, and a reading
/// with none is a complete reading.
public enum StressTag: String, Codable, Sendable, CaseIterable {
    case work, study, family, money, health, travel, other

    public var label: String {
        switch self {
        case .work:   "Work"
        case .study:  "Study"
        case .family: "Family"
        case .money:  "Money"
        case .health: "Health"
        case .travel: "Travel"
        case .other:  "Other"
        }
    }

    /// Stored order, never `Set` order — a tag list that reshuffles between two
    /// reads of the same row is a diff on every pull.
    public static func sorted(_ tags: some Collection<StressTag>) -> [StressTag] {
        allCases.filter(tags.contains)
    }
}

/// One `stress_logs` row, as a screen reads it.
///
/// `id` is the ROW's id: two events can share a slot now, so the slot is no
/// longer an identity. `loggedAt` is nil on a row written before W1.
public struct StressReading: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var slot: StressSlot
    public var loggedAt: Date?
    public var level: Int
    public var tags: [StressTag]
    public var note: String?

    public init(id: String, slot: StressSlot, loggedAt: Date? = nil, level: Int, tags: [StressTag] = [], note: String? = nil) {
        self.id = id
        self.slot = slot
        self.loggedAt = loggedAt
        self.level = level
        self.tags = tags
        self.note = note
    }
}

public enum PsychStress {

    /// The scale. 1 is settled and 5 is overwhelmed, so the term centres on 3
    /// the way fatigue does (`StressConstants.fatigueNeutral`) and the two can
    /// be averaged without either being flipped first.
    ///
    /// ── WHY NOT "CALM" AT 1 ─────────────────────────────────────────────────
    /// The Stress TILE sits directly above this row and prints `StressBand`'s
    /// own word for a computed reading — and its lowest band is spelled "Calm".
    /// Two five-point scales on one screen sharing a word, one typed and one
    /// derived, is a screen where neither can be read. "Stressed" is out for
    /// the same class of reason: a rung named after the instrument makes its
    /// neighbours read as modifiers of it rather than as rungs of their own.
    /// The middle word is "Okay" — the same middle as fatigue, deliberately,
    /// because D6 folds the two answers into ONE term.
    ///
    /// The top rung is "Swamped" and not "Overwhelmed" for a measured reason:
    /// at 78 pt the longer word cannot share a phone's width with four others,
    /// so the row that decision 6 is built around became a column of five at
    /// every type size. "Swamped" is 62 pt, plainer English, and unambiguously
    /// above "Strained".
    public static let levels: [StressLevel] = [
        StressLevel(value: 1, label: "Relaxed",     hint: "nothing on it"),
        StressLevel(value: 2, label: "Okay",        hint: "normal background noise"),
        StressLevel(value: 3, label: "Tense",       hint: "holding something"),
        StressLevel(value: 4, label: "Strained",    hint: "carrying more than usual"),
        StressLevel(value: 5, label: "Swamped",     hint: "cannot put it down"),
    ]

    /// Nil for an unlogged reading or a value off the scale.
    public static func level(_ value: Int?) -> StressLevel? {
        levels.first { $0.value == value }
    }

    /// Minutes since local midnight.
    public static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// One day's readings in the order the day happened.
    ///
    /// ── THE RULE ────────────────────────────────────────────────────────────
    /// Sort key = `loggedAt ?? slotStart`, both as minutes of the day: a timed
    /// event sorts by its time, a legacy row without one sorts at its slot's
    /// lower boundary. So a legacy `evening` row (18:00) comes after a 14:32
    /// event and before a 19:05 one — which is the most a row that only knows
    /// its bucket can claim. Stable, so two rows with one key keep stored order.
    public static func sorted(_ readings: [StressReading], calendar: Calendar = .current) -> [StressReading] {
        readings.sorted { a, b in key(a, calendar) < key(b, calendar) }
    }

    private static func key(_ r: StressReading, _ calendar: Calendar) -> Int {
        r.loggedAt.map { minuteOfDay($0, calendar: calendar) } ?? r.slot.startMinutes
    }

    /// The day's LATEST reading — what the row states. The mean is the
    /// index's business; a row that said "3.0" when you answered Relaxed this
    /// morning and Swamped tonight would describe neither moment
    /// (`Fatigue.latest` makes the same choice for the same reason).
    public static func latest(_ readings: [StressReading], calendar: Calendar = .current) -> StressReading? {
        sorted(readings, calendar: calendar).last
    }

    /// Parse a stored tag array, dropping anything this build does not know. A
    /// tag written by a later version costs a chip, never a reading.
    public static func tags(_ raw: [String]) -> [StressTag] {
        StressTag.sorted(Set(raw.compactMap(StressTag.init(rawValue:))))
    }
}
