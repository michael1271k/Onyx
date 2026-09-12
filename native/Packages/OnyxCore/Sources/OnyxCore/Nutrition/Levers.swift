import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Phase levers — the rungs of the cut, as ROWS, with one selection in the
// database. A port of the web app's `lib/nutrition/levers.ts`, generic since W2.
//
// A deficit has two dials: eat less, or move more. A lever is one named
// combination of both. EVERY MACRO TRIPLE SHOULD BE ATWATER-EXACT (4/4/9): the
// calorie figure is the SUM of the macros, never a round number written beside
// them — `1950` was five kcal wrong for months that way. The seed's rungs are;
// a rung a user writes is checked by `atwaterKcal`, not enforced.
//
// ── WHAT A RUNG IS NOW ───────────────────────────────────────────────────────
// A `target_profiles` row whose `kind` is `deficit` or `release`. The founder's
// four (`baseline`, `lever-1`, `lever-2`, `maintenance-week`) were compiled in
// as `Levers.all`; they are rows now, and the id is the row's `key` — a String,
// not an enum, because a second account names its own rungs.
//
// THE LEVER IS DATE-BOUND. `user_goals.active_lever` is one mutable value, and
// every grader used to read it — including graders of days that finished weeks
// ago. Pulling Lever 1 on 16 Aug silently re-marked the month behind it. So the
// past belongs to the SCHEDULE — `lever_periods` rows, "this rung came into
// force on this date" — and today-and-after belong to the selection you are
// holding; `leverForDate` is the one thing every grader asks.
//
// A rung coming OFF is also an event: a period goes in whenever the rung
// CHANGES, and going back to your own numbers (no rung) is a change. A release
// must always be followed by the rung that resumes, or it is a permanent
// maintenance week.
// ─────────────────────────────────────────────────────────────────────────────

/// `deficit` rungs are the ordered ladder; `release` is a planned, bounded week
/// at maintenance taken ON PURPOSE inside a cut — a rung by every mechanic, and
/// emphatically not a step on the ladder. `day` is not a rung at all: a shape
/// one day can take (Home, Restaurant), applied with one tap.
public enum ProfileKind: String, Codable, Sendable, CaseIterable {
    case day, deficit, release
}

/// The two rung kinds, for readers that never see a `day` profile.
public enum LeverKind: String, Codable, Sendable { case deficit, release }

/// A rung, as the levers screen and the graders read it: a `TargetProfile`
/// of kind deficit/release, with the lever vocabulary on its fields.
public struct NutritionLever: Codable, Equatable, Sendable {
    public var id: String
    public var kind: LeverKind
    public var label: String
    public var summary: String
    public var calorieGoal: Double
    public var proteinGoalG: Double
    public var carbsGoalG: Double
    public var fatGoalG: Double
    public var stepsGoal: Double

    public init(id: String, kind: LeverKind, label: String, summary: String, calorieGoal: Double,
                proteinGoalG: Double, carbsGoalG: Double, fatGoalG: Double, stepsGoal: Double) {
        self.id = id; self.kind = kind; self.label = label; self.summary = summary
        self.calorieGoal = calorieGoal; self.proteinGoalG = proteinGoalG; self.carbsGoalG = carbsGoalG
        self.fatGoalG = fatGoalG; self.stepsGoal = stepsGoal
    }

    /// Nil for a `day` profile, and for a rung missing a macro — a rung holds
    /// ALL five numbers or it is not a rung.
    public init?(_ p: TargetProfile) {
        let kind: LeverKind
        switch p.kind {
        case .day: return nil
        case .deficit: kind = .deficit
        case .release: kind = .release
        }
        guard let carbs = p.carbsG, let fat = p.fatG, let steps = p.stepsGoal else { return nil }
        self.init(id: p.key, kind: kind, label: p.label, summary: p.summary, calorieGoal: p.kcal,
                  proteinGoalG: p.proteinG, carbsGoalG: carbs, fatGoalG: fat, stepsGoal: steps)
    }
}

/// The goal fields a lever replaces. Everything else it leaves alone.
public struct LeverGoals: Codable, Equatable, Sendable {
    public var calorie: Double
    public var protein: Double?
    public var carbs: Double?
    public var fat: Double?
    public var steps: Double?
    public init(calorie: Double, protein: Double?, carbs: Double?, fat: Double?, steps: Double?) {
        self.calorie = calorie; self.protein = protein; self.carbs = carbs; self.fat = fat; self.steps = steps
    }
}

/// A row of the SCHEDULE — `lever_periods`: "this rung came into force on
/// this date".
public struct LeverPeriod: Codable, Equatable, Sendable {
    /// First date this rung applies to, inclusive (`starts_on`).
    public var from: String
    /// The rung's key, or nil for a stretch on the user's own numbers.
    public var profileKey: String?
    /// Only ever on a keyless row, and only on a CLOSED stretch: the numbers
    /// that were in force from `from` until the next row. Absent means the
    /// stretch is still open and answers with the live `user_goals` row.
    public var goals: LeverGoals?

    public init(from: String, profileKey: String?, goals: LeverGoals? = nil) {
        self.from = from; self.profileKey = profileKey; self.goals = goals
    }
}

/// The RESOLVED answer for a run of days that shared one set of targets.
public struct TargetPeriod: Codable, Equatable, Sendable {
    /// The rung's key, or nil for the user's own numbers.
    public var leverId: String?
    /// "Lever 1" / "Baseline" / "Custom".
    public var label: String
    public var goals: LeverGoals
    /// ISO dates, in input order. Contiguous by construction.
    public var dates: [String]
}

/// Everything `leverForDate` reads, in one value: the rungs, the schedule,
/// and the live selection. Built once per read by the store (`TargetSources`
/// carries it) and handed to every grader, so the past and the present are
/// resolved by the same rows.
public struct LeverLadder: Codable, Equatable, Sendable {
    /// The user's profiles of kind deficit/release, in `sort` order.
    public var rungs: [NutritionLever]
    /// `lever_periods`, oldest first.
    public var periods: [LeverPeriod]
    /// `user_goals.active_lever`, verbatim.
    public var stored: String?
    /// `user_goals.maintenance_until` — a release that closes itself.
    public var releaseEndsOn: String?

    public init(rungs: [NutritionLever] = [], periods: [LeverPeriod] = [], stored: String? = nil, releaseEndsOn: String? = nil) {
        self.rungs = rungs
        self.periods = periods.sorted { $0.from < $1.from }
        self.stored = stored
        self.releaseEndsOn = releaseEndsOn
    }

    /// From profiles of every kind: the rungs are the ones that are rungs.
    public init(profiles: [TargetProfile], periods: [LeverPeriod] = [], stored: String? = nil, releaseEndsOn: String? = nil) {
        self.init(
            rungs: profiles.sorted { $0.sort < $1.sort }.compactMap(NutritionLever.init),
            periods: periods, stored: stored, releaseEndsOn: releaseEndsOn
        )
    }

    /// The ordered ladder — the rungs the "each is harder than the last" rule governs.
    public var deficit: [NutritionLever] { rungs.filter { $0.kind == .deficit } }

    public static let empty = LeverLadder()
}

public enum Levers {

    /// The rung a stored value names, or nil for `custom` / unknown / absent.
    public static func lever(byId id: String?, in ladder: LeverLadder) -> NutritionLever? {
        guard let id, !id.isEmpty else { return nil }
        return ladder.rungs.first { $0.id == id }
    }

    /// Is this a value the lever column may hold at all — a rung's key?
    public static func isLeverId(_ id: String?, in ladder: LeverLadder) -> Bool {
        lever(byId: id, in: ladder) != nil
    }

    /// The schedule row covering a date, or nil before the first rung.
    public static func scheduledPeriod(on dateISO: String, in ladder: LeverLadder) -> LeverPeriod? {
        var found: LeverPeriod?
        for p in ladder.periods {
            if dateISO >= p.from { found = p } else { break }
        }
        return found
    }

    /// The rung the SCHEDULE puts on a date, or nil.
    public static func scheduledLever(on dateISO: String, in ladder: LeverLadder) -> String? {
        scheduledPeriod(on: dateISO, in: ladder)?.profileKey
    }

    /// The rung in force on a date — the one thing every grader should ask.
    ///
    /// The past belongs to the schedule; today and after belong to the stored
    /// selection when it names a rung — except a `release` past
    /// `releaseEndsOn`, which stops being honoured and falls back to the
    /// schedule so a release closes itself whether or not anyone remembered
    /// to. `today` is a parameter, never a clock.
    ///
    /// `stored == "custom"` is an explicit selection too — "my own numbers" —
    /// and for today and after it wins over the schedule exactly as a rung
    /// would; only an ABSENT selection (nil / empty / a key no rung claims)
    /// falls through to the schedule.
    public static func leverForDate(_ dateISO: String, today: String, in ladder: LeverLadder) -> String? {
        if dateISO >= today {
            if ladder.stored == customSelection { return nil }
            if let rung = lever(byId: ladder.stored, in: ladder) {
                let expired = ladder.releaseEndsOn != nil && ladder.releaseEndsOn != ""
                    && rung.kind == .release
                    && dateISO > ladder.releaseEndsOn!
                if !expired { return rung.id }
            }
        }
        return scheduledLever(on: dateISO, in: ladder)
    }

    /// The `user_goals.active_lever` value that means "no rung, my own
    /// numbers" — stored, never nil: nil means "no selection", which falls
    /// through to the schedule, and the schedule may be the rung just left.
    public static let customSelection = "custom"

    /// Atwater energy of a macro triple, for the invariant every rung must satisfy.
    public static func atwaterKcal(proteinG: Double, carbsG: Double, fatG: Double) -> Double {
        proteinG * 4 + carbsG * 4 + fatG * 9
    }

    /// Apply a lever over resolved goals. Hands the input back untouched for
    /// no rung, an unknown id and no selection — the cases where the user has
    /// not asked for a rung.
    public static func applyLever(_ goals: LeverGoals, _ leverId: String?, in ladder: LeverLadder) -> LeverGoals {
        guard let lever = lever(byId: leverId, in: ladder) else { return goals }
        return LeverGoals(calorie: lever.calorieGoal, protein: lever.proteinGoalG, carbs: lever.carbsGoalG, fat: lever.fatGoalG, steps: lever.stepsGoal)
    }

    /// The targets that were in force on a date — rung, pinned history, or your
    /// row. A real rung wins; otherwise a keyless period's pinned goals (that
    /// stretch is finished and said what it meant); otherwise the fallback,
    /// the live `user_goals` row, correct only for the stretch you are inside.
    public static func goalsForDate(_ dateISO: String, today: String, fallback: LeverGoals, in ladder: LeverLadder) -> LeverGoals {
        if let id = leverForDate(dateISO, today: today, in: ladder), lever(byId: id, in: ladder) != nil {
            return applyLever(fallback, id, in: ladder)
        }
        // A keyless period's pin is only ever written when the NEXT change
        // closes it (`recordLeverChange`), so the stretch that is still open —
        // today's — reads the live row through the nil below, and every edit
        // to it lands at once.
        return scheduledPeriod(on: dateISO, in: ladder)?.goals ?? fallback
    }

    /// Which KIND of week a date belongs to. No rung and any date before the
    /// first period are `deficit`; only a `release` rung is the other thing.
    public static func leverKind(on dateISO: String, today: String, in ladder: LeverLadder) -> LeverKind {
        lever(byId: leverForDate(dateISO, today: today, in: ladder), in: ladder)?.kind ?? .deficit
    }

    /// Is the rung in force on a date a release — a planned maintenance week?
    public static func isRelease(on dateISO: String, today: String, in ladder: LeverLadder) -> Bool {
        leverKind(on: dateISO, today: today, in: ladder) == .release
    }

    /// Which targets were in force on each day of a range, collapsed into runs.
    ///
    /// Resolve every day (rung ⊂ pinned period ⊂ fallback, then the day's own
    /// `daily_targets` row on top) and glue equal NEIGHBOURS. Runs are compared
    /// on the RESOLVED GOALS, not the rung's name: two rungs asking for the same
    /// food and steps are the same instruction however they are labelled.
    public static func leverPeriods(
        _ dates: [String], today: String, fallback: LeverGoals, in ladder: LeverLadder,
        dailyTargets: [DailyTarget]? = nil
    ) -> [TargetPeriod] {
        var out: [TargetPeriod] = []
        // `new Map(rows.map(t => [t.date, t]))` — a later duplicate wins.
        var overrides: [String: DailyTarget] = [:]
        for t in dailyTargets ?? [] { overrides[t.date] = t }

        for date in dates {
            let id = leverForDate(date, today: today, in: ladder)
            let goals = DailyTargets.apply(goalsForDate(date, today: today, fallback: fallback, in: ladder), overrides[date])
            if let last = out.indices.last, out[last].goals == goals {
                out[last].dates.append(date)
                continue
            }
            out.append(TargetPeriod(leverId: id, label: lever(byId: id, in: ladder)?.label ?? "Custom", goals: goals, dates: [date]))
        }
        return out
    }
}
