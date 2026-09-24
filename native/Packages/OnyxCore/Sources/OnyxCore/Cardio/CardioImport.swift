import Foundation

/// Bringing a bout in from Apple Health without logging it twice.
///
/// PURE, and here rather than beside the HealthKit reader, because the rule
/// that decides "this is the walk you already have" writes over a row the user
/// may have typed by hand. That is the one piece of this feature that can
/// destroy something, so it is the piece that gets a golden test and no
/// framework import.
public enum CardioImport {

    /// The kinds the app both imports and offers by hand.
    ///
    /// Strings rather than an enum because `cardio_logs.kind` is a text column
    /// shared with the web app, which writes its own vocabulary into it. A
    /// closed enum here would turn a row written by the other client into a
    /// decode failure — a bout that exists and cannot be read — where a string
    /// is merely a kind this build has no glyph for.
    public static let walk = "walk"
    /// An INDOOR walk (overhaul C2). Health files it as `.walking` with
    /// `HKMetadataKeyIndoorWorkout`; the reader never read the key, so every
    /// treadmill bout came in as a walk and the warm-up card named it "Walk".
    public static let treadmill = "treadmill"
    public static let run = "run"
    public static let cycling = "cycling"
    public static let rowing = "rowing"
    public static let elliptical = "elliptical"
    public static let hiit = "hiit"

    /// Display order. Walk and run lead because they are the two the founder
    /// logs; the rest follow in descending likelihood rather than alphabetically,
    /// which would put `cycling` above the two that matter.
    public static let offered = [walk, treadmill, run, cycling, rowing, elliptical, hiit]

    /// Whether two kinds can be ONE bout. Exact, except that a walk and a
    /// treadmill are the same activity told apart by one metadata key — so a
    /// row filed as `walk` before the key was read still matches the treadmill
    /// bout Health now describes, rather than being imported a second time.
    public static func sameActivity(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let foot: Set<String> = [walk, treadmill]
        return foot.contains(a) && foot.contains(b)
    }

    /// How close two bouts must start to be the same bout: five minutes.
    ///
    /// A window and not an equality test because the same walk reaches Health
    /// from a watch and a phone with starts that differ by seconds, and because
    /// a bout typed by hand is typed to the nearest minute.
    public static let duplicateWindow: TimeInterval = 5 * 60

    /// One `cardio_logs` row, reduced to what the duplicate rule reads.
    public struct Existing: Sendable, Equatable {
        public let id: String
        public let date: String
        public let kind: String
        public let durationMin: Double?
        /// For an IMPORTED row this is the bout's own start — see
        /// `matchingRow(hkUuid:kind:start:durationMin:date:in:)` for why the
        /// column carries two meanings and how they are told apart.
        public let createdAt: Date?
        public let fromHealthkit: Bool
        /// `HKWorkout.uuid`, on a row imported after W1. Nil on a hand-typed
        /// row and on every row imported before the column existed.
        public let hkUuid: String?

        public init(
            id: String, date: String, kind: String, durationMin: Double?,
            createdAt: Date?, fromHealthkit: Bool, hkUuid: String? = nil
        ) {
            self.id = id
            self.date = date
            self.kind = kind
            self.durationMin = durationMin
            self.createdAt = createdAt
            self.fromHealthkit = fromHealthkit
            self.hkUuid = hkUuid
        }
    }

    /// The row an incoming bout should OVERWRITE, or nil to insert a new one.
    ///
    /// ── WHY `created_at` CARRIES THE START, AND ONLY SOMETIMES ──────────────
    /// `cardio_logs` has no start-time column and is not getting one: the table
    /// is shared with the web app and adding a column is a paste-into-the-SQL-
    /// editor step this machine cannot perform. `created_at` already exists, is
    /// read by exactly one query (`ORDER BY created_at`, the session page's
    /// bout list), and for an imported row the bout's start is a STRICTLY
    /// BETTER value for that ordering than the instant the import happened —
    /// bouts come back in the order they were performed.
    ///
    /// So an imported row stores the bout's start there. A hand-typed row still
    /// stores the moment it was typed, because that is all it knows.
    ///
    /// ── WHICH GIVES TWO RULES, AND THE SAFE ONE IS THE FUZZY ONE ────────────
    ///   · Against another IMPORTED row, `created_at` is a start on both sides,
    ///     so the founder's five-minute window is applied exactly as asked.
    ///   · Against a HAND-TYPED row, `created_at` is an insertion instant and
    ///     comparing it to a start is meaningless — a walk done at 08:00 and
    ///     typed up at 21:00 is thirteen hours from itself. There, the match is
    ///     same day, same kind, and a duration within the same five minutes.
    ///
    /// ponytail: the fuzzy rule cannot tell two hand-typed 30-minute walks on
    /// one day apart, and will overwrite the first. Given no start column that
    /// is the closest honest reading of "within a 5-minute window", and the
    /// alternative — never matching a manual row — leaves the founder with a
    /// duplicate every time they type a bout up before Health syncs it. A
    /// `started_at` column retires this whole branch.
    ///
    /// ── AND ABOVE BOTH OF THEM, THE KEY (W1) ───────────────────────────────
    /// `HKWorkout.uuid` is the identity Apple already assigns every bout, and
    /// once a row carries it the question "is this the walk you already have"
    /// stops being a guess. It is tried FIRST and, when it hits, wins outright:
    /// a uuid equality cannot be wrong, where both rules below are heuristics
    /// over a table with no start column.
    ///
    /// It is deliberately NOT gated on `kind`. A bout whose activity type this
    /// build maps differently than the build that imported it is still the same
    /// physical bout, and re-inserting it under a new kind is exactly the
    /// duplicate this branch exists to prevent. `date` is not checked either,
    /// because the caller already scopes `existing` to one day — see
    /// `ingestCardio`, which now files a bout under the day it STARTED in.
    ///
    /// Nil `durationMin` on either side never matches: unknown is not equal.
    public static func matchingRow(
        hkUuid: String? = nil,
        kind: String,
        start: Date,
        durationMin: Double?,
        date: String,
        in existing: [Existing]
    ) -> Existing? {
        // The key first. Nil never matches nil: a hand-typed row has no uuid
        // and neither does a pre-migration import, and treating two absences as
        // an equality would collapse every unkeyed bout on the day into one.
        if let hkUuid, let keyed = existing.first(where: { $0.hkUuid == hkUuid }) {
            return keyed
        }

        let sameBout = existing.filter { $0.date == date && sameActivity($0.kind, kind) }

        // Then the precise HEURISTIC: an imported row can be matched on its
        // start, and the closest one wins so a day of hourly walks maps
        // one-to-one. This is the branch a pre-migration row still lands in.
        let imported = sameBout
            .filter(\.fromHealthkit)
            .compactMap { row -> (Existing, TimeInterval)? in
                guard let at = row.createdAt else { return nil }
                let delta = abs(at.timeIntervalSince(start))
                return delta <= duplicateWindow ? (row, delta) : nil
            }
            .min { $0.1 < $1.1 }
        if let imported { return imported.0 }

        // Then the fuzzy one, over rows a person typed.
        guard let incoming = durationMin else { return nil }
        return sameBout
            .filter { !$0.fromHealthkit }
            .compactMap { row -> (Existing, Double)? in
                guard let stored = row.durationMin else { return nil }
                let delta = abs(stored - incoming)
                return delta <= duplicateWindow / 60 ? (row, delta) : nil
            }
            .min { $0.1 < $1.1 }?.0
    }
}

// MARK: - The SMART MERGE (W6)

public extension CardioImport {

    /// The measurable numbers a bout carries, with nothing else attached.
    ///
    /// A value type rather than the row because the merge rule is the one part
    /// of the automatic ingest that can DESTROY something a person typed, and
    /// the rule that can destroy something is the rule that gets a pure test
    /// and no database import.
    struct Fields: Sendable, Equatable {
        public var distanceM: Double?
        public var durationMin: Double?
        public var activeKcal: Double?
        public var totalKcal: Double?
        public var avgHr: Double?
        public var elevationM: Double?
        public var inclinePct: Double?

        public init(
            distanceM: Double? = nil,
            durationMin: Double? = nil,
            activeKcal: Double? = nil,
            totalKcal: Double? = nil,
            avgHr: Double? = nil,
            elevationM: Double? = nil,
            inclinePct: Double? = nil
        ) {
            self.distanceM = distanceM
            self.durationMin = durationMin
            self.activeKcal = activeKcal
            self.totalKcal = totalKcal
            self.avgHr = avgHr
            self.elevationM = elevationM
            self.inclinePct = inclinePct
        }
    }

    /// Fill the gaps in a stored bout from an incoming one. **Never overwrite.**
    ///
    /// ── WHY THE STORED VALUE ALWAYS WINS ────────────────────────────────────
    /// The sheet's import is a person looking at a card and tapping it: an
    /// overwrite there is consented to, reviewable before Save, and correct —
    /// Health's figures are better than a guess and the person asked for them.
    ///
    /// The automatic ingest is neither looked at nor asked for. It runs on
    /// launch, over bouts nobody opened a screen about, and the row it may find
    /// is one somebody typed by hand — a treadmill walk with the console's own
    /// distance in it, which is the number they trust and Health's phone-derived
    /// one is the number they do not. An unattended process that replaces a
    /// typed figure with a measured one has silently overruled the user, and
    /// they find out a month later from a chart.
    ///
    /// So the automatic path only ever ADDS: heart rate, ascent, total energy —
    /// the figures nobody types, because no console shows them. A field that is
    /// already present is left exactly as it is, incoming value discarded.
    ///
    /// The consequence is worth stating plainly: a wrong figure typed by hand
    /// stays wrong until a person edits it. That is the correct failure. The
    /// other direction loses data nobody can recover.
    static func merge(stored: Fields, incoming: Fields) -> Fields {
        Fields(
            distanceM: stored.distanceM ?? incoming.distanceM,
            durationMin: stored.durationMin ?? incoming.durationMin,
            activeKcal: stored.activeKcal ?? incoming.activeKcal,
            totalKcal: stored.totalKcal ?? incoming.totalKcal,
            avgHr: stored.avgHr ?? incoming.avgHr,
            elevationM: stored.elevationM ?? incoming.elevationM,
            // Incline is never read from Health — HealthKit has no such metric
            // for a walk — so it is carried through untouched. It is in `Fields`
            // so that a merge is a whole-row replacement the caller cannot
            // accidentally narrow, not because the ingest ever supplies one.
            inclinePct: stored.inclinePct ?? incoming.inclinePct
        )
    }
}
