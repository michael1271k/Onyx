import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// TARGET rest between sets — prescribed by the plan, adjustable by you. The
// pure half of the web app's `lib/training/restTargets.ts`.
//
// Onyx used to MEASURE rest (the gap between two set ticks) and never
// prescribe it. Every exercise on the live plan now carries `restSec`, and
// this resolves it with the same day-disambiguation `Ceilings.repWindow`
// uses. The two override stores (plan and per-session) are local state and
// belong to OnyxData; the keys they are stored under are defined here so the
// two sides cannot disagree about them.
// ─────────────────────────────────────────────────────────────────────────────

public enum RestTargets {
    /// The step the ± controls move in, and the grid every stored value snaps to.
    public static let stepSec: Double = 15
    /// Nothing shorter than a breath, nothing longer than a set-up.
    public static let minSec: Double = 15
    public static let maxSec: Double = 300

    /// Clamp to the legal range and snap to the 15-second grid.
    public static func clamp(_ sec: Double) -> Double {
        let snapped = jsRound(sec / stepSec) * stepSec
        return Swift.min(maxSec, Swift.max(minSec, snapped))
    }

    /// The PLAN's rest target for an exercise. The day wins when known; with
    /// an unknown day, the LONGEST programmed rest — too much rest costs time,
    /// too little costs the set.
    public static func programRestSec(for exerciseName: String, dayKey: String?, program: Program, phase: ProgramPhase = .cut) -> Double? {
        let target = Ceilings.normalize(exerciseName)
        let match = { (e: ProgramExercise) in Ceilings.normalize(e.name) == target }
        if let dayKey, !dayKey.isEmpty, let onDay = program.day(key: dayKey)?.exercises(for: phase).first(where: match),
           let rest = onDay.restSec {
            return Double(rest)
        }
        let all = program.days.flatMap { $0.exercises(for: phase) }.filter(match).compactMap(\.restSec)
        return all.max().map(Double.init)
    }

    /// The key a plan override is stored under: `program|day or -|canonical name`.
    public static func targetKey(_ exerciseName: String, dayKey: String?, programId: String) -> String {
        "\(programId)|\(dayKey ?? "-")|\(Ceilings.normalize(exerciseName))"
    }

    /// The key a SESSION override is stored under — the plan key with the date leading.
    public static func sessionKey(_ dateISO: String, _ exerciseName: String, dayKey: String?, programId: String) -> String {
        "\(dateISO)|\(targetKey(exerciseName, dayKey: dayKey, programId: programId))"
    }

    /// "2:00", "1:45", "45s" — how a target reads on a chip.
    public static func format(_ sec: Double) -> String {
        if sec < 60 { return "\(jsIntegerString(sec))s" }
        let minutes = jsIntegerString((sec / 60).rounded(.down))
        var seconds = jsIntegerString(sec.truncatingRemainder(dividingBy: 60))
        while seconds.count < 2 { seconds = "0" + seconds }
        return "\(minutes):\(seconds)"
    }
}
