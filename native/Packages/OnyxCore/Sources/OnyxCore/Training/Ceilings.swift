import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Rep windows read from the PROGRAM, and the double-progression verdicts built
// on them. A port of the web app's `lib/training/ceilings.ts`.
//
// The badge used to run on a single global ceiling of 12, so Calf Press at
// 15/14/13 "cleared" and prompted +2.5 kg against a programmed 10–15 window.
// Every exercise carries its window as a `reps` string; this is the one place
// that parses it. The rule is the program's own: increase load only when ALL
// work sets hit the ceiling at RPE ≤ 8.5 in TWO CONSECUTIVE sessions.
// ─────────────────────────────────────────────────────────────────────────────

public struct RepWindow: Codable, Equatable, Sendable {
    public var floor: Double
    public var ceiling: Double
    public init(floor: Double, ceiling: Double) { self.floor = floor; self.ceiling = ceiling }
}

public struct WorkingSet: Codable, Equatable, Sendable {
    public var weightKg: Double
    public var reps: Double
    /// CR-10, or nil for an UNRATED set — which is most of the history. See
    /// `Ceilings.progressionMaxRpe` for why the difference is load-bearing.
    public var rpe: Double?

    public init(weightKg: Double, reps: Double, rpe: Double? = nil) {
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
    }
}

/// One load used within an exercise, with the sets performed at it.
public struct LoadRung: Codable, Equatable, Sendable {
    public var weightKg: Double
    public var sets: [WorkingSet]
    /// Every set at THIS load reached the ceiling.
    public var cleared: Bool
}

public enum LadderState: String, Codable, Sendable {
    /// One load, every set at the ceiling — the clean double-progression case.
    case cleared
    /// Mixed loads, but the LOWEST load cleared: it retires, the top load is the new baseline.
    case collapseReady = "collapse-ready"
    /// Mixed loads and the lowest load is short — the lighter weight must be earned first.
    case blocked
    /// Nothing conclusive yet.
    case incomplete
}

public struct LadderVerdict: Codable, Equatable, Sendable {
    public var state: LadderState
    /// The load that must clear first — always the LOWEST used.
    public var bindingLoadKg: Double?
    /// The heaviest load used; what the exercise progresses toward.
    public var topLoadKg: Double?
    public var ceiling: Double
    /// Reps still owed at the binding load (0 when it has cleared).
    public var repsOwed: Double
}

/// Mixed loads where the top rung is doing the work but a lighter rung is not:
/// bring the light sets up to the load you are already handling, at the floor.
public struct LevelUpCue: Codable, Equatable, Sendable {
    public var fromKg: Double
    public var toKg: Double
    public var atReps: Double
}

public enum ProgressionState: String, Codable, Sendable {
    case ready
    case oneMore = "one-more"
    case no
}

public struct ProgressionVerdict: Codable, Equatable, Sendable {
    public var state: ProgressionState
    /// The ceiling actually applied (nil when the exercise isn't programmed).
    public var ceiling: Double?
    /// Suggested new load, only when `state == .ready` and there is a load to add.
    public var suggestKg: Double?
}

public enum Ceilings {
    /// Recommended jump once the ceiling is cleared twice.
    public static let loadStepKg = 2.5

    /// The two load steps the weight stepper offers — a tap and a long press.
    ///
    /// Coarse FIRST, and `loadStepKg` is that first entry: it is the jump
    /// `progressionVerdict` suggests and the one the plan is written in. 1.25 is
    /// there because cable stacks and micro-plates genuinely move in halves of
    /// it, and a stepper that can only offer 2.5 forces a load you did not lift
    /// to be recorded as one you did.
    /// No caller yet — the stepper that offers them is wave U2's. The
    /// constants land here so both clients agree before either draws a control.
    public static let loadSteps: [Double] = [2.5, 1.25]

    /// The finest step — what a hand-typed or derived load is snapped to.
    public static let loadStepFineKg = 1.25

    /// Snap a load to a step of the plate stack. Two decimals out, for the same
    /// reason `OnyxFormat.kg` keeps them. A non-finite or non-positive step
    /// hands the value back untouched rather than producing NaN.
    public static func roundToStep(_ kg: Double, step: Double = loadStepFineKg) -> Double {
        guard kg.isFinite, step.isFinite, step > 0 else { return kg }
        return jsRound(jsRound(kg / step) * step * 100) / 100
    }

    /// The ceiling on effort a progression may be earned at.
    ///
    /// ── THE HEADER PROMISED THIS FOR A YEAR AND THE CODE NEVER READ IT ──────
    /// The rule at the top of this file has always said "all work sets hit the
    /// ceiling at RPE ≤ 8.5"; only the reps half was implemented. Hitting the
    /// top of the window at an RPE of 9.5 is the top of the window bought with
    /// everything you had, and adding load to it is how a stall becomes a
    /// regression.
    ///
    /// ── AN UNRATED SET PASSES, DELIBERATELY ────────────────────────────────
    /// `workout_sets.rpe` is nullable and most of the history is null. Treating
    /// nil as "too hard" would silently turn the cue off for every lift logged
    /// before rating was a habit; treating it as "easy" is what the nil-is-not-
    /// zero rule forbids everywhere else. An unrated set makes no claim about
    /// effort, so it cannot block a verdict the reps have earned — and the
    /// moment you DO rate a set 9, it counts.
    ///
    /// ── IT COUNTS AGAIN NEXT WEEK, AND THAT IS THE RULE ────────────────────
    /// `RpeMemory.resolveSeededRpe` carries a rating forward while the load and
    /// reps are unchanged, so a 9 given at the ceiling seeds a 9 into the next
    /// deck, which commits a 9, which blocks `ready` again. That reads like a
    /// lock and it is the instruction: you are at the top of the window at an
    /// RPE of 9, and adding load to that is how a stall becomes a regression.
    /// The seed clears itself the moment the work gets harder, and re-rating is
    /// one tap. `workout_sets` stores no `rpe_seed`, so nothing downstream can
    /// tell an inherited rating from a fresh one — and inventing that
    /// distinction would mean grading two identical sessions differently.
    public static let progressionMaxRpe = 8.5

    /// No rated working set was above the effort ceiling. Unrated sets pass.
    public static func underEffortCeiling(_ sets: [WorkingSet]) -> Bool {
        workLoads(sets).allSatisfy { s in
            guard let rpe = s.rpe, rpe.isFinite else { return true }
            return rpe <= progressionMaxRpe
        }
    }

    /// `'8–12'` / `'8-12'` → 8–12 · `'10'` → 10–10 · `'55s'` → nil (timed, not rep-driven).
    /// The first and last digit runs are the floor and ceiling; ceiling < floor → nil.
    public static func parseRepWindow(_ reps: String) -> RepWindow? {
        let trimmed = reps.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.last, last == "s" || last == "S" { return nil }
        let runs = digitRuns(trimmed)
        guard let first = runs.first, let last = runs.last, let floor = Double(first), let ceiling = Double(last) else { return nil }
        guard floor.isFinite, ceiling.isFinite, ceiling >= floor else { return nil }
        return RepWindow(floor: floor, ceiling: ceiling)
    }

    /// `reps.match(/\d+/g)` — maximal runs of ASCII digits, in order.
    private static func digitRuns(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in s.unicodeScalars {
            if ch.value >= 48 && ch.value <= 57 { cur.unicodeScalars.append(ch) }
            else if !cur.isEmpty { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// `/(\d+)\s*s\b/i` — the programmed hold in seconds, or nil.
    static func parseHold(_ reps: String) -> Double? {
        let re = try! NSRegularExpression(pattern: #"(\d+)\s*s\b"#, options: .caseInsensitive)
        let ns = reps as NSString
        guard let m = re.firstMatch(in: reps, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Double(ns.substring(with: m.range(at: 1)))
    }

    static func normalize(_ name: String) -> String {
        ExerciseAliases.canonicalName(name).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The programmed rep window for an exercise. The day wins when it is
    /// known (Calf Press differs between the leg days); with no day, the
    /// STRICTEST window across the deck — highest ceiling, keeping its own
    /// floor — so an ambiguous match can only under-trigger the badge. Nil for
    /// exercises not in the program and for timed holds.
    public static func repWindow(for exerciseName: String, dayKey: String?, program: Program, phase: ProgramPhase = .cut) -> RepWindow? {
        let target = normalize(exerciseName)
        let match = { (e: ProgramExercise) in normalize(e.name) == target }
        if let dayKey, !dayKey.isEmpty, let onDay = program.day(key: dayKey)?.exercises(for: phase).first(where: match) {
            return parseRepWindow(onDay.reps)
        }
        let windows = program.days.flatMap { $0.exercises(for: phase) }.filter(match).compactMap { parseRepWindow($0.reps) }
        guard let first = windows.first else { return nil }
        return windows.dropFirst().reduce(first) { $1.ceiling > $0.ceiling ? $1 : $0 }
    }

    /// The programmed HOLD target in seconds for a timed movement, or nil. With
    /// no day, the LONGEST target so an ambiguous match only under-triggers.
    public static func holdTarget(for exerciseName: String, dayKey: String?, program: Program, phase: ProgramPhase = .cut) -> Double? {
        let target = normalize(exerciseName)
        let match = { (e: ProgramExercise) in normalize(e.name) == target }
        if let dayKey, !dayKey.isEmpty, let onDay = program.day(key: dayKey)?.exercises(for: phase).first(where: match),
           let h = parseHold(onDay.reps) {
            return h
        }
        let holds = program.days.flatMap { $0.exercises(for: phase) }.filter(match).compactMap { parseHold($0.reps) }
        return holds.max()
    }

    /// Did this session earn a load increase? Every working set must reach the
    /// ceiling AT ONE CONSISTENT LOAD, and that load must be > 0.
    public static func clearedCeiling(_ sets: [WorkingSet], ceiling: Double) -> Bool {
        guard !sets.isEmpty, sets.allSatisfy({ $0.reps >= ceiling }) else { return false }
        guard Set(sets.map(\.weightKg)).count == 1 else { return false }
        return sets[0].weightKg > 0
    }

    /// Sets grouped by load, lightest first.
    public static func loadLadder(_ sets: [WorkingSet], ceiling: Double) -> [LoadRung] {
        var order: [Double] = []
        var byLoad: [Double: [WorkingSet]] = [:]
        for s in sets {
            if byLoad[s.weightKg] == nil { order.append(s.weightKg) }
            byLoad[s.weightKg, default: []].append(s)
        }
        return order.sorted().map { w in
            let rung = byLoad[w]!
            return LoadRung(weightKg: w, sets: rung, cleared: !rung.isEmpty && rung.allSatisfy { $0.reps >= ceiling })
        }
    }

    /// The sets that count as WORK: strip the 0 kg rows only when some set in
    /// the exercise actually carried load. Bodyweight work is one rung at 0.
    public static func workLoads(_ sets: [WorkingSet]) -> [WorkingSet] {
        sets.contains { $0.weightKg > 0 } ? sets.filter { $0.weightKg > 0 } : sets
    }

    /// Ceiling verdict for an exercise whose sets may span SEVERAL loads.
    /// ORDER-INDEPENDENT: the LOWEST load used is binding, and the ladder only
    /// collapses upward when every set at that load reached the ceiling.
    public static func ladderVerdict(_ sets: [WorkingSet], ceiling: Double) -> LadderVerdict {
        let working = workLoads(sets)
        guard !working.isEmpty else {
            return LadderVerdict(state: .incomplete, bindingLoadKg: nil, topLoadKg: nil, ceiling: ceiling, repsOwed: 0)
        }
        let rungs = loadLadder(working, ceiling: ceiling)
        let binding = rungs[0]
        let top = rungs[rungs.count - 1]
        let worst = binding.sets.map(\.reps).min()!
        let repsOwed = Swift.max(0, ceiling - worst)
        let state: LadderState = rungs.count == 1
            ? (binding.cleared ? .cleared : .incomplete)
            : (binding.cleared ? .collapseReady : .blocked)
        return LadderVerdict(state: state, bindingLoadKg: binding.weightKg, topLoadKg: top.weightKg, ceiling: ceiling, repsOwed: repsOwed)
    }

    /// The TOP RUNG's own verdict: ≥ 2 sets at the heaviest load, all at the ceiling.
    private static func topRungCleared(_ sets: [WorkingSet], ceiling: Double) -> Bool {
        let working = workLoads(sets)
        guard let top = working.map(\.weightKg).max() else { return false }
        let atTop = working.filter { $0.weightKg == top }
        return atTop.count >= 2 && atTop.allSatisfy { $0.reps >= ceiling }
    }

    /// Did the session earn a progression? ONE load across every working set,
    /// at least two sets of it, every one at the ceiling. A trailing fade — on
    /// reps or to a lighter load — is the evidence the load is not consolidated.
    public static func topLoadCleared(_ sets: [WorkingSet], ceiling: Double) -> Bool {
        let working = workLoads(sets)
        guard working.count >= 2, Set(working.map(\.weightKg)).count == 1 else { return false }
        return working.allSatisfy { $0.reps >= ceiling }
    }

    /// Mixed loads with the top rung cleared: raise the light load, at the floor.
    public static func levelUpCue(_ sets: [WorkingSet], window: RepWindow) -> LevelUpCue? {
        let working = sets.filter { $0.weightKg > 0 }
        guard !working.isEmpty else { return nil }
        let loads = Array(Set(working.map(\.weightKg))).sorted()
        guard loads.count >= 2, topRungCleared(working, ceiling: window.ceiling) else { return nil }
        return LevelUpCue(fromKg: loads[0], toKg: loads[loads.count - 1], atReps: window.floor)
    }

    /// Double progression across the last TWO sessions, newest LAST: both
    /// cleared → ready (top + 2.5 kg, nil at 0 kg); newest only → one-more;
    /// otherwise no. A ladder collapse does not count as cleared.
    ///
    /// "Cleared" is `topLoadCleared` AND `underEffortCeiling`: two sets at the
    /// ceiling on the heaviest load, none of them RATED above 8.5. An unrated
    /// set passes — see `progressionMaxRpe`.
    public static func progressionVerdict(_ sessions: [[WorkingSet]], ceiling: Double?) -> ProgressionVerdict {
        guard let ceiling, let latest = sessions.last else {
            return ProgressionVerdict(state: .no, ceiling: ceiling, suggestKg: nil)
        }
        let cleared = { (sets: [WorkingSet]) in
            topLoadCleared(sets, ceiling: ceiling) && underEffortCeiling(sets)
        }
        let previous = sessions.count >= 2 ? sessions[sessions.count - 2] : nil
        if !cleared(latest) { return ProgressionVerdict(state: .no, ceiling: ceiling, suggestKg: nil) }
        guard let previous, cleared(previous) else {
            return ProgressionVerdict(state: .oneMore, ceiling: ceiling, suggestKg: nil)
        }
        let top = latest.filter { $0.weightKg > 0 }.map(\.weightKg).max() ?? 0
        return ProgressionVerdict(state: .ready, ceiling: ceiling, suggestKg: top > 0 ? jsRound1(top + loadStepKg) : nil)
    }

    /// Double progression for a TIMED hold, where `reps` carries SECONDS.
    /// Progression is "hold longer", never "add load".
    public static func timedProgressionVerdict(_ sessions: [[WorkingSet]], targetSec: Double?) -> ProgressionVerdict {
        guard let targetSec, let latest = sessions.last else {
            return ProgressionVerdict(state: .no, ceiling: targetSec, suggestKg: nil)
        }
        let cleared = { (sets: [WorkingSet]) in !sets.isEmpty && sets.allSatisfy { $0.reps >= targetSec } }
        let previous = sessions.count >= 2 ? sessions[sessions.count - 2] : nil
        if !cleared(latest) { return ProgressionVerdict(state: .no, ceiling: targetSec, suggestKg: nil) }
        guard let previous, cleared(previous) else { return ProgressionVerdict(state: .oneMore, ceiling: targetSec, suggestKg: nil) }
        return ProgressionVerdict(state: .ready, ceiling: targetSec, suggestKg: nil)
    }
}
