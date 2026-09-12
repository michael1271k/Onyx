import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Is a body-composition change good, bad, or neither — given the phase you are
// in? A port of the web app's `lib/body/deltaVerdict.ts` (colours are OnyxUI's).
//
// THREE DELIBERATE ASYMMETRIES: muscle is good up and bad down in every phase;
// fat gain in a bulk is neutral, not good; maintenance has a dead band, and
// outside it judges like a cut.
// ─────────────────────────────────────────────────────────────────────────────

public enum BodyMetric: String, Codable, Sendable, CaseIterable { case weight, fat, muscle, water }
public enum Verdict: String, Codable, Sendable { case good, bad, neutral }

public enum DeltaVerdict {
    /// How much a metric must move before maintenance calls it a direction at all.
    public static let maintenanceBand: [BodyMetric: Double] = [.weight: 0.5, .fat: 0.3, .muscle: 0.3, .water: .infinity]

    /// Anything smaller than this is measurement noise in any phase.
    static let epsilon = 0.01

    public static func verdict(_ metric: BodyMetric, delta: Double, phase: ProgramPhase, maintenance: Bool = false) -> Verdict {
        if !delta.isFinite || abs(delta) < epsilon { return .neutral }
        if metric == .water { return .neutral }
        if metric == .muscle { return delta > 0 ? .good : .bad }
        if maintenance {
            return abs(delta) < maintenanceBand[metric]! ? .neutral : (delta < 0 ? .good : .bad)
        }
        if metric == .fat {
            if delta < 0 { return .good }
            return phase == .bulk ? .neutral : .bad
        }
        return phase == .cut ? (delta < 0 ? .good : .bad) : (delta > 0 ? .good : .bad)
    }
}
