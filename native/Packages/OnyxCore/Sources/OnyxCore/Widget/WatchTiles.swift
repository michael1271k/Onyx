import Foundation

// MARK: - The watch's tile payload (W7)
//
// ── WHAT THIS IS, AND WHAT IT IS NOT ────────────────────────────────────────
// The dozen numbers a complication can draw, cut out of `OnyxSnapshot` on the
// phone and carried to the wrist inside `WatchContext`. It is NOT a second
// snapshot: every field here is a projection of a field the phone's
// `WidgetSnapshotBuilder` already fills, taken by `init(_:)` below, so the
// Lock Screen on the phone and the complication on the watch read the SAME
// value from the same builder. There is no builder on the watch — its store
// has sets and nothing else — and a face that computed its own battery from a
// second source would be the split this payload's one-accumulator rule exists
// to prevent.
//
// ── WHY IT IS SMALL ─────────────────────────────────────────────────────────
// It rides in the application context beside a ~25 KB schedule, and the
// watch's widget extension reads it back out of a `UserDefaults` suite on
// every timeline. `OnyxSnapshot` at `.full` is tens of kilobytes of trends,
// ledgers and sixteen-muscle ladders that no 40 pt face can draw. The budget
// is 2 KB (`WatchTilesTests` pins it), and the shape stays under it by
// carrying no series at all: one figure a tile, which is what W6 decided the
// faces are anyway.
//
// ── MISSING IS NIL, NEVER ZERO ──────────────────────────────────────────────
// Same rule as the snapshot it is cut from. A watch face printing "0 kcal
// left" on a day nothing was logged is a lie the wrist will believe; "—" is
// not. The one deliberate exception is `week`, whose marks are answers to
// "was the goal met" rather than readings (`OnyxSnapshot.WeekRingDay`).

/// Everything the wearable faces draw. `Codable` with SHORT keys, because it
/// crosses the wire on every push and is decoded on every complication
/// timeline.
public struct WatchTiles: Codable, Sendable, Equatable {
    /// One day of the week's three marks — `WeekRingDay` without its date,
    /// because seven dates are 70 bytes that say "the last seven days".
    public struct WeekDay: Codable, Sendable, Equatable {
        public let trained: Bool
        public let fuelHit: Bool
        public let sleepHit: Bool
        public init(trained: Bool, fuelHit: Bool, sleepHit: Bool) {
            self.trained = trained
            self.fuelHit = fuelHit
            self.sleepHit = sleepHit
        }
        enum CodingKeys: String, CodingKey {
            case trained = "t", fuelHit = "f", sleepHit = "s"
        }
    }

    /// `YYYY-MM-DD` the phone built it for. The watch compares it with its own
    /// day so a face never says yesterday's session is today's.
    public let date: String
    public let battery: Int?
    public let score: Int?
    public let sleepMin: Int?
    public let sleepScore: Int?
    public let waterMl: Int?
    public let waterGoalMl: Int?
    public let steps: Int?
    public let stepsGoal: Int?
    public let kcal: Int?
    public let kcalGoal: Int?
    /// Today's split, as the plan names it ("Delts & Arms"). Empty on a rest
    /// day is not the convention — `restDay` is.
    public let todayLabel: String
    public let todayLogged: Bool
    public let restDay: Bool
    public let stressIndex: Double?
    /// How many landmarks are sore today. Nil when the payload did not ask
    /// (a scope without soreness), 0 when it asked and nothing hurts — the
    /// "0 regions" distinction W4 learned the hard way.
    public let sorenessCount: Int?
    /// The last seven days, oldest first. Nil when the week was not built.
    public let week: [WeekDay]?
    /// "23:30" — the usual bedtime as a LOCAL clock string, converted on the
    /// phone (the only place with a timezone decision, see
    /// `OnyxSnapshot.Sleep.medianBedtime`). Never re-converted here.
    public let medianBedtime: String?
    /// Last night's bedtime, same form. The Lock Screen's Bedtime face has
    /// always drawn this one; the tile draws the median. Both ride so the two
    /// faces keep their readings.
    public let lastBedtime: String?

    public init(
        date: String, battery: Int? = nil, score: Int? = nil,
        sleepMin: Int? = nil, sleepScore: Int? = nil,
        waterMl: Int? = nil, waterGoalMl: Int? = nil,
        steps: Int? = nil, stepsGoal: Int? = nil,
        kcal: Int? = nil, kcalGoal: Int? = nil,
        todayLabel: String, todayLogged: Bool, restDay: Bool,
        stressIndex: Double? = nil, sorenessCount: Int? = nil,
        week: [WeekDay]? = nil, medianBedtime: String? = nil, lastBedtime: String? = nil
    ) {
        self.date = date
        self.battery = battery
        self.score = score
        self.sleepMin = sleepMin
        self.sleepScore = sleepScore
        self.waterMl = waterMl
        self.waterGoalMl = waterGoalMl
        self.steps = steps
        self.stepsGoal = stepsGoal
        self.kcal = kcal
        self.kcalGoal = kcalGoal
        self.todayLabel = todayLabel
        self.todayLogged = todayLogged
        self.restDay = restDay
        self.stressIndex = stressIndex
        self.sorenessCount = sorenessCount
        self.week = week
        self.medianBedtime = medianBedtime
        self.lastBedtime = lastBedtime
    }

    enum CodingKeys: String, CodingKey {
        case date = "d", battery = "b", score = "sc"
        case sleepMin = "sm", sleepScore = "ss"
        case waterMl = "w", waterGoalMl = "wg"
        case steps = "st", stepsGoal = "sg"
        case kcal = "k", kcalGoal = "kg"
        case todayLabel = "tl", todayLogged = "td", restDay = "r"
        case stressIndex = "x", sorenessCount = "so"
        case week = "wk", medianBedtime = "mb", lastBedtime = "lb"
    }

    /// The projection. ONE place cuts the snapshot down, so the phone's
    /// accessory faces (handed a snapshot) and the watch's (handed the wire
    /// value) are drawing the same dozen numbers by construction.
    public init(_ s: OnyxSnapshot) {
        self.init(
            date: s.date,
            battery: s.battery,
            score: s.score,
            sleepMin: s.sleep.minutes,
            sleepScore: s.sleep.score,
            waterMl: s.water.ml.map { Int($0.rounded()) },
            waterGoalMl: s.water.goalMl.map { Int($0.rounded()) },
            steps: s.steps.count,
            stepsGoal: s.steps.goal,
            kcal: s.macros.kcal.map { Int($0.rounded()) },
            kcalGoal: s.macros.kcalGoal.map { Int($0.rounded()) },
            todayLabel: s.workout.label,
            todayLogged: s.workout.logged,
            restDay: s.workout.isRestDay,
            stressIndex: s.stress?.index,
            sorenessCount: s.soreness.map { $0.filter { $0.level > 0 }.count },
            week: s.weekRings.map { $0.suffix(7).map { WeekDay(trained: $0.trained, fuelHit: $0.fuelHit, sleepHit: $0.sleepHit) } },
            medianBedtime: s.sleep.medianBedtime,
            lastBedtime: OnyxSnapshot.clockTime(s.sleep.startTime)
        )
    }

    // MARK: Derived readings the faces share

    /// kcal left against the goal, or nil. Mirrors `OnyxSnapshot.caloriesRemaining`.
    public var kcalRemaining: Int? {
        guard let kcal, let kcalGoal else { return nil }
        return kcalGoal - kcal
    }

    /// Fractional progress toward a goal, clamped, nil when unknown.
    public static func progress(_ value: Int?, _ goal: Int?) -> Double? {
        OnyxSnapshot.progress(value.map(Double.init), goal.map(Double.init))
    }

    // MARK: Where the watch keeps it

    /// The App Group the watch app and its widget extension share. ONE
    /// spelling, in the package both link, for the reason `AddWaterIntent`
    /// imports OnyxData on the phone: a second literal is what silently breaks
    /// on a rename. Distinct from the phone's group — an App Group is per
    /// device, and the watch's is provisioned on the watch targets alone.
    public static let suiteName = "group.app.onyx.health.watch"
    /// The key the watch app writes the JSON under and the extension reads.
    public static let key = "onyx.watch.tiles"

    /// The suite, or `.standard` on a build with no App Group entitlement
    /// (Gate 0) — the app still runs, the complication stays empty.
    public static func defaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// What the extension reads. Nil before the phone has ever pushed, or on
    /// a build without the entitlement.
    public static func load(from defaults: UserDefaults = WatchTiles.defaults()) -> WatchTiles? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchTiles.self, from: data)
    }

    /// What the watch app writes on every context arrival.
    public func save(to defaults: UserDefaults = WatchTiles.defaults()) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
