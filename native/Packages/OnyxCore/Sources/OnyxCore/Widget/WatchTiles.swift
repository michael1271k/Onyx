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

    // ── ADDED BY W4, OPTIONAL AND LAST ──────────────────────────────────────
    //
    // The dashboard pages the wrist gained this wave ask two questions the
    // complications never did — "how has the week gone" on the Train page and
    // "how much protein is left" on the Fuel page — and neither number was on
    // the wire. Appended rather than inserted, and optional like everything
    // that arrives after a shape has shipped: an older phone sends a payload
    // without these keys and a `decodeIfPresent` is what stops that being a
    // watch whose faces all go blank the day the phone updates first.
    //
    // The budget moved from 2 KB to 2 KB — see `WatchTilesTests`, which pins
    // the measured size rather than the intention.

    /// Working sets logged across the current week. `OnyxSnapshot.Week.sets`.
    public let weekSets: Int?
    /// Tonnage across the current week, in kilograms.
    ///
    /// Nil, never 0, on a week with no sessions — `OnyxSnapshot.Week.volumeKg`
    /// makes the same distinction for the same reason.
    public let weekVolumeKg: Double?
    /// Protein eaten today and the day's target, in grams.
    ///
    /// Rounded to whole grams on the phone, where the formatting rules live.
    /// A tenth of a gram is not a reading anyone acts on and it is four more
    /// characters on a 40 pt face.
    public let proteinG: Int?
    public let proteinGoalG: Int?
    /// Set only when the watch was off the wrist and readiness lost a signal
    /// to it (App Store W6) — the snapshot's `readiness.offWrist`, carried.
    /// Optional, so a payload from an older phone still decodes.
    public let offWrist: OffWristNote?

    // ── ADDED BY OVERHAUL LANE A, OPTIONAL AND LAST ─────────────────────────
    //
    // The Fuel page's food face draws a three-segment macro bar, and the wire
    // carried protein alone; carbs and fat ride beside it now. `nextDose` is
    // the sixth complication's one reading (decision Q5) — filled on the
    // phone by `PhoneWatchBridge` from the stack, because the snapshot this
    // payload is otherwise cut from has no supplement schedule in it. `var`,
    // for that reason: the bridge sets it after the projection.

    public let carbsG: Int?
    public let fatG: Int?
    public var nextDose: NextDose?

    /// The next supplement slot today — its first item's name (and how many
    /// ride with it) and when. Nil when nothing is left today.
    public struct NextDose: Codable, Sendable, Equatable {
        public let name: String
        public let at: Date
        public init(name: String, at: Date) {
            self.name = name
            self.at = at
        }
        enum CodingKeys: String, CodingKey { case name = "n", at = "a" }

        /// The first slot of `slots` due after `nowMinutes` on `date`, or nil.
        /// `slots` come in time order (`Supplements.customSlotsForDate`); a
        /// slot with no time ("—") is not a dose anybody can be reminded of.
        public static func next(in slots: [SupplementSlot], date: String, nowMinutes: Int,
                                calendar: Calendar = .current) -> NextDose? {
            let ymd = date.split(separator: "-").compactMap { Int($0) }
            guard ymd.count == 3 else { return nil }
            for slot in slots {
                let hm = slot.time.split(separator: ":").compactMap { Int($0) }
                guard hm.count == 2, hm[0] * 60 + hm[1] > nowMinutes, let first = slot.items.first,
                      let at = calendar.date(from: DateComponents(year: ymd[0], month: ymd[1], day: ymd[2],
                                                                   hour: hm[0], minute: hm[1]))
                else { continue }
                let more = slot.items.count - 1
                return NextDose(name: more > 0 ? "\(first.name) +\(more)" : first.name, at: at)
            }
            return nil
        }
    }

    public init(
        date: String, battery: Int? = nil, score: Int? = nil,
        sleepMin: Int? = nil, sleepScore: Int? = nil,
        waterMl: Int? = nil, waterGoalMl: Int? = nil,
        steps: Int? = nil, stepsGoal: Int? = nil,
        kcal: Int? = nil, kcalGoal: Int? = nil,
        todayLabel: String, todayLogged: Bool, restDay: Bool,
        stressIndex: Double? = nil, sorenessCount: Int? = nil,
        week: [WeekDay]? = nil, medianBedtime: String? = nil, lastBedtime: String? = nil,
        weekSets: Int? = nil, weekVolumeKg: Double? = nil,
        proteinG: Int? = nil, proteinGoalG: Int? = nil,
        offWrist: OffWristNote? = nil,
        carbsG: Int? = nil, fatG: Int? = nil, nextDose: NextDose? = nil
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
        self.weekSets = weekSets
        self.weekVolumeKg = weekVolumeKg
        self.proteinG = proteinG
        self.proteinGoalG = proteinGoalG
        self.offWrist = offWrist
        self.carbsG = carbsG
        self.fatG = fatG
        self.nextDose = nextDose
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
        // W4. As short as the rest, because this value is decoded on every
        // timeline of every complication that reads it.
        case weekSets = "ws", weekVolumeKg = "wv"
        case proteinG = "p", proteinGoalG = "pg"
        case offWrist = "ow"
        case carbsG = "cg", fatG = "fg", nextDose = "nd"
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
            lastBedtime: OnyxSnapshot.clockTime(s.sleep.startTime),
            // The week, as the Train page asks it. `sets` is a plain count and
            // rides as one; `volumeKg` is nil on a week with no sessions and
            // that nil is carried rather than flattened to 0.
            weekSets: s.week.sets,
            weekVolumeKg: s.week.volumeKg,
            proteinG: s.macros.proteinG.map { Int($0.rounded()) },
            proteinGoalG: s.macros.proteinGoalG.map { Int($0.rounded()) },
            offWrist: s.readiness?.offWrist,
            carbsG: s.macros.carbsG.map { Int($0.rounded()) },
            fatG: s.macros.fatG.map { Int($0.rounded()) }
        )
    }

    // MARK: Derived readings the faces share

    /// kcal left against the goal, or nil. Mirrors `OnyxSnapshot.caloriesRemaining`.
    public var kcalRemaining: Int? {
        guard let kcal, let kcalGoal else { return nil }
        return kcalGoal - kcal
    }

    /// Protein left against the target, or nil. Same shape as `kcalRemaining`,
    /// and nil for the same reason: a face with no target has nothing to
    /// subtract from, and "0 g left" would be a claim about a goal that does
    /// not exist.
    public var proteinRemaining: Int? {
        guard let proteinG, let proteinGoalG else { return nil }
        return proteinGoalG - proteinG
    }

    /// The same payload with `ml` more water on it — the wrist's optimistic
    /// glass (W4).
    ///
    /// ── WHY THE PAGE CANNOT JUST ADD IT WHEN IT DRAWS ───────────────────────
    /// The Fuel page draws the SAME `AccessoryFace` the complication and the
    /// phone's Lock Screen draw, and that face takes a `WatchTiles` and
    /// composes every string from it. Handing it a second number to add would
    /// be a second place the water reading is assembled, which is precisely
    /// what one-face-both-devices exists to prevent. So the page hands it a
    /// payload that already includes the glass.
    ///
    /// ── AND WHY `nil + 250` IS 250, NOT 250-OVER-NOTHING ────────────────────
    /// `nil` here means the phone has sent no water reading for today, which
    /// on the day's first glass is the true state — and the glass you just
    /// tapped IS today's water. Adding to nil therefore produces the reading
    /// rather than preserving the absence. `ml == 0` changes nothing at all,
    /// so a page with nothing queued hands the face exactly what arrived.
    public func addingWater(_ ml: Int) -> WatchTiles {
        guard ml > 0 else { return self }
        return WatchTiles(
            date: date, battery: battery, score: score,
            sleepMin: sleepMin, sleepScore: sleepScore,
            waterMl: (waterMl ?? 0) + ml, waterGoalMl: waterGoalMl,
            steps: steps, stepsGoal: stepsGoal,
            kcal: kcal, kcalGoal: kcalGoal,
            todayLabel: todayLabel, todayLogged: todayLogged, restDay: restDay,
            stressIndex: stressIndex, sorenessCount: sorenessCount,
            week: week, medianBedtime: medianBedtime, lastBedtime: lastBedtime,
            weekSets: weekSets, weekVolumeKg: weekVolumeKg,
            proteinG: proteinG, proteinGoalG: proteinGoalG, offWrist: offWrist,
            carbsG: carbsG, fatG: fatG, nextDose: nextDose
        )
    }

    /// These tiles if they are about `day`, else nil — what a complication
    /// draws after midnight (overhaul A2). The phone builds them for ITS day;
    /// past 00:00 every figure is yesterday's and the Train face would still
    /// say yesterday's session is due, so the face says "—" until the phone
    /// pushes the new day.
    public func current(on day: String) -> WatchTiles? {
        date == day ? self : nil
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
