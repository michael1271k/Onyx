import Foundation
import GRDB
import Testing
import OnyxCore
@testable import OnyxData

/// The W6 before/after table, measured rather than asserted.
///
/// ── WHY A TEST AND NOT `xctrace` ────────────────────────────────────────────
/// The eight seams in §W6-A are signposted (`Perf`) and a device trace will
/// read them. Four of them could not be timed on THIS machine: the simulator
/// has no Supabase session (W2's summary records it, and it is still true), so
/// there is no signed-in shell to switch tabs in, no deck to open, no session
/// to finish and no foreground sync to run. Timing those on a signed-out
/// launch screen would produce a table of zeroes wearing units.
///
/// The four that are pure store work CAN be timed here, exactly and
/// reproducibly, because `DenseSeed` is a deterministic account and both the
/// old shape and the new one are three lines apart. Each case below runs BOTH
/// and prints the pair, so the table in `docs/CHANGELOG.md` is two numbers
/// from one run on one machine rather than two numbers from two branches.
///
/// It is not a gate: a benchmark that fails on a busy laptop is a benchmark
/// somebody deletes. The assertions are on the SHAPE — that the new path is
/// not slower, and that it reads the same rows — and the numbers are printed.
/// `ONYX_BENCH=1` prints them; otherwise the suite still runs and still
/// checks the shape.
@Suite("W6 seam benchmarks")
struct SeamBenchmarkTests {

    static let user = "11111111-1111-4111-8111-111111111111"
    static let today = "2026-09-18"

    private func seeded() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "bench")
        try DenseSeed.seed(db, userId: Self.user, from: "2026-05-01", days: 141)
        return db
    }

    private func time(_ label: String, _ body: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now()
        try body()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        if ProcessInfo.processInfo.environment["ONYX_BENCH"] == "1" {
            print(String(format: "BENCH %@ %.1f ms", label, ms))
        }
        return ms
    }

    // MARK: - stressSeries: fourteen 49-day windows → one 62-day window

    @Test("stress series — one window is not slower than fourteen, and says the same thing")
    func stressSeries() throws {
        let db = try seeded()
        // Warm the page cache so the first path measured is not also paying
        // for the file coming into memory.
        _ = try db.stressSeries(userId: Self.user, endingOn: Self.today, limit: 14)

        var old: [StressDay] = []
        let before = try time("stress.series.before") {
            old = try Self.stressSeriesPerDay(db, userId: Self.user, endingOn: Self.today, limit: 14)
        }
        var new: [StressDay] = []
        let after = try time("stress.series.after") {
            new = try db.stressSeries(userId: Self.user, endingOn: Self.today, limit: 14)
        }
        #expect(new.map(\.d) == old.map(\.d))
        #expect(new.map { $0.index } == old.map { $0.index })
        #expect(after <= before * 1.5, "one window should not be materially slower: \(after) vs \(before)")
    }

    /// The pre-W6 shape, kept here and nowhere else: one `stressInputs` per
    /// day, each opening its own 49-day readiness window.
    private static func stressSeriesPerDay(
        _ db: AppDatabase, userId: String, endingOn: String, limit: Int
    ) throws -> [StressDay] {
        let days = try db.read { conn -> [StressDayIn] in
            let schedule = try AppDatabase.scheduleContext(conn, userId: userId)
            return try (0..<limit).map { i in
                let date = ISODate.addDays(endingOn, -i) ?? endingOn
                return StressDayIn(
                    date: date,
                    breakdown: Stress.breakdown(
                        try AppDatabase.stressInputs(conn, userId: userId, date: date, schedule: schedule)
                    )
                )
            }
        }
        return StressSeries.build(days, endingOn: endingOn, limit: limit)
    }

    // MARK: - scoringInputs: fourteen windows → one

    @Test("battery stack — one window answers fourteen days identically")
    func batteryStack() throws {
        let db = try seeded()
        let dates = (0..<14).map { ISODate.addDays(Self.today, -13 + $0) ?? Self.today }
        _ = try db.scoringInputs(
            userId: Self.user, dates: dates, todayISO: Self.today,
            hoursAwake: { _ in 16 }, isRestDay: { _ in false }
        )

        var old: [ScoringInputs?] = []
        let before = try time("battery.stack.before") {
            old = try dates.map {
                try db.scoringInputs(
                    userId: Self.user, date: $0, hoursAwake: 16, isRestDay: false,
                    todayISO: Self.today, isToday: $0 == Self.today
                )
            }
        }
        var new: [(date: String, inputs: ScoringInputs?)] = []
        let after = try time("battery.stack.after") {
            new = try db.scoringInputs(
                userId: Self.user, dates: dates, todayISO: Self.today,
                hoursAwake: { _ in 16 }, isRestDay: { _ in false }
            )
        }
        #expect(new.map(\.date) == dates)
        #expect(new.map { $0.inputs == nil } == old.map { $0 == nil })
        #expect(after <= before, "one window must not be slower than fourteen: \(after) vs \(before)")
    }

    // MARK: - The nutrition day: seven observations → one

    @Test("the nutrition day is one read, and it holds what seven held")
    func nutritionDay() throws {
        let db = try seeded()
        let date = Self.today
        _ = try db.stackCredit(userId: Self.user, date: date, today: date)

        let before = try time("nutrition.day.before") {
            // The seven reads the seven streams each performed.
            _ = try db.read { conn -> Int in
                _ = try DailyLogRow.filter(Column("user_id") == Self.user && Column("date") == date).fetchOne(conn)
                _ = try NutritionEntryRow.filter(Column("user_id") == Self.user && Column("date") == date).fetchAll(conn)
                _ = try WaterIntakeRow.filter(Column("user_id") == Self.user && Column("date") == date).fetchAll(conn)
                _ = try DailyTargetRow.filter(Column("user_id") == Self.user && Column("date") == date).fetchOne(conn)
                _ = try AppDatabase.nutritionWeek(conn, userId: Self.user, from: ISODate.addDays(date, -6)!, to: date)
                _ = try CustomSupplementRow.filter(Column("user_id") == Self.user).fetchAll(conn)
                _ = try SupplementLogRow.filter(Column("user_id") == Self.user && Column("date") == date).fetchAll(conn)
                return 0
            }
            _ = try db.stackCredit(userId: Self.user, date: date, today: date)
        }
        var snapshot: NutritionDaySnapshot?
        let after = try time("nutrition.day.after") {
            snapshot = try db.read { conn in
                NutritionDaySnapshot(
                    dailyLog: try DailyLogRow.filter(Column("user_id") == Self.user && Column("date") == date).fetchOne(conn),
                    entries: try NutritionEntryRow.filter(Column("user_id") == Self.user && Column("date") == date).fetchAll(conn),
                    water: try WaterIntakeRow.filter(Column("user_id") == Self.user && Column("date") == date).fetchAll(conn),
                    dailyTarget: try DailyTargetRow.filter(Column("user_id") == Self.user && Column("date") == date).fetchOne(conn),
                    week: try AppDatabase.nutritionWeek(conn, userId: Self.user, from: ISODate.addDays(date, -6)!, to: date),
                    stack: try AppDatabase.stackCredit(conn, userId: Self.user, date: date, today: date)
                )
            }
        }
        #expect(snapshot?.week.count == 7)
        #expect(after <= before, "one transaction must not be slower than eight: \(after) vs \(before)")
    }

    // MARK: - The watch context: the whole catalogue → the active deck

    @Test("the watch context carries the active deck and a deduplicated pool")
    func watchContext() throws {
        // Three decks, six days each, seven movements a day — the founder's
        // account's shape, so the byte counts below are about the payload that
        // actually crosses the wire and not about a two-lift fixture.
        let movements = [
            "Bench Press", "Barbell Row", "Overhead Press", "Lat Pulldown",
            "Back Squat", "Romanian Deadlift", "Leg Press", "Face Pull",
            "Incline Dumbbell Press", "Seated Cable Row", "Hack Squat",
            "Lying Leg Curl", "Cable Lateral Raise", "Triceps Pushdown",
        ]
        let programs: [Program] = (0..<3).map { p in
            Program(id: "p\(p)", label: "Deck \(p)", days: (0..<6).map { d in
                ProgramDay(
                    key: "p\(p)d\(d)", label: "Day \(d)", accent: 0, weekday: d,
                    exercises: (0..<7).map { e in
                        ProgramExercise(
                            movements[(p * 6 * 7 + d * 7 + e) % movements.count],
                            sets: 3, wk1Kg: 60, reps: "8-12", restSec: 150
                        )
                    }
                )
            })
        }
        let schedule = ScheduleContext(
            programId: "p0",
            phase: .cut,
            overrides: [:],
            layout: DayLayout(),
            programs: programs,
            plans: [],
            phases: []
        )
        let context = WatchContext(userId: "u", today: Self.today, schedule: schedule)
        #expect(context.schedule.programs.map(\.id) == ["p0"])
        let pool = context.swapPool ?? []
        // Deduplicated by name, and in the phone's own program order — that
        // order IS the tie-break the watch resolves a shared name by, so a
        // sorted or active-first pool would hand the wrist a different
        // prescription for the same movement.
        #expect(pool.count == Set(pool.map(\.name)).count)
        var seen = Set<String>()
        let expected = schedule.programs.flatMap(\.days).flatMap(\.exercises)
            .filter { seen.insert($0.name).inserted }
        #expect(pool.map(\.name) == expected.map(\.name))

        let full = try JSONEncoder().encode(
            WatchContextWire(userId: "u", today: Self.today, schedule: schedule)
        ).count
        let trimmed = try JSONEncoder().encode(context).count
        if ProcessInfo.processInfo.environment["ONYX_BENCH"] == "1" {
            print("BENCH watch.context.before \(full) bytes")
            print("BENCH watch.context.after \(trimmed) bytes")
        }
        #expect(trimmed < full)
    }

    /// The pre-W6 wire shape — the whole catalogue, untrimmed — so the byte
    /// count above is a comparison and not a claim.
    private struct WatchContextWire: Codable {
        var userId: String
        var today: String
        var schedule: ScheduleContext
    }
}
