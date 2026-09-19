import Foundation
import GRDB
import OnyxCore
import Testing
@testable import OnyxData

/// Rescore at the door (W2, decision 11).
@Suite("The rescore door")
struct RescoreDoorTests {

    private let user = "door-user"
    private let today = "2026-09-18"
    /// 2026-09-18 14:00 UTC.
    private var now: Date { Date(timeIntervalSince1970: 1_789_740_000) }
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func store() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(deviceId: "door")
        try db.seedRows { conn in
            try UserGoalRow(
                id: "g", userId: user, sleepGoalHours: 8, calorieGoal: 2000, proteinGoalG: 170,
                carbsGoalG: 200, fatGoalG: 60, stepsGoal: 9000, waterGoalMl: 3000, contextMode: "normal",
                createdAt: Date(), updatedAt: Date(), autoLogSupplements: false, activeProgram: "onyx5",
                dayCutoffHour: 0, unitSystem: "metric", reduceMotion: false, timezone: "UTC", trackRpe: true
            ).insert(conn)
            try Exercise(id: ExerciseSlug.id("Hack Squat"), name: "Hack Squat").insert(conn)
        }
        return db
    }

    private func metrics(_ db: AppDatabase, _ dates: [String]) throws {
        try db.writer.write { conn in
            for d in dates {
                try DailyMetricRow(id: "m-\(d)", userId: user, date: d, steps: 4000, createdAt: now, updatedAt: now).insert(conn)
            }
        }
    }

    // MARK: - The facts the door reports

    @Test("a past-dated write reports its date, once per commit")
    func reportsAPastWrite() throws {
        let db = try store()
        let touches = Touches()
        let door = db.observePastWrites { touches.add($0) }
        defer { door.cancel() }
        try metrics(db, ["2026-09-15"])
        #expect(touches.all == [RescoreDoor.Touch(date: "2026-09-15", reason: .dayEdit)])
    }

    @Test("N rows in one transaction are one touch, at the earliest date")
    func coalescesWithinACommit() throws {
        let db = try store()
        let touches = Touches()
        let door = db.observePastWrites { touches.add($0) }
        defer { door.cancel() }
        try metrics(db, ["2026-09-16", "2026-09-02", "2026-09-10"])
        #expect(touches.all.count == 1)
        #expect(touches.all.first?.date == "2026-09-02")
    }

    @Test("a DELETE is a touch too — the row's date is captured before it goes")
    func deletesCount() throws {
        let db = try store()
        try db.addWaterGlass(userId: user, date: "2026-09-11", ml: 250)
        let touches = Touches()
        let door = db.observePastWrites { touches.add($0) }
        defer { door.cancel() }
        try db.writer.write { conn in
            _ = try WaterIntakeRow.filter(Column("user_id") == user && Column("date") == "2026-09-11").deleteAll(conn)
        }
        #expect(touches.all.map(\.date) == ["2026-09-11"])
    }

    @Test("a set on a past session is a session edit, dated by the session")
    func setsResolveThroughTheSession() throws {
        let db = try store()
        try db.writer.write { conn in
            try WorkoutSession(id: "s-old", userId: user, dayKey: "legs_a", date: "2026-09-04").insert(conn)
        }
        let touches = Touches()
        let door = db.observePastWrites { touches.add($0) }
        defer { door.cancel() }
        try db.appendSet(sessionId: "s-old", SetSnapshot(exerciseId: ExerciseSlug.id("Hack Squat"), setIndex: 1, weightKg: 100, reps: 8))
        #expect(touches.all.first == RescoreDoor.Touch(date: "2026-09-04", reason: .sessionEdit))
    }

    @Test("a night is filed under the morning it ended on, as a sleep edit")
    func nightsResolveToTheirMorning() throws {
        let db = try store()
        let touches = Touches()
        let door = db.observePastWrites { touches.add($0) }
        defer { door.cancel() }
        // Bedtime 2026-09-09 22:30 UTC → the night of 2026-09-10.
        let bed = Date(timeIntervalSince1970: 1_788_993_000)
        try db.writer.write { conn in
            try SleepSessionRow(id: "n1", userId: user, startTime: bed, endTime: bed.addingTimeInterval(7 * 3600), durationMin: 400, createdAt: Date()).insert(conn)
        }
        #expect(touches.all.first == RescoreDoor.Touch(date: "2026-09-10", reason: .sleepEdit))
    }

    @Test("a pulled row is not an edit — the mirror mark hides it from the door")
    func mirrorRowsAreIgnored() throws {
        let db = try store()
        let touches = Touches()
        let door = db.observePastWrites { touches.add($0) }
        defer { door.cancel() }
        try db.saveMirrorRows([
            DailyMetricRow(id: "pulled", userId: user, date: "2026-08-01", steps: 1000, createdAt: now, updatedAt: now)
        ])
        #expect(touches.all.isEmpty)
        // And the mark is DOWN again for the next, local, write.
        try metrics(db, ["2026-09-12"])
        #expect(touches.all.map(\.date) == ["2026-09-12"])
    }

    @Test("a rolled-back write reports nothing")
    func rollbackReportsNothing() throws {
        let db = try store()
        let touches = Touches()
        let door = db.observePastWrites { touches.add($0) }
        defer { door.cancel() }
        struct Abort: Error {}
        #expect(throws: Abort.self) {
            try db.writer.write { conn in
                try DailyMetricRow(id: "x", userId: user, date: "2026-09-01", steps: 1, createdAt: now, updatedAt: now).insert(conn)
                throw Abort()
            }
        }
        #expect(touches.all.isEmpty)
        try metrics(db, ["2026-09-13"])
        #expect(touches.all.map(\.date) == ["2026-09-13"], "the watermark did not skip the live rows")
    }

    @Test("a sync acknowledgement is not an edit — no touch for is_synced or is_pending_sync")
    func acksAreSilent() throws {
        let db = try store()
        try db.writer.write { conn in
            try WorkoutSession(id: "s-ack", userId: user, dayKey: "legs_a", date: "2026-09-04").insert(conn)
        }
        let event = try db.appendSet(sessionId: "s-ack", SetSnapshot(exerciseId: ExerciseSlug.id("Hack Squat"), setIndex: 1, weightKg: 80, reps: 8))
        let touches = Touches()
        let door = db.observePastWrites { touches.add($0) }
        defer { door.cancel() }
        try db.markSessionSynced(id: "s-ack")
        try db.writer.write { conn in
            try conn.execute(sql: "UPDATE set_events SET is_synced = 1 WHERE id = ?", arguments: [event.id])
            // The finish sheet's own columns feed no score either.
            try conn.execute(sql: "UPDATE workout_sessions SET avg_bpm = 140, calories_burned = 300 WHERE id = 's-ack'")
        }
        #expect(touches.all.isEmpty)
        // A load input moving IS an edit.
        _ = try db.updateMetrics(sessionId: "s-ack", userId: user, durationMin: 55)
        #expect(touches.all.map(\.date) == ["2026-09-04"])
    }

    @Test("the puller's event-log seed is a pull, not an edit")
    func seedIsSilent() throws {
        let db = try store()
        try db.writer.write { conn in
            try WorkoutSession(id: "s-web", userId: user, dayKey: "legs_a", date: "2026-08-20", endedAt: Date()).insert(conn)
            try WorkoutSet(id: "w1", sessionId: "s-web", exerciseId: ExerciseSlug.id("Hack Squat"), setIndex: 1, weightKg: 90, reps: 8).insert(conn)
        }
        let touches = Touches()
        let door = db.observePastWrites { touches.add($0) }
        defer { door.cancel() }
        try db.seedEventLogs(sessionIds: ["s-web"])
        #expect(try db.setEvents(sessionId: "s-web").count == 1, "the seed happened")
        #expect(touches.all.isEmpty, "and the door did not hear it")
    }

    // MARK: - The decision

    @Test("past within 120 days cascades; today is ignored; older is stale")
    func decision() {
        #expect(Rescore.doorDecision(date: "2026-09-17", today: today) == .cascade)
        #expect(Rescore.doorDecision(date: "2026-05-21", today: today) == .cascade, "day 120 is inside")
        #expect(Rescore.doorDecision(date: "2026-05-20", today: today) == .historyStale, "day 121 is outside")
        #expect(Rescore.doorDecision(date: today, today: today) == .ignore)
        #expect(Rescore.doorDecision(date: "2026-09-19", today: today) == .ignore)
        #expect(Rescore.doorWindowDays == 120)
    }

    // MARK: - Door + queue, end to end

    @Test("three past writes in a row leave every day from the earliest rescored")
    func doorFeedsTheQueue() async throws {
        let db = try store()
        try metrics(db, (0..<12).map { ISODate.addDays("2026-09-07", $0)! })
        let runs = RunLog()
        let queue = RescoreQueue(database: db, userId: user, calendar: calendar, now: { self.now }) { run in
            await runs.append(run)
        }
        let door = db.observePastWrites { touch in
            guard Rescore.doorDecision(date: touch.date, today: "2026-09-18") == .cascade else { return }
            Task { await queue.request(from: touch.date, reason: touch.reason) }
        }
        defer { door.cancel() }
        try db.addWaterGlass(userId: user, date: "2026-09-16", ml: 250)
        try db.addWaterGlass(userId: user, date: "2026-09-12", ml: 250)
        try db.addWaterGlass(userId: user, date: "2026-09-18", ml: 250) // today: ignored
        // The requests hop through a Task; give them a beat before settling.
        try await Task.sleep(for: .milliseconds(50))
        await queue.settle()
        let seen = await runs.all
        #expect(!seen.isEmpty)
        #expect(seen.map(\.from).min() == "2026-09-12")
        for i in 0..<7 {
            let d = ISODate.addDays("2026-09-12", i)!
            #expect(try db.dailyScore(userId: user, date: d) != nil, "\(d) was skipped")
        }
    }
}

private final class Touches: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [RescoreDoor.Touch] = []
    var all: [RescoreDoor.Touch] { lock.withLock { items } }
    func add(_ t: RescoreDoor.Touch) { lock.withLock { items.append(t) } }
}

private actor RunLog {
    private(set) var all: [Rescore.Run] = []
    func append(_ run: Rescore.Run) { all.append(run) }
}
