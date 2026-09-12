import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// The four composition numbers, each with the month behind it — a port of
// the web app's `lib/charts/bodyComp.ts` (§W12).
//
// ── WHY FOUR AND WHY THESE FOUR ──────────────────────────────────────────────
// Weight is not a body composition. On a cut the useful question is which of
// the kilos left, and the scale reports the answer in four currencies:
//
//   SMM  skeletal muscle mass — the scale's OWN figure (~27 kg), the one that
//        should not be falling
//   LST  lean soft tissue — weight × muscle % (~50 kg), a different measurement
//        that has shared a label with SMM before and cost this app a season of
//        wrong deltas (`InBodyEntryView`)
//   FFM  fat-free mass — weight − fat mass, derived
//   fat  body-fat percentage, the one that should be falling
//
// All four, because the tile picks three and Body trends wants them all; a
// series returning only what one face draws would be re-derived by the next.
//
// ── AND WHY THE DELTA CARRIES ITS OWN SPAN ───────────────────────────────────
// "−1.2 kg over 30 days" and "−1.2 kg over 9 days" are different news, and a
// body weighed twice this month can honestly report the second. The delta is
// the newest reading against the OLDEST one in the window, and `deltaDays` is
// the span it actually covers — so a face reading "30 d" off the window length
// while the data spans nine is not a shape this can take.
// ─────────────────────────────────────────────────────────────────────────────

public enum BodyMetricKey: String, Codable, Sendable, CaseIterable {
    case smm, lst, ffm, fat
}

public struct BodyCompReadingIn: Codable, Sendable, Equatable {
    public var date: String
    public var weightKg: Double?
    public var fatPct: Double?
    /// `skeletal_muscle_mass_kg` — the scale's own figure.
    public var skeletalMuscleKg: Double?
    /// `muscle_mass_kg` — weight × muscle %. NOT skeletal muscle.
    public var leanSoftTissueKg: Double?
    public var fatFreeMassKg: Double?

    public init(
        date: String, weightKg: Double? = nil, fatPct: Double? = nil,
        skeletalMuscleKg: Double? = nil, leanSoftTissueKg: Double? = nil, fatFreeMassKg: Double? = nil
    ) {
        self.date = date
        self.weightKg = weightKg
        self.fatPct = fatPct
        self.skeletalMuscleKg = skeletalMuscleKg
        self.leanSoftTissueKg = leanSoftTissueKg
        self.fatFreeMassKg = fatFreeMassKg
    }
}

public struct BodyCompPoint: Codable, Sendable, Equatable, Identifiable {
    public var d: String
    public var v: Double
    public var id: String { d }
}

public struct BodyCompMetric: Codable, Sendable, Equatable, Identifiable {
    public var key: BodyMetricKey
    /// What the strip calls it.
    public var label: String
    public var unit: String
    /// Down is the good direction for fat and nothing else.
    public var upIsGood: Bool
    public var latest: Double?
    public var latestOn: String?
    /// `latest − earliest`, two decimals. Nil without two readings.
    public var delta: Double?
    /// Days between the two readings the delta is measured across.
    public var deltaDays: Int?
    /// Every reading of this metric in the window, oldest first.
    public var points: [BodyCompPoint]
    public var id: String { key.rawValue }
}

public enum BodyCompSeries {

    private struct Spec {
        let key: BodyMetricKey
        let label: String
        let unit: String
        let upIsGood: Bool
        let pick: @Sendable (BodyCompReadingIn) -> Double?
    }

    private static let specs: [Spec] = [
        Spec(key: .smm, label: "Skeletal", unit: "kg", upIsGood: true, pick: { $0.skeletalMuscleKg }),
        Spec(key: .lst, label: "Lean", unit: "kg", upIsGood: true, pick: { $0.leanSoftTissueKg }),
        Spec(key: .ffm, label: "Fat-free", unit: "kg", upIsGood: true, pick: { $0.fatFreeMassKg }),
        Spec(key: .fat, label: "Body fat", unit: "%", upIsGood: false, pick: { $0.fatPct }),
    ]

    /// A finite, positive number, or nil. A zero is a scale that failed to
    /// read, not a body that weighs nothing.
    private static func reading(_ v: Double?) -> Double? {
        guard let v, v.isFinite, v > 0 else { return nil }
        return v
    }

    public static func build(
        _ readings: [BodyCompReadingIn], endingOn: String, days: Int = 30
    ) -> [BodyCompMetric] {
        let from = ISODate.addDays(endingOn, -(Swift.max(1, days) - 1)) ?? endingOn

        // A STABLE sort by date. `Array.prototype.sort` has been required to be
        // stable since ES2019 and Swift's `sorted` is explicitly not, so two
        // readings on one date would be free to swap — and the newest of them
        // is the one every figure below reads.
        let sorted = readings
            .filter { $0.date >= from && $0.date <= endingOn }
            .enumerated()
            .sorted { a, b in a.element.date != b.element.date ? a.element.date < b.element.date : a.offset < b.offset }
            .map(\.element)

        return specs.map { spec in
            var points: [BodyCompPoint] = []
            for r in sorted {
                if let v = reading(spec.pick(r)) { points.append(BodyCompPoint(d: r.date, v: v)) }
            }
            let latest = points.last
            // The oldest reading the window holds. One reading is a
            // measurement, not a change, and a delta against itself would
            // render as a confident 0.00.
            let usable = points.count >= 2 ? points.first : nil
            var delta: Double?
            var deltaDays: Int?
            if let usable, let latest {
                delta = jsRound((latest.v - usable.v) * 100) / 100
                if let a = ISODate.dayNumber(usable.d), let b = ISODate.dayNumber(latest.d) {
                    deltaDays = b - a
                }
            }
            return BodyCompMetric(
                key: spec.key, label: spec.label, unit: spec.unit, upIsGood: spec.upIsGood,
                latest: latest?.v, latestOn: latest?.d,
                delta: delta, deltaDays: deltaDays, points: points
            )
        }
    }
}
