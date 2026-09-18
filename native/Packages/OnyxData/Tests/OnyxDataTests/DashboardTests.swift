import Foundation
import GRDB
import Testing
import OnyxCore
@testable import OnyxData

@Suite("Dashboard layout — stored, streamed, queued")
struct DashboardLayoutStoreTests {
    private let user = "00000000-0000-0000-0000-000000000001"

    @Test("a save writes the phone side, keeps the desktop side, and queues the row once")
    func saveKeepsOtherSurface() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        // A row the web wrote: v4 with a desktop arrangement this app must not lose.
        let webRow = #"{"v":4,"desktop":{"slots":[{"id":"d1","size":"xl","items":["recovery"]}],"hidden":[],"updatedAt":5}}"#
        try db.writer.write { try DashboardLayoutRow(userId: user, layout: JSONText(raw: webRow), updatedAt: Date()).insert($0) }

        var layout = Dashboard.defaultLayout(.phone)
        layout = Dashboard.resizeSlot(layout, slotId: "sl-sleep")
        try db.saveDashboardLayout(userId: user, layout)

        let stored = try db.writer.read { try DashboardLayoutRow.filter(Column("user_id") == user).fetchOne($0) }
        let object = try JSONSerialization.jsonObject(with: Data(stored!.layout.raw.utf8)) as! [String: Any]
        #expect((object["desktop"] as! [String: Any])["slots"] != nil)
        #expect(Dashboard.fromStored(object, surface: .phone) == layout)

        let outbox = try db.pendingOutbox()
        #expect(outbox.map(\.kind) == [SyncKind.rowUpsert])
        let ref = try OnyxJSON.decoder.decode(RowRef.self, from: outbox[0].payload)
        #expect(ref.table == "dashboard_layouts")
        #expect(ref.id == user)
    }

    // ── W7: `linked` over the row that is on the device ─────────────────────

    /// The migration this wave performs, at the layer that performs it.
    /// `Dashboard`'s own vectors prove the reader; this proves that a real
    /// stored row, written by a build that had never heard of `linked`, comes
    /// back out of the store saying the same thing — and that connecting a
    /// stack adds one key and moves nothing else, `v` included.
    @Test("a row written before `linked` existed reads, re-writes and loses nothing")
    func v4RowSurvivesTheBump() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let v4 = #"{"v":4,"phone":{"slots":[{"id":"sl-sleep","size":"m","items":["sleep","vitals"]}],"hidden":["steps"],"updatedAt":7},"desktop":{"slots":[{"id":"d1","size":"xl","items":["recovery"]}],"hidden":[],"updatedAt":5}}"#
        try db.writer.write { try DashboardLayoutRow(userId: user, layout: JSONText(raw: v4), updatedAt: Date()).insert($0) }

        let read = try db.writer.read { db -> DashboardLayout in
            let row = try DashboardLayoutRow.filter(Column("user_id") == user).fetchOne(db)!
            return StoredDashboardLayout(row).layout
        }
        // The arrangement the row held, plus the catalogue widgets it predates.
        #expect(read.slots.first { $0.id == "sl-sleep" }?.items == [.sleep, .vitals])
        #expect(read.slots.first { $0.id == "sl-sleep" }?.linked == false)
        #expect(read.hidden == [.steps])
        #expect(read.slots.last?.items == [.daily], "reconcile appends the Mega Widget last")

        // Connect the stack, save, and read it back off disk.
        try db.saveDashboardLayout(userId: user, Dashboard.setLinked(read, slotId: "sl-sleep", true))
        let object = try db.writer.read { db -> [String: Any] in
            let row = try DashboardLayoutRow.filter(Column("user_id") == user).fetchOne(db)!
            return try JSONSerialization.jsonObject(with: Data(row.layout.raw.utf8)) as! [String: Any]
        }
        // ── AND `v` DID NOT MOVE ────────────────────────────────────────
        // `linked` is additive, and `Dashboard.version` is the gate an older
        // build uses to decide whether this row has surface sides at all. See
        // `Layout.swift`'s header for what raising it costs.
        #expect(object["v"] as? Double == 4)
        // The desktop side the phone has no business touching is still there.
        #expect(((object["desktop"] as! [String: Any])["slots"] as! [[String: Any]])[0]["id"] as? String == "d1")
        let back = Dashboard.fromStored(object, surface: .phone)
        #expect(back.slots.first { $0.id == "sl-sleep" }?.linked == true)
        // And every slot that was NOT connected wrote no flag at all.
        let slots = (object["phone"] as! [String: Any])["slots"] as! [[String: Any]]
        #expect(slots.filter { $0["linked"] != nil }.count == 1)
    }

    // ── W6: the Train tab rides in this row ─────────────────────────────────

    @Test("a train save keeps both dashboard sides, and a dashboard save keeps the train key")
    func trainAndDashboardShareTheRow() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let webRow = #"{"v":4,"desktop":{"slots":[{"id":"d1","size":"xl","items":["recovery"]}],"hidden":[],"updatedAt":5}}"#
        try db.writer.write { try DashboardLayoutRow(userId: user, layout: JSONText(raw: webRow), updatedAt: Date()).insert($0) }

        // The phone arranges its dashboard, then puts the Cardio card away.
        var layout = Dashboard.defaultLayout(.phone)
        layout = Dashboard.resizeSlot(layout, slotId: "sl-sleep")
        try db.saveDashboardLayout(userId: user, layout)
        try db.saveTrainLayout(userId: user, TrainLayout.default.setting(.cardio, visible: false))

        #expect(db.trainLayout(userId: user).hidden == [.cardio])
        let stored = try db.writer.read { try DashboardLayoutRow.filter(Column("user_id") == user).fetchOne($0) }
        let object = try JSONSerialization.jsonObject(with: Data(stored!.layout.raw.utf8)) as! [String: Any]
        // The Train write may not cost the dashboard either of its sides.
        #expect((object["desktop"] as! [String: Any])["slots"] != nil)
        #expect(Dashboard.fromStored(object, surface: .phone) == layout)

        // …and arranging the dashboard again may not bring the Cardio card back.
        try db.saveDashboardLayout(userId: user, Dashboard.resizeSlot(layout, slotId: "sl-vitals"))
        #expect(db.trainLayout(userId: user).hidden == [.cardio])
    }

    // ── W9: the Pulse squares ride in this row too ──────────────────────────

    @Test("a pulse save keeps both dashboard sides and the train key; a dashboard save keeps the pulse key")
    func pulseSharesTheRow() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let webRow = #"{"v":4,"desktop":{"slots":[{"id":"d1","size":"xl","items":["recovery"]}],"hidden":[],"updatedAt":5}}"#
        try db.writer.write { try DashboardLayoutRow(userId: user, layout: JSONText(raw: webRow), updatedAt: Date()).insert($0) }

        var layout = Dashboard.defaultLayout(.phone)
        layout = Dashboard.resizeSlot(layout, slotId: "sl-sleep")
        try db.saveDashboardLayout(userId: user, layout)
        try db.saveTrainLayout(userId: user, TrainLayout.default.setting(.cardio, visible: false))
        let order = PulseLayout.default.moving(.stack, to: .stress)
        try db.savePulseLayout(userId: user, order)

        #expect(db.pulseLayout(userId: user) == order)
        #expect(db.trainLayout(userId: user).hidden == [.cardio])
        let stored = try db.writer.read { try DashboardLayoutRow.filter(Column("user_id") == user).fetchOne($0) }
        let object = try JSONSerialization.jsonObject(with: Data(stored!.layout.raw.utf8)) as! [String: Any]
        #expect((object["desktop"] as! [String: Any])["slots"] != nil)
        #expect(Dashboard.fromStored(object, surface: .phone) == layout)
        // The stream's decoded row reads the same order.
        #expect(StoredDashboardLayout(stored!).pulse == order)

        // Arranging the dashboard again, or the Train tab, may not put the squares back.
        try db.saveDashboardLayout(userId: user, Dashboard.resizeSlot(layout, slotId: "sl-vitals"))
        try db.saveTrainLayout(userId: user, .default)
        #expect(db.pulseLayout(userId: user) == order)
        #expect(try db.pendingOutbox().allSatisfy { $0.kind == SyncKind.rowUpsert })
    }

    @Test("a store that has never held a layout row reads the squares in declaration order")
    func pulseDefaultsOnAnEmptyStore() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        #expect(db.pulseLayout(userId: user) == .default)
        #expect(db.pulseLayout(userId: user).order == PulseSquare.allCases)
    }

    @Test("a store that has never held a layout row reads as everything visible")
    func trainDefaultsOnAnEmptyStore() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        #expect(db.trainLayout(userId: user) == .default)
    }

    @Test("a train save queues the row like any other mirrored write")
    func trainSaveQueues() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try db.saveTrainLayout(userId: user, TrainLayout.default.setting(.pastWeeks, visible: false))
        let outbox = try db.pendingOutbox()
        #expect(outbox.map(\.kind) == [SyncKind.rowUpsert])
        let ref = try OnyxJSON.decoder.decode(RowRef.self, from: outbox[0].payload)
        #expect(ref.table == "dashboard_layouts")
        #expect(ref.id == user)
        // The row it minted is still a readable dashboard, not a train-only
        // object the grid would choke on.
        #expect(!Dashboard.fromStored(
            try JSONSerialization.jsonObject(
                with: Data(db.writer.read { try DashboardLayoutRow.filter(Column("user_id") == user).fetchOne($0) }!.layout.raw.utf8)
            ),
            surface: .phone
        ).slots.isEmpty)
    }

    @MainActor @Test("the stream yields the reconciled layout after a save")
    func streamYields() async throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        var layout = Dashboard.defaultLayout(.phone)
        layout = Dashboard.removeFace(layout, slotId: "sl-water", index: 0)
        try db.saveDashboardLayout(userId: user, layout)
        for try await stored in db.dashboardLayoutStream(userId: user) {
            #expect(stored?.layout.hidden == [.water])
            break
        }
    }
}

@Suite("Today feed — one build, four cards")
struct TodayFeedBuilderTests {
    private let user = "00000000-0000-0000-0000-000000000001"
    private let tz = TimeZone(identifier: "Europe/London")!
    /// Thu 3 Sep 2026, 08:15 London.
    private var now: Date { ISO8601DateFormatter().date(from: "2026-09-03T07:15:00Z")! }

    @Test("an empty mirror builds an empty feed rather than throwing")
    func emptyMirror() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        let feed = try TodayFeedBuilder(database: db, userId: user, timeZone: tz).build(now: now)
        #expect(feed.snapshot.date == "2026-09-03")
        // No weigh-ins and no ledger, but the phase's own targets still stand:
        // the board says what the phase asked for and "—" for what it measured.
        #expect(feed.goalBoard.ratePerWeekKg == nil)
        #expect(feed.goalBoard.pace == .unknown)
        #expect(feed.goalBoard.weekDaysCounted == 0)
        // No `plan_phase_goals` row in this store, so no destination (W2: the
        // compiled preset no longer fills in).
        #expect(feed.goalBoard.targetWeightKg == nil)
        #expect(feed.weekSoFar.current == .empty)
        #expect(feed.weekSoFar.change == nil)
        #expect(!feed.weeklySummaryReady)
        #expect(feed.weekSoFar.dayOfWeek >= 1 && feed.weekSoFar.dayOfWeek <= 7)
    }

    @Test("sessions split by week and the change names what moved")
    func weekTotals() throws {
        let db = try AppDatabase.inMemory(deviceId: "device-a")
        try db.editUserGoals(userId: user) { $0.weekEndDay = 6; $0.activePlan = "onyx5" }   // weeks start Sunday
        try db.writer.write { g in
            // This week (Sun 30 Aug…): two sessions. Last week: one, heavier.
            for (id, date, kg) in [("a", "2026-08-31", 100.0), ("b", "2026-09-01", 120.0), ("c", "2026-08-25", 300.0)] {
                try WorkoutSession(id: id, userId: user, dayKey: "upper_a", date: date).insert(g)
                try WorkoutSet(id: "\(id)-1", sessionId: id, exerciseId: "x", setIndex: 1, weightKg: kg, reps: 10).insert(g)
            }
        }
        let feed = try TodayFeedBuilder(database: db, userId: user, timeZone: tz).build(now: now)
        #expect(feed.weekSoFar.weekStart == "2026-08-30")
        #expect(feed.weekSoFar.current.sessions == 2)
        #expect(feed.weekSoFar.previous.sessions == 1)
        #expect(feed.weekSoFar.current.volumeKg == 2200)
        #expect(feed.weekSoFar.previous.volumeKg == 3000)
        // −27% tonnage outranks +1 session.
        #expect(feed.weekSoFar.change?.label == "Tonnage")
        #expect(feed.weekSoFar.change?.direction == .down)
        #expect(feed.weekSoFar.dayOfWeek == 5)
    }
}
