import Foundation

/// The supplement protocol — the web app's `lib/supplements.ts` and the pure half of
/// the web app's `lib/hooks/useCustomSupplements.ts`.
///
/// ── THE STACK LIVES IN THE DATABASE ──────────────────────────────────────────
/// `custom_supplements` is the whole protocol, one row per item, editable in
/// the app. There is no compiled seed since W2; W5's onboarding offers a
/// starter stack from a bundled template, as rows.
///
/// `key` is the identity that must survive everything: `supplement_log.item_key`
/// and the nutrient table are both keyed by it, so seeded rows carry these
/// exact strings in `schedule.key` and months of ticked history keeps resolving.
///
/// No clock: the weekday and the minute-of-day are parameters.
public struct Supplement: Codable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var dose: String
    /// Renders/counts only on training days (the pre-workout stimulants).
    /// Optional, not `false`: the seed leaves it unset and a DB row may say
    /// either, and the two are different facts on the wire.
    public var trainingOnly: Bool?
    /// A rule the dose alone can't state — "2 on Monday & Friday".
    public var notes: String?
    /// `custom_supplements.id`, present for anything read from the DB.
    public var customId: String?

    public init(key: String, name: String, dose: String, trainingOnly: Bool? = nil, notes: String? = nil, customId: String? = nil) {
        self.key = key; self.name = name; self.dose = dose
        self.trainingOnly = trainingOnly; self.notes = notes; self.customId = customId
    }
}

public struct SupplementSlot: Codable, Equatable, Sendable {
    public var key: String
    /// "HH:MM", or "—" for rows with no time. Orders the day.
    public var time: String
    public var label: String
    /// A CSS colour string, carried opaquely — OnyxUI decides what to do with it.
    public var accent: String
    public var items: [Supplement]

    public init(key: String, time: String, label: String, accent: String, items: [Supplement]) {
        self.key = key; self.time = time; self.label = label; self.accent = accent; self.items = items
    }
}

/// Everything about a supplement that isn't one of the table's own columns —
/// the `custom_supplements.schedule` jsonb.
public struct CustomSchedule: Codable, Equatable, Sendable {
    /// 0 = Sun … 6 = Sat; absent or empty ⇒ every day.
    public var days: [Int]?
    public var trainingDose: String?
    public var restDose: String?
    /// The stable log key. NEVER change one on an existing row.
    public var key: String?
    /// Display grouping only — "Morning", "Pre-Workout"; the TIME orders the day.
    public var slot: String?
    public var notes: String?
    public var trainingOnly: Bool?

    public init(days: [Int]? = nil, trainingDose: String? = nil, restDose: String? = nil, key: String? = nil,
                slot: String? = nil, notes: String? = nil, trainingOnly: Bool? = nil) {
        self.days = days; self.trainingDose = trainingDose; self.restDose = restDose
        self.key = key; self.slot = slot; self.notes = notes; self.trainingOnly = trainingOnly
    }
}

/// One `custom_supplements` row.
public struct CustomSupplement: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var dose: String
    public var color: String?
    /// pill | powder | capsule | …
    public var form: String?
    /// "HH:MM"
    public var time: String?
    public var schedule: CustomSchedule?
    /// Micronutrient payload per UNIT of the dose; nil = contributes none.
    public var micros: [String: Double]?
    /// The number inside `dose`, when the row was written by the phone's own
    /// list — `custom_supplements.dose_amount`. Nil on every row the web wrote,
    /// which is why `dose` and not this pair is what every reader parses.
    public var doseAmount: Double?
    /// The unit inside `dose` — `mg | g | mcg | IU | ml | tab | cap | scoop`.
    public var doseUnit: String?
    /// When the row left the stack, as an ISO instant — `custom_supplements.
    /// archived_at`. Nil is an item still in the protocol.
    ///
    /// ── WHY ARCHIVE AND NOT DELETE ──────────────────────────────────────────
    /// The web deletes the row outright, which takes the item's `schedule.key`
    /// with it — and that key is the join to every `supplement_log` row the
    /// item ever wrote. Deleting a supplement you stopped taking in June
    /// therefore rewrites June: the skips are still in the log, keyed to
    /// something no longer in the stack, and the day's credit changes under
    /// them. Archiving stops the item being scheduled from that date forward
    /// and leaves the history it already wrote alone.
    public var archivedAt: String?
    /// The doses this item USED to be taken at — `custom_supplements.
    /// dose_periods`. Nil on a row whose dose has never changed, which is every
    /// row written before 7.13.0. Read through `Supplements.doseAt`, never
    /// directly: see `DosePeriod`.
    public var dosePeriods: [DosePeriod]?
    /// Label ingredients the nutrient table has no key for, by name —
    /// `custom_supplements.other_ingredients`, written only by the DSLD import
    /// (overhaul C3). Nil on every other row. Added LAST and optional: a new
    /// key, never a renamed one.
    public var otherIngredients: [String]?

    /// `archived_at` is spelled the way the row spells it: the golden vectors
    /// serialise this struct from the TypeScript side, where it is a raw
    /// Supabase row and every other field already agrees by accident.
    public enum CodingKeys: String, CodingKey {
        case id, name, dose, color, form, time, schedule, micros
        case archivedAt = "archived_at"
        case doseAmount = "dose_amount"
        case doseUnit = "dose_unit"
        case dosePeriods = "dose_periods"
        case otherIngredients = "other_ingredients"
    }

    public init(id: String, name: String, dose: String, color: String? = nil, form: String? = nil,
                time: String? = nil, schedule: CustomSchedule? = nil, micros: [String: Double]? = nil,
                archivedAt: String? = nil, doseAmount: Double? = nil, doseUnit: String? = nil,
                dosePeriods: [DosePeriod]? = nil, otherIngredients: [String]? = nil) {
        self.id = id; self.name = name; self.dose = dose; self.color = color
        self.form = form; self.time = time; self.schedule = schedule; self.micros = micros
        self.archivedAt = archivedAt; self.doseAmount = doseAmount; self.doseUnit = doseUnit
        self.dosePeriods = dosePeriods
        self.otherIngredients = otherIngredients
    }
}

/// A dose an item used to be taken at, and the day it stopped being.
///
/// ── WHY THE ROW STAYS THE CURRENT DOSE ──────────────────────────────────────
/// `custom_supplements` carried one dose and no date, so changing 300 mg to
/// 200 mg rewrote every day the item had ever been taken: the checklist for
/// last Tuesday, that day's micronutrient credit and the export all said
/// 200 mg. A period records what was replaced — never what replaced it — so
/// the row's own `dose` columns keep meaning "the dose now", and a reader that
/// has never heard of this type still reads today correctly. Only a HISTORICAL
/// read has to ask, and it asks `Supplements.doseAt`.
///
/// ── `until` IS EXCLUSIVE ────────────────────────────────────────────────────
/// The day the change was made is the first day of the NEW dose: an item has
/// one dose per day, and the day you change it is the day you start taking the
/// new amount. So this period covers every day before `until`, back to the
/// previous period's `until`.
///
/// camelCase inside the jsonb, like `schedule` beside it.
public struct DosePeriod: Codable, Equatable, Sendable {
    /// ISO date: the first day this dose was no longer in force.
    public var until: String
    public var dose: String
    public var doseAmount: Double?
    public var doseUnit: String?
    public var trainingDose: String?
    public var restDose: String?

    public init(until: String, dose: String, doseAmount: Double? = nil, doseUnit: String? = nil,
                trainingDose: String? = nil, restDose: String? = nil) {
        self.until = until; self.dose = dose; self.doseAmount = doseAmount; self.doseUnit = doseUnit
        self.trainingDose = trainingDose; self.restDose = restDose
    }

    /// The row's dose as it stands, closed at `until`.
    public init(until: String, closing c: CustomSupplement) {
        self.init(until: until, dose: c.dose, doseAmount: c.doseAmount, doseUnit: c.doseUnit,
                  trainingDose: c.schedule?.trainingDose, restDose: c.schedule?.restDose)
    }

    /// Whether a reader would see the same dose. The three STRINGS, because
    /// they are what every reader parses; the amount and unit are the editor's
    /// copy of `dose` and cannot disagree with it.
    ///
    /// `dose` is compared as a PARSED amount and unit wherever both sides
    /// parse. The editor re-spells a row the web wrote — "2 Caps" saves back
    /// as "2 caps", "0.50 g" as "0.5 g" — so a string compare turned a time
    /// edit into a dose change the export then reported.
    func sameDose(as c: CustomSupplement) -> Bool {
        let same = Supplements.parseDose(dose).flatMap { a in
            Supplements.parseDose(c.dose).map { b in a.amount == b.amount && a.unit == b.unit }
        } ?? (dose == c.dose)
        return same && trainingDose == c.schedule?.trainingDose && restDose == c.schedule?.restDose
    }
}

/// What the thing physically IS — `custom_supplements.form`.
///
/// Drawn as a silhouette beside the name, the way Apple Health draws a
/// medication: five shapes a reader tells apart at a glance in a list of nine.
/// The symbol name lives here rather than in the view because the mapping is a
/// fact about the vocabulary, and a second copy of it in a second list is how
/// two screens come to disagree about what a capsule looks like.
public enum SupplementForm: String, Codable, Sendable, CaseIterable, Identifiable {
    case pill, capsule, powder, liquid, gummy

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pill:    "Pill"
        case .capsule: "Capsule"
        case .powder:  "Powder"
        case .liquid:  "Liquid"
        case .gummy:   "Gummy"
        }
    }

    /// SF Symbols has no powder and no gummy. `circle.hexagongrid.fill` reads
    /// as granules; `cube.fill` is the only solid in the set, so its silhouette
    /// cannot be mistaken for the two round ones.
    public var symbol: String {
        switch self {
        case .pill:    "pill.fill"
        case .capsule: "capsule.fill"
        case .powder:  "circle.hexagongrid.fill"
        case .liquid:  "drop.fill"
        case .gummy:   "cube.fill"
        }
    }

    /// A row with no form, or one carrying a word this build does not know.
    /// "Unspecified", never a guess.
    public static let unspecifiedSymbol = "pills.fill"

    public static func parse(_ raw: String?) -> SupplementForm? {
        guard let raw, !raw.isEmpty else { return nil }
        return SupplementForm(rawValue: raw.lowercased())
    }
}

/// The unit half of a structured dose — `custom_supplements.dose_unit`.
///
/// ── COUNT UNITS AND MASS UNITS ARE NOT THE SAME FACT ────────────────────────
/// `SupplementNutrients.doseUnits` decides whether a payload is multiplied by
/// reading the dose STRING: a count of physical units ("2 tabs") delivers that
/// multiple of the label, a mass ("300 mg") already IS the label. So the unit
/// carries which kind it is, and `Supplements.doseText` spells a count in the
/// plural the regex over there recognises. Get that wrong and every
/// micronutrient total on the Nutrition tab moves without a word being said.
public enum DoseUnit: String, Codable, Sendable, CaseIterable, Identifiable {
    case mg, g, mcg, iu = "IU", ml, tab, cap, scoop

    public var id: String { rawValue }

    /// True for a unit that names a COUNT of physical objects.
    public var isCount: Bool {
        switch self {
        case .tab, .cap, .scoop: true
        case .mg, .g, .mcg, .iu, .ml: false
        }
    }

    /// `tab` → `tabs`. Only count units pluralise; "300 mgs" is not a dose.
    public func spelling(for amount: Double) -> String {
        guard isCount, amount != 1 else { return rawValue }
        return rawValue + "s"
    }

    public static func parse(_ raw: String?) -> DoseUnit? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return allCases.first { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

/// The row's id is its identity on a list. `sheet(item:)` wants it and the
/// stack screen is the only caller.
extension CustomSupplement: Identifiable {}

/// What the day's log says about one item. Absence is not a state — it is the
/// protocol, and `DoseState` resolves it against the clock.
public struct DoseLogEntry: Codable, Equatable, Sendable {
    public var itemKey: String
    public var taken: Bool

    public init(itemKey: String, taken: Bool) {
        self.itemKey = itemKey
        self.taken = taken
    }
}

/// Where a scheduled dose stands.
public enum DoseState: String, Codable, Equatable, Sendable {
    /// A `taken = true` row: said explicitly, and counted the moment it is said.
    case taken
    /// No row, and the slot's time has come. The protocol is what happens
    /// unless you say otherwise, so this counts.
    case due
    /// No row, and the slot is still ahead. Nothing has been taken yet, so
    /// nothing is credited — a 22:00 magnesium must not appear in the day's
    /// micros at breakfast.
    case later
    /// A `taken = false` row. Never counted.
    case skipped
}

/// One scheduled dose of one day, resolved.
public struct SupplementDose: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    public var name: String
    public var dose: String
    public var slotKey: String
    public var slotLabel: String
    public var slotTime: String
    public var trainingOnly: Bool?
    public var notes: String?
    public var customId: String?
    public var state: DoseState

    public var id: String { key }

    /// Whether this dose's micronutrients count towards the day.
    public var credited: Bool { state == .taken || state == .due }

    public init(
        key: String, name: String, dose: String, slotKey: String, slotLabel: String, slotTime: String,
        trainingOnly: Bool? = nil, notes: String? = nil, customId: String? = nil, state: DoseState
    ) {
        self.key = key; self.name = name; self.dose = dose
        self.slotKey = slotKey; self.slotLabel = slotLabel; self.slotTime = slotTime
        self.trainingOnly = trainingOnly; self.notes = notes; self.customId = customId
        self.state = state
    }
}

/// One notification's worth of a day's stack — see `Supplements.reminders`.
public struct StackReminder: Equatable, Sendable {
    /// "HH:MM", the slot's own time.
    public var time: String
    public var title: String
    public var body: String
}

/// Where the day sits against the clock.
///
/// A past day has had every slot and a future one has had none; only today
/// needs a time of day. Modelled as two fields rather than an enum with an
/// associated value so the golden vector is one flat object on both sides.
public struct DayClock: Codable, Equatable, Sendable {
    /// Minutes since local midnight — nil when the date is not today.
    public var nowMinutes: Int?
    /// True when the date is in the PAST. Ignored when `nowMinutes` is set.
    public var dayIsOver: Bool

    public init(nowMinutes: Int? = nil, dayIsOver: Bool = false) {
        self.nowMinutes = nowMinutes
        self.dayIsOver = dayIsOver
    }

    /// Today, at a time.
    public static func today(minutes: Int) -> DayClock { DayClock(nowMinutes: minutes) }
    /// A day that has already happened.
    public static let past = DayClock(dayIsOver: true)
    /// A day that has not happened yet.
    public static let future = DayClock(dayIsOver: false)
}

public enum Supplements {

    /// The day's stack: the user's own rows, and nothing else.
    ///
    /// ── THE SEED IS GONE (W2) ───────────────────────────────────────────────
    /// `protocolSeed` was the founder's nine items compiled in, and the
    /// fallback rendered when the table was empty. An empty table now IS an
    /// empty stack: the founder's rows have existed since 2026-08-06, and a
    /// second account was being shown a protocol it never wrote. ONE resolver
    /// still, so the checklist, the micro totals, the Stack tile's denominator
    /// and the export cannot disagree.
    public static func stackForDate(_ dbSlots: [SupplementSlot], isTraining: Bool, weekday: Int) -> [SupplementSlot] {
        dbSlots
    }

    /// `supplementCountForDate` — the denominator for the Stack tile. The web
    /// reads the clock for the weekday here; it is not a parameter because the
    /// weekday only changes a DOSE STRING, never how many items there are.
    public static func count(isTraining: Bool, dbSlots: [SupplementSlot] = []) -> Int {
        stackForDate(dbSlots, isTraining: isTraining, weekday: 0).reduce(0) { $0 + $1.items.count }
    }

    /// `slotTimePassed` — has a slot's "HH:MM" passed, given the device's
    /// minute of the day? Parsed the way `split(':').map(Number)` parses:
    /// whitespace is trimmed, an empty part is 0, a missing or non-numeric
    /// part is NaN and the comparison is false.
    public static func slotTimePassed(_ hhmm: String, nowMinutes: Int) -> Bool {
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, let h = jsNumber(parts[0]), let m = jsNumber(parts[1]) else { return false }
        return Double(nowMinutes) >= h * 60 + m
    }

    private static func jsNumber(_ s: Substring) -> Double? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? 0 : Double(t)
    }

    // MARK: The custom rows

    /// `customDoseFor` — the dose on a training vs rest day. `||`, so an empty
    /// per-day dose falls back to the row's own.
    public static func customDose(_ c: CustomSupplement, isTraining: Bool) -> String {
        let d = isTraining ? c.schedule?.trainingDose : c.schedule?.restDose
        return (d?.isEmpty == false) ? d! : c.dose
    }

    /// `supplementKeyOf` — the stable seeded key where present, else `custom:<id>`.
    public static func key(of c: CustomSupplement) -> String {
        (c.schedule?.key?.isEmpty == false) ? c.schedule!.key! : "custom:\(c.id)"
    }

    /// `customSlotsForDate` — the DB rows due on a day → the slots the checklist
    /// renders and the export prints. Grouped by TIME and ordered by it.
    ///
    /// Every item carries the dose that was in force on `date` (`doseAt`).
    /// This is where the history is applied, rather than in each caller,
    /// because this is the one function the checklist, the day's micronutrient
    /// credit, the Stack tile and the export all already go through.
    ///
    /// The web sorts the time keys with `localeCompare`. The keys are "HH:MM"
    /// strings and the "—" bucket for rows with no time, and under ICU's root
    /// collation punctuation sorts before every digit — so "—" leads and the
    /// rest is bytewise. That is spelled out here rather than delegated to a
    /// locale-sensitive compare whose answer depends on the device.
    public static func customSlotsForDate(
        _ customs: [CustomSupplement], on date: String, weekday: Int, isTraining: Bool = true
    ) -> [SupplementSlot] {
        let customs = customs.map { doseAt($0, on: date) }
        let due = customs.filter { c in
            let days = c.schedule?.days ?? []
            return (days.isEmpty || days.contains(weekday))
                // A training-only item simply is not part of a rest day.
                && (isTraining || c.schedule?.trainingOnly != true)
        }
        if due.isEmpty { return [] }

        var order: [String] = []
        var byTime: [String: [CustomSupplement]] = [:]
        for c in due {
            let t = (c.time?.isEmpty == false) ? c.time! : "—"
            if byTime[t] == nil { order.append(t) }
            byTime[t, default: []].append(c)
        }
        return order.sorted(by: timeOrder).map { time in
            let items = byTime[time]!
            return SupplementSlot(
                key: "stack-\(time)",
                time: time,
                // The slot's name comes from its members; 'Custom' was a label for
                // a second-class list that no longer exists.
                label: items.first { $0.schedule?.slot?.isEmpty == false }?.schedule?.slot ?? "Stack",
                accent: (items[0].color?.isEmpty == false) ? items[0].color! : "#8E9AAC",
                items: items.map { c in
                    Supplement(key: key(of: c), name: c.name, dose: customDose(c, isTraining: isTraining),
                               trainingOnly: c.schedule?.trainingOnly, notes: c.schedule?.notes, customId: c.id)
                }
            )
        }
    }

    // MARK: - Archive

    /// Whether an item had left the stack by `date`.
    ///
    /// The comparison is on the DATE part of the instant, not the instant:
    /// archiving at 21:00 must not credit the 22:00 dose of the same evening
    /// while leaving the 10:30 one alone — the item is either in the day's
    /// protocol or it is not.
    public static func isArchived(_ c: CustomSupplement, on date: String) -> Bool {
        guard let at = c.archivedAt, !at.isEmpty else { return false }
        return String(at.prefix(10)) <= date
    }

    /// The rows still in the protocol on `date`.
    public static func active(_ customs: [CustomSupplement], on date: String) -> [CustomSupplement] {
        customs.filter { !isArchived($0, on: date) }
    }

    /// The rows that had left it.
    public static func archived(_ customs: [CustomSupplement], on date: String) -> [CustomSupplement] {
        customs.filter { isArchived($0, on: date) }
    }

    // MARK: - Dose history

    /// The row as it stood on `date`: its own columns, with the dose that was
    /// in force that day. THE one reader of `dose_periods` — see `DosePeriod`.
    ///
    /// The period in force is the one with the EARLIEST `until` still after
    /// `date`, found by search rather than by position, so a list two devices
    /// appended to in either order still resolves to the same dose. No period
    /// after `date` means the dose on the row, which is every date for an item
    /// whose dose has never changed.
    public static func doseAt(_ c: CustomSupplement, on date: String) -> CustomSupplement {
        guard let p = c.dosePeriods?.filter({ date < $0.until }).min(by: { $0.until < $1.until }) else { return c }
        var then = c
        then.dose = p.dose
        then.doseAmount = p.doseAmount
        then.doseUnit = p.doseUnit
        if then.schedule != nil || p.trainingDose != nil || p.restDose != nil {
            var schedule = then.schedule ?? CustomSchedule()
            schedule.trainingDose = p.trainingDose
            schedule.restDose = p.restDose
            then.schedule = schedule
        }
        return then
    }

    /// The history after `current` is saved as `next` on `today`.
    ///
    /// ── APPENDED, NEVER REWRITTEN ───────────────────────────────────────────
    /// A change closes the dose being replaced at `today` and adds it to the
    /// list; nothing already in the list is touched, so no edit can reach a day
    /// that has already been lived.
    ///
    /// ── TWICE IN ONE DAY ────────────────────────────────────────────────────
    /// A day has one dose. If today already closed a period, the dose that
    /// stood at the START of today is already recorded and a second change is
    /// just a better answer for today — nothing new to close. And a change back
    /// to that recorded dose is an undo: its period comes out, and the day
    /// reads as though nothing happened. `>=` rather than `==` so a device
    /// whose clock ran ahead of this one's cannot make a period that never
    /// closes.
    ///
    /// Returns the row's list unchanged when the dose did not change — a name
    /// or a time edited on its own is not a dose change.
    public static func dosePeriods(changing current: CustomSupplement, to next: CustomSupplement, today: String) -> [DosePeriod]? {
        guard !DosePeriod(until: today, closing: current).sameDose(as: next) else { return current.dosePeriods }
        var periods = current.dosePeriods ?? []
        if let i = periods.indices.filter({ periods[$0].until >= today })
            .min(by: { periods[$0].until < periods[$1].until }) {
            // Closed "after" today only by a clock running ahead of this one —
            // it closes today, or today would go on reading it.
            periods[i].until = today
            if periods[i].sameDose(as: next) { periods.remove(at: i) }
            return periods
        }
        periods.append(DosePeriod(until: today, closing: current))
        return periods
    }

    // MARK: - The day's doses

    /// Every scheduled dose of the day, with where it stands.
    ///
    /// ── THE FOUR STATES, AND WHY `due` COUNTS ───────────────────────────────
    /// `supplement_log` records EXCEPTIONS: a row exists to say a dose was
    /// refused (`taken = false`) or explicitly confirmed (`taken = true`).
    /// Absence is the protocol — you took it, because that is what the protocol
    /// is — and the only question absence leaves open is WHEN. Crediting an
    /// absent dose from 00:00 credited the night's magnesium at breakfast;
    /// crediting it only on an explicit tick would have required ticking nine
    /// items a day to make the micro totals true. So absence counts from the
    /// slot's time, and an explicit tick counts immediately.
    public static func doses(slots: [SupplementSlot], log: [DoseLogEntry], clock: DayClock) -> [SupplementDose] {
        var states: [String: Bool] = [:]
        for entry in log { states[entry.itemKey] = entry.taken }
        return slots.flatMap { slot in
            let passed = clock.nowMinutes.map { slotTimePassed(slot.time, nowMinutes: $0) } ?? clock.dayIsOver
            return slot.items.map { item in
                let state: DoseState
                if let taken = states[item.key] {
                    state = taken ? .taken : .skipped
                } else {
                    state = passed ? .due : .later
                }
                return SupplementDose(
                    key: item.key, name: item.name, dose: item.dose,
                    slotKey: slot.key, slotLabel: slot.label, slotTime: slot.time,
                    trainingOnly: item.trainingOnly, notes: item.notes, customId: item.customId,
                    state: state
                )
            }
        }
    }

    /// The doses whose micronutrients count towards the day.
    public static func creditedDoses(slots: [SupplementSlot], log: [DoseLogEntry], clock: DayClock) -> [SupplementDose] {
        doses(slots: slots, log: log, clock: clock).filter(\.credited)
    }

    /// One reminder per slot TIME that still holds a dose nobody has answered.
    ///
    /// A dose already ticked or skipped has a log row and is not asked about
    /// again — the reason reminders are re-armed rather than repeated (see
    /// `OnyxReminders`). An item with no time has no moment to be reminded at.
    /// The body names each item with the dose in force that day, because the
    /// doses came through `customSlotsForDate` and so through `doseAt`.
    public static func reminders(_ doses: [SupplementDose]) -> [StackReminder] {
        var order: [String] = []
        var byTime: [String: [SupplementDose]] = [:]
        for d in doses where (d.state == .later || d.state == .due) && d.slotTime != "—" {
            if byTime[d.slotTime] == nil { order.append(d.slotTime) }
            byTime[d.slotTime, default: []].append(d)
        }
        return order.map { time in
            let due = byTime[time]!
            return StackReminder(
                time: time,
                title: "\(due[0].slotLabel) · \(time)",
                body: due.map { "\($0.name) \($0.dose)" }.joined(separator: ", "))
        }
    }

    // MARK: - The structured dose

    /// `2` + `tab` → `"2 tabs"`; `300` + `mg` → `"300 mg"`.
    ///
    /// The display string stays the source of truth for every reader — the
    /// checklist, the export, and `SupplementNutrients.doseUnits`, whose regex
    /// is what makes a count scale and a mass not. The structured pair exists
    /// so the EDITOR does not have to re-parse prose; this is the one place the
    /// two are allowed to disagree about, and they do not.
    public static func doseText(amount: Double, unit: DoseUnit) -> String {
        "\(number(amount)) \(unit.spelling(for: amount))"
    }

    /// `2`, `0.5`, `12.75` — never `2.0`, which reads as a measurement taken to
    /// a decimal place that was not.
    ///
    /// ── AND NEVER `0,5`, WHICH WOULD DOUBLE A MICRONUTRIENT TOTAL ───────────
    /// This is the one formatter in `OnyxCore` whose output is PARSED again.
    /// `SupplementNutrients.doseUnits` matches a dot decimal to decide whether
    /// a payload is multiplied; on a comma-decimal device the device locale
    /// would write "0,5 scoops", the regex would not match it, `doseUnits`
    /// would fall to its ×1 default — and half a scoop would be credited as a
    /// whole one, silently, on the Nutrition tab. `parseDose`'s `Double(_:)` is
    /// dot-only for the same reason. So the STORED string is POSIX and the
    /// locale gets no say in it; a localised dose is a display concern and this
    /// string is not one.
    private static func number(_ value: Double) -> String {
        value.formatted(
            .number.precision(.fractionLength(0...2)).grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    /// The stored pair, or a best effort read off the display string, so a row
    /// the web wrote opens in the editor with its number in the number field.
    ///
    /// Deliberately narrow: leading whitespace, a number, optional whitespace,
    /// a unit this build knows, and nothing else that matters. Anything else —
    /// "2 tabs with food", "1-2 caps" — comes back nil and the editor asks,
    /// which is better than silently rewriting a dose nobody typed.
    public static func doseParts(_ c: CustomSupplement) -> (amount: Double, unit: DoseUnit)? {
        if let amount = c.doseAmount, amount > 0, let unit = DoseUnit.parse(c.doseUnit) {
            return (amount, unit)
        }
        return parseDose(c.dose)
    }

    /// `"300 mg"` → `(300, .mg)`. Plural count units are accepted; a trailing
    /// word is not.
    public static func parseDose(_ dose: String) -> (amount: Double, unit: DoseUnit)? {
        let parts = dose.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, let amount = Double(parts[0]), amount > 0 else { return nil }
        var word = String(parts[1])
        if word.count > 1, word.hasSuffix("s"), DoseUnit.parse(String(word.dropLast()))?.isCount == true {
            word = String(word.dropLast())
        }
        guard let unit = DoseUnit.parse(word) else { return nil }
        return (amount, unit)
    }

    // MARK: - The stored time

    /// `18:30` → a `Date` on today at that wall-clock time, for a `DatePicker`.
    ///
    /// Returns nil for the empty string and for anything that is not two
    /// numbers inside the clock — the caller draws "no set time" rather than
    /// inventing one, which is what a blank `time` column means.
    public static func slotTime(from stored: String, calendar: Calendar = .current, now: Date = Date()) -> Date? {
        let parts = stored.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
    }

    /// A `Date` → the `"HH:mm"` the `time` column stores.
    ///
    /// ── WHY THIS IS ARITHMETIC AND NOT A `DateFormatter` ────────────────────
    /// `customSlotsForDate` GROUPS BY THIS STRING and orders the keys bytewise
    /// against a "—" bucket. A `DateFormatter` on the device locale writes
    /// "6:30 PM" on a US phone and "١٨:٣٠" on an Arabic-Indic one, and either
    /// one mints a second slot that never merges with the first — the same
    /// class of silent locale bug `number(_:)` above exists to prevent, on the
    /// one other string in this file that is stored and re-read.
    ///
    /// `%02d` is C-locale by construction, so there is no formatter to
    /// misconfigure and nothing for a region setting to reach. What the WHEEL
    /// shows is the platform's business and may well be 12-hour; what it
    /// stores is this.
    public static func slotTimeString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func timeOrder(_ a: String, _ b: String) -> Bool {
        if a == "—" { return b != "—" }
        if b == "—" { return false }
        return Array(a.utf16).lexicographicallyPrecedes(b.utf16)
    }
}
