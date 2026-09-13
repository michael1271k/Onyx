import Foundation

/// The sixteen muscles ONYX actually tracks, and the one rule for crediting a
/// set to them.
///
/// A 1:1 port of the web app's `lib/training/landmarks.ts` (the `LANDMARK_MUSCLES` list,
/// `toLandmarkMuscle` and `SECONDARY_SET_CREDIT`) plus the accumulator half of
/// `MuscleDistribution.tsx`. The arithmetic is in `OnyxCore` rather than in a
/// view because it is arithmetic: it has been wrong three separate times in the
/// web app and every one of those was invisible on screen.

// MARK: - The sixteen

/// Declaration order IS `LANDMARK_MUSCLES` order, and `CaseIterable` is what
/// the sheet iterates. A reordering here silently reorders the legend, so the
/// order is part of the port and not a style choice.
public enum LandmarkMuscle: String, CaseIterable, Codable, Sendable, Hashable {
    case chest       = "Chest"
    case lats        = "Lats"
    case upperBack   = "Upper back"
    case lowerBack   = "Lower back"
    case frontDelts  = "Front delts"
    case sideDelts   = "Side delts"
    case rearDelts   = "Rear delts"
    case biceps      = "Biceps"
    case triceps     = "Triceps"
    case forearms    = "Forearms"
    case quads       = "Quads"
    case hamstrings  = "Hamstrings"
    case glutes      = "Glutes"
    case adductors   = "Adductors"
    case calves      = "Calves"
    case absCore     = "Abs/core"

    /// The muscle's own name, exactly as the generated atlas spells it.
    ///
    /// `OnyxAtlas.muscles` keys on these strings, so this is not merely a
    /// label — it is the join between the arithmetic and the drawing, which is
    /// why `rawValue` carries the display spelling rather than a slug.
    public var displayName: String { rawValue }

    /// Fold a raw muscle token into one of the sixteen, or `nil` when it is not
    /// a tracked target.
    ///
    /// The surprising cases are all deliberate and all bought with a
    /// reconciliation against a real week of Hevy data — see the long comments
    /// in `landmarks.ts`:
    ///
    ///   · a bare `back` is LATS, because everything in the catalogue tagged
    ///     only "back" is a pulldown or a row;
    ///   · a bare `shoulders` is SIDE delts, the common isolation case;
    ///   · `inner_thigh` is the adductor machine's own tag, and dropping it
    ///     left the Adductors target permanently unmeetable;
    ///   · `abductors` folds onto Adductors too, since 2026-09-08. It resolved
    ///     to nil for the same reason `inner_thigh` once did — "not a tracked
    ///     target" — which discarded every abduction set instead of crediting
    ///     the one landmark that covers the hip. The atlas draws ONE inner-thigh
    ///     region and the soreness rating asks ONE question about it, so the
    ///     credit lands in one place too.
    /// The token to STORE when this app is the one writing the muscle down —
    /// an imported exercise's `primary_muscle`, a CSV row's tags.
    ///
    /// ── WHY NOT JUST `rawValue` ─────────────────────────────────────────────
    /// `rawValue` is the DISPLAY spelling and fifteen of the sixteen happen to
    /// survive a round trip through `from(token:)`, because it folds spaces and
    /// hyphens to underscores. `Abs/core` is the sixteenth: the slash is not
    /// folded, so the token would resolve to nil and every abdominal set logged
    /// against an imported movement would earn no credit — silently, which is
    /// the failure mode this whole file is written against.
    ///
    /// `LandmarkTokenTests` asserts `from(token: m.token) == m` for all sixteen,
    /// so a new landmark cannot be added without a token that resolves.
    public var token: String {
        switch self {
        case .absCore: "abs"
        default:       rawValue
        }
    }

    public static func from(token: String) -> LandmarkMuscle? {
        switch token.lowercased().replacingOccurrences(
            of: "[\\s-]+", with: "_", options: .regularExpression
        ) {
        case "chest", "pecs":                                   return .chest
        case "lats", "back":                                    return .lats
        case "upper_back", "traps", "rhomboids":                return .upperBack
        case "lower_back", "erectors", "spinal_erectors":       return .lowerBack
        case "front_delts", "anterior_delts":                   return .frontDelts
        case "side_delts", "lateral_delts", "shoulders", "delts": return .sideDelts
        case "rear_delts", "rear_delt":                         return .rearDelts
        case "biceps":                                          return .biceps
        case "triceps":                                         return .triceps
        case "forearms", "brachioradialis":                     return .forearms
        case "quads", "quadriceps":                             return .quads
        case "hamstrings":                                      return .hamstrings
        case "glutes":                                          return .glutes
        case "adductors", "inner_thigh", "adductor", "abductors": return .adductors
        case "calves":                                          return .calves
        case "abs", "abdominals", "core", "obliques":           return .absCore
        default:                                                return nil
        }
    }
}

/// An exercise's movers, already split. Both lists hold raw tokens.
public struct MoverTokens: Sendable, Equatable, Codable {
    public let primary: [String]
    public let secondary: [String]

    public init(primary: [String], secondary: [String] = []) {
        self.primary = primary
        self.secondary = secondary
    }
}

// MARK: - The credit rule

public enum MuscleCredit {

    /// Assistance is worth half a set. Direct work is worth one.
    public static let secondarySetCredit = 0.5

    /// One exercise's contribution: how many PHYSICAL sets of it were performed,
    /// and what it trains.
    public struct Contribution: Sendable, Equatable {
        public let physicalSets: Int
        public let movers: MoverTokens

        public init(physicalSets: Int, movers: MoverTokens) {
            self.physicalSets = physicalSets
            self.movers = movers
        }
    }

    /// Weighted set counts per landmark muscle.
    ///
    /// ── WHY THE OVERLAP TAKES `max` AND NOT `+` ─────────────────────────────
    /// A movement can name the same landmark in both lists — a cable row is
    /// `upper back` primary and `traps` secondary, and both fold to Upper back.
    /// Summing them would pay 1.5 sets for one set of rowing. The rule is that
    /// a set is credited to a muscle ONCE, at the highest weight any of its
    /// tokens earned, which is why secondary is applied first and primary
    /// second.
    ///
    /// ── AND WHY WARM-UPS BELONG IN `physicalSets` ───────────────────────────
    /// Nowhere else in ONYX does a warm-up count as a set. Here it does,
    /// because the question is different: "where did this session land" is
    /// about what the body was asked to do, and two warm-up sets of leg press
    /// are two sets of leg press as far as the quads are concerned. It is also
    /// the number compared against Hevy, and Hevy counts them. A GHOST set is
    /// the one exclusion — that is work you marked as *not* done.
    public static func weightedSets(_ contributions: [Contribution]) -> [LandmarkMuscle: Double] {
        var out: [LandmarkMuscle: Double] = [:]
        for contribution in contributions where contribution.physicalSets > 0 {
            var credit: [LandmarkMuscle: Double] = [:]
            func add(_ tokens: [String], _ weight: Double) {
                for token in tokens {
                    guard let muscle = LandmarkMuscle.from(token: token) else { continue }
                    credit[muscle] = Swift.max(credit[muscle] ?? 0, weight)
                }
            }
            add(contribution.movers.secondary, secondarySetCredit)
            add(contribution.movers.primary, 1)   // last, so an overlap keeps FULL credit

            let count = Double(contribution.physicalSets)
            for (muscle, weight) in credit {
                out[muscle, default: 0] += count * weight
            }
        }
        return out
    }

    /// **The one accumulator.** Weighted sets per landmark for a bag of
    /// exercise names, one entry per PHYSICAL set performed.
    ///
    /// ── WHY THIS EXISTS (F7) ────────────────────────────────────────────────
    /// Before W3 the same week was counted three times in three currencies:
    /// `MuscleAggregator.aggregate` over six families with no assistance credit
    /// and a hard-coded Sunday week; `WidgetDerive.volumeByFamily` over six
    /// families with half credit and the athlete's week start; and
    /// `TodayFeedBuilder.muscleFocus` over sixteen landmarks. The widget tile,
    /// the sheet it opens and the Trends card could therefore report three
    /// different numbers for one session, and two of them were right about
    /// something different. Both of the others are gone; this is what is left,
    /// and the tile, the sheet and Trends all call it.
    ///
    /// Ghost sets are the caller's to drop — the caller is the one that knows
    /// what a set row looks like. Warm-ups COUNT, for the reason `weightedSets`
    /// states above.
    public static func weightedSets(exerciseNames: [String]) -> [LandmarkMuscle: Double] {
        weightedSets(exerciseNames.map {
            Contribution(physicalSets: 1, movers: MuscleMap.resolveMovers($0))
        })
    }

    /// Set counts to 0…1 tint intensities for the atlas, graded against the
    /// week's TARGETS.
    ///
    /// ── THE THREE-WAY RULE, IN ONE PLACE ────────────────────────────────────
    /// A muscle grades against its OWN target, because the question a week's
    /// figure answers is "is the week done": a quad at 10 of 10 and a bicep at
    /// 8 of 8 must both read full even though one is the bigger number. A muscle
    /// the plan does not ask for grades against the biggest target in the plan —
    /// it still HAPPENED, and fading it out reports trained work as untrained.
    ///
    /// ── AND WHY THE LAST CLAUSE EXISTS ──────────────────────────────────────
    /// When there are no targets AT ALL — a fresh account, a phase nobody has
    /// given volume rows — both of those denominators are zero, and the whole
    /// figure came out blank for a week with real work in it. That is the one
    /// thing this drawing may never do, so with no targets it falls back to
    /// `worked(from:)`'s rule and grades against the busiest muscle instead.
    /// Three surfaces used to spell this out separately (the widget tile, the
    /// Today sheet and the Trends card) and two of them were missing the
    /// fallback; there is now one copy.
    public static func worked(
        sets: [LandmarkMuscle: Double], targets: [LandmarkMuscle: Int]
    ) -> [LandmarkMuscle: Double] {
        let biggestTarget = Double(targets.values.max() ?? 0)
        // Not "fall back per muscle": with no target anywhere there is no
        // target-graded reading to be had, and `worked(from:)` IS the
        // busiest-muscle rule — including its 0.25 floor, so the session atlas
        // and this figure do not fade one set to two different alphas.
        guard biggestTarget > 0 else { return worked(from: sets) }
        var out: [LandmarkMuscle: Double] = [:]
        for (muscle, count) in sets where count > 0 {
            let own = Double(targets[muscle] ?? 0)
            out[muscle] = Swift.min(1, Swift.max(0.15, count / (own > 0 ? own : biggestTarget)))
        }
        return out
    }

    /// Set counts to 0…1 tint intensities for the atlas.
    ///
    /// The floor of 0.25 is load-bearing: a muscle that got one set out of
    /// twelve still HAPPENED, and fading it to invisible reports it as
    /// untrained — which is the opposite of what the figure is for.
    public static func worked(from sets: [LandmarkMuscle: Double]) -> [LandmarkMuscle: Double] {
        let peak = sets.values.filter { $0 > 0 }.max() ?? 0
        guard peak > 0 else { return [:] }
        return sets.compactMapValues { count in
            count > 0 ? Swift.max(0.25, Swift.min(1, count / peak)) : nil
        }
    }
}
