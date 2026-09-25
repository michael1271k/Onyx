import Foundation
import Observation
import OnyxCore
import OnyxData

/// Every program this account has, and the gestures that change which one runs
/// (Precision E2).
///
/// ── ONE STREAM, THE SAME ONE SETTINGS READS ─────────────────────────────────
/// The list observes `targetSnapshotStream` — the catalogue (plans, decks,
/// phases) with the selection applied — so a program created here, a plan
/// switched in Settings or a routine edited on another device redraws this
/// screen by observation, never by a reload someone remembered to call.
///
/// ── RUNNING IS THE SETTINGS PHASE SWITCH ────────────────────────────────────
/// "Make active" is `AppDatabase.activateProgram`, the five writes
/// `SettingsModel.activate` has always made (and now delegates to), with the
/// program's own goal choosing the phase when it has one.
@MainActor
@Observable
final class ProgramsModel {

    let database: AppDatabase
    let userId: String

    private(set) var schedule = ScheduleContext(programId: "", phase: .cut)
    /// The last write that failed or was refused, in words.
    var failure: String?

    /// No read here: a `NavigationLink`'s destination is built on every
    /// redraw of the screen holding it (the Train door, the Settings form),
    /// and a snapshot read per redraw is a main-thread query nobody asked for
    /// (review). The list's `.task` observes, and GRDB's first yield is
    /// immediate.
    init(database: AppDatabase, userId: String) {
        self.database = database
        self.userId = userId
    }

    func observe() async {
        do {
            for try await snap in database.targetSnapshotStream(userId: userId) where snap.schedule != schedule {
                schedule = snap.schedule
            }
        } catch {
            if !(error is CancellationError) { failure = "Could not read your programs." }
        }
    }

    // MARK: - Derived

    /// The running program's id — the selection resolved against the rows.
    var runningId: String { schedule.programId }

    /// Live programs first, in picker order; the historical ones apart.
    var live: [PlanInfo] { Programs.pickerOrder(schedule.plans).filter { !$0.isLegacy } }
    var past: [PlanInfo] { Programs.pickerOrder(schedule.plans).filter(\.isLegacy) }

    func plan(_ id: String) -> PlanInfo? { schedule.plans.first { $0.id == id } }

    func days(_ id: String) -> [ProgramDay] { schedule.program(id: id)?.days ?? [] }

    /// ["5 days", "since 15 Jul"] — the facts that decide whether a split
    /// fits a life, and whether it is the one in force.
    func metaParts(_ plan: PlanInfo) -> [String] {
        let count = days(plan.id).count
        var parts = [count == 0 ? "No days yet" : count == 1 ? "1 day" : "\(count) days"]
        if plan.id == runningId, let since = plan.startedOn.flatMap(Self.shortDate) {
            parts.append("since\u{00A0}\(since)")
        }
        return parts
    }

    /// "15 Jul".
    /// Joined by a no-break space so "15 Jul" never splits across lines.
    static func shortDate(_ iso: String) -> String? {
        LogicalDay.date(fromISO: iso)?.formatted(.dateTime.day().month(.abbreviated))
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    // MARK: - Writes

    /// A blank program. Returns its id for the editor to open.
    func createBlank() -> String? {
        write("Could not create the program.") {
            try database.createPlan(userId: userId, name: uniqueName("New program"))
        }
    }

    /// A benched COPY of a bundled template (`PlanTemplates.copy`).
    func startFrom(_ template: PlanTemplates.TemplatePlan) -> String? {
        write("Could not copy \(template.label).") {
            try PlanTemplates.copy(
                template, into: database, userId: userId, name: uniqueName(template.label)
            )
        }
    }

    /// Run a program. The phase is the program's goal's when it has one —
    /// a bulk program run on the cut's rows would deal the wrong volume — and
    /// the current phase otherwise.
    func activate(_ id: String) {
        let phase = plan(id)?.goal?.phase ?? schedule.phase
        _ = write("Could not switch program.") {
            try database.activateProgram(userId: userId, programId: id, phase: phase, startedOn: LogicalDay.today())
            return id
        }
    }

    func rename(_ id: String, to name: String) {
        _ = write("Could not rename the program.") {
            try database.renamePlan(userId: userId, programId: id, name: name)
            return id
        }
    }

    /// Delete — or say, in the program's own words, why not.
    func delete(_ id: String) {
        _ = write("Could not delete the program.") {
            try database.deletePlan(userId: userId, programId: id)
            return id
        }
    }

    /// A days model for the editor, over this program.
    func routines(_ id: String) -> RoutinesModel {
        RoutinesModel(database: database, userId: userId, programId: id, programLabel: plan(id)?.label ?? "Program")
    }

    // MARK: - Helpers

    /// "Onyx-5 2" when the account already has an "Onyx-5" — two programs
    /// with one name are two rows nobody can tell apart in a list.
    private func uniqueName(_ base: String) -> String {
        let taken = Set(schedule.plans.map { $0.label.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    /// Every write funnels through one failure path. A `PlanWriteError` is
    /// shown in its own words — it is a refusal with a reason, not a fault.
    private func write(_ fallback: String, _ body: () throws -> String) -> String? {
        do {
            let id = try body()
            failure = nil
            return id
        } catch let refusal as PlanWriteError {
            failure = refusal.errorDescription
        } catch {
            failure = fallback
        }
        return nil
    }
}

// MARK: - Templates as programs

extension PlanTemplates {

    /// A template's days as routine rows, in its own order. The `programId` is
    /// the template's; the writer re-homes them.
    static func routineDays(_ template: TemplatePlan) -> [RoutineDay] {
        template.days.sorted { $0.sort < $1.sort }.map { d in
            RoutineDay(
                programId: template.id, dayKey: d.key, label: d.label, sub: d.sub,
                weekday: d.weekday, accent: d.accent, sort: d.sort,
                payload: RoutinePayload(exercises: d.exercises)
            )
        }
    }

    /// File a template's movements in the exercise list, so every set it
    /// logs resolves to a catalogue row.
    ///
    /// ── THE STARTER IDS ─────────────────────────────────────────────────────
    /// `StarterMovements.id` — md5(user:name) as a uuid — rather than a random
    /// one: a name this phone has not pulled yet but the server holds under
    /// that same id lands on ONE row (the push upserts on `id`). A name the
    /// catalogue already holds is left alone (`createExercise` answers with the
    /// existing row). ponytail: a store that has NEVER pulled, against a server
    /// row under a different id, would still mint a second row — the ceiling
    /// Lane A's starter movements accepted; a pull-before-create gate lifts it.
    static func fileMovements(_ template: TemplatePlan, into database: AppDatabase, userId: String) throws {
        for name in Set(template.days.flatMap { $0.exercises.map(\.name) }).sorted() {
            _ = try database.createExercise(userId: userId, name: name, id: StarterMovements.id(userId: userId, name: name))
        }
    }

    /// A new, benched program from a template: movements filed, days copied.
    static func copy(
        _ template: TemplatePlan, into database: AppDatabase, userId: String, name: String,
        goal: ProgramGoal? = nil, goalTarget: ProgramGoalTarget? = nil
    ) throws -> String {
        try fileMovements(template, into: database, userId: userId)
        return try database.createPlan(
            userId: userId, name: name, blurb: template.blurb,
            goal: goal, goalTarget: goalTarget, days: routineDays(template)
        )
    }
}
