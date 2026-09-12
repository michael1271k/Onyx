import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Where the scale is going, and when it arrives — a port of
// the web app's `lib/charts/trajectory.ts` (§W12).
//
// ── WHY AN EWMA AND A REGRESSION, BOTH ───────────────────────────────────────
// They answer different questions and the tile draws both.
//
// The EWMA is the LINE — what to draw over the raw dots, so the shape of the
// fortnight is legible through a kilo of water. It is local: it bends when the
// scale bends, which is what makes a stall visible three days in rather than
// three weeks in.
//
// The regression is the RATE — one number for the whole window, and the number
// the Goal Board row already prints (`GoalBoard`). A tile computing its own
// rate off the EWMA's endpoints would disagree with the row above it on the
// same screen, which is precisely the class of split this project has already
// paid for once with the streak. One rate, one source; the EWMA is a curve.
//
// ── AND WHY THE SMOOTHING IS TIME-WEIGHTED ───────────────────────────────────
// Weigh-ins are sparse by protocol — every second or third morning, and not at
// all on a trip. A plain `α·x + (1−α)·s` treats a reading taken after a
// fortnight's gap exactly like one taken the next morning, so the line drifts
// out of date and then lurches. The weight here is `2^(−Δdays / halfLife)`:
// after one half-life the previous state counts half, whether that half-life
// took one reading or six.
// ─────────────────────────────────────────────────────────────────────────────

public struct TrajectoryPoint: Codable, Sendable, Equatable, Identifiable {
    public var d: String
    /// The morning's reading.
    public var raw: Double
    /// The smoothed line at that reading, two decimals.
    public var ewma: Double
    public var id: String { d }
}

public struct Trajectory: Codable, Sendable, Equatable {
    /// One point per reading, oldest first. Days without a weigh-in are absent.
    public var points: [TrajectoryPoint]
    /// The rate, the arrival and the pace — `GoalBoard`, unchanged.
    public var board: GoalBoard
    /// What the title flips on. Nil between phases.
    public var phaseKind: PhaseKind?
    /// The newest smoothed value — what the line ENDS at, which is not the
    /// same as the fitted `trendWeightKg` the ETA is measured from.
    public var latestEwmaKg: Double?
}

public enum TrajectorySeries {
    /// How long it takes an old reading to count half. Ten days is ~a fortnight
    /// of water noise smoothed while a real 0.5 kg/week trend survives it.
    public static let halfLifeDays: Double = 10

    /// The time-weighted EWMA of a weight series, oldest first.
    ///
    /// Readings arrive in any order and are sorted; a nil weight, an
    /// unparseable date and a duplicate date are dropped (the LAST value wins
    /// for a duplicate, at the position the FIRST occurrence claimed, as a
    /// JavaScript `Map` does). The state carries FULL precision and only the
    /// output is rounded — rounding each step compounds a hundredth per reading
    /// into a tenth over a block.
    public static func ewma(_ readings: [GoalBoard.Reading], halfLifeDays: Double = halfLifeDays) -> [TrajectoryPoint] {
        var order: [String] = []
        var byDate: [String: Double] = [:]
        for r in readings {
            guard let w = r.weightKg, w.isFinite, ISODate.dayNumber(r.date) != nil else { continue }
            if byDate[r.date] == nil { order.append(r.date) }
            byDate[r.date] = w
        }
        let dates = order.sorted()
        let half = halfLifeDays > 0 ? halfLifeDays : Self.halfLifeDays

        var out: [TrajectoryPoint] = []
        var state: Double?
        var previousDay: Int?
        for d in dates {
            let raw = byDate[d]!
            let day = ISODate.dayNumber(d)!
            if let s = state, let previous = previousDay {
                let gap = Double(Swift.max(0, day - previous))
                let w = pow(2, -gap / half)
                state = raw * (1 - w) + s * w
            } else {
                state = raw
            }
            previousDay = day
            out.append(TrajectoryPoint(d: d, raw: raw, ewma: jsRound(state! * 100) / 100))
        }
        return out
    }

    public static func build(
        _ readings: [GoalBoard.Reading],
        today: String,
        targetWeightKg: Double? = nil,
        rateMinKgWk: Double? = nil,
        rateMaxKgWk: Double? = nil,
        energy: [GoalBoard.EnergyDay] = [],
        halfLifeDays: Double = halfLifeDays,
        phases: [PhaseDef] = []
    ) -> Trajectory {
        let points = ewma(readings, halfLifeDays: halfLifeDays)
        return Trajectory(
            points: points,
            board: GoalBoard.build(
                readings: readings, energy: energy, targetWeightKg: targetWeightKg,
                rateMinKgWk: rateMinKgWk, rateMaxKgWk: rateMaxKgWk, today: today
            ),
            phaseKind: Phases.span(for: today, in: phases)?.def.kind,
            latestEwmaKg: points.last?.ewma
        )
    }
}
