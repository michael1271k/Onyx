import Testing
import Foundation
import OnyxCore
import OnyxData
@testable import Onyx

/// The dose-history claim, through the screens' own model.
///
/// A dose is changed TODAY through `DayModel.editSupplement` — the call the
/// Stack screen's editor makes — and then yesterday is opened the way swiping
/// back on Pulse opens it. The day's stack (what the Stack screen and the
/// Pulse day draw) and the weekly export must both still say the old dose for
/// yesterday and the new one for today. `DoseHistoryStoreTests` proves the
/// same at the store; this proves the app's model does not route around it.
@MainActor
@Suite("Dose history — the Pulse day and the export")
struct DoseHistoryDayTests {

    private static let userId = "00000000-0000-0000-0000-000000000001"

    private func settle(_ done: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !done(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
    }

    @Test("a dose changed today leaves yesterday at the old dose, on the day and in the export")
    func changeLeavesYesterdayAlone() async throws {
        // The edit below is a rearming write: with a switch left on in this
        // simulator it would replace the developer's pending reminders with
        // this test's store.
        UserDefaults.standard.removeObject(forKey: OnyxReminders.enabledKey)
        UserDefaults.standard.removeObject(forKey: OnyxReminders.supplementsKey)
        let database = try AppDatabase.inMemory(deviceId: "test")
        let today = LogicalDay.today()
        let yesterday = try #require(ISODate.addDays(today, -1))
        try database.addCustomSupplement(
            userId: Self.userId, name: "Magnesium", dose: "300 mg", time: "22:00",
            schedule: CustomSchedule(key: "magnesium"), doseAmount: 300, doseUnit: "mg")

        // Change it the way the editor does, on today's page.
        let now = DayModel(database: database, userId: Self.userId, date: today)
        let watchingNow = Task { await now.observe() }
        defer { watchingNow.cancel() }
        try await settle { !now.doses.isEmpty }
        let first = try #require(now.doses.first)
        let custom = try #require(now.custom(for: first))
        #expect(now.editSupplement(
            custom, name: "Magnesium", dose: "200 mg", doseAmount: 200, doseUnit: "mg",
            form: nil, time: "22:00", days: [], trainingOnly: false))
        try await settle { now.doses.first?.dose == "200 mg" }
        #expect(now.doses.first?.dose == "200 mg")

        // Swipe back a day.
        let past = DayModel(database: database, userId: Self.userId, date: yesterday)
        let watchingPast = Task { await past.observe() }
        defer { watchingPast.cancel() }
        try await settle { !past.doses.isEmpty }
        #expect(past.doses.first?.dose == "300 mg")

        // And the export of the two days.
        let input = try WeeklyExportBuilder(database: database, userId: Self.userId)
            .input(span: ExportSpan(start: yesterday, end: today), today: today)
        let logged = { (date: String) in input.days.first { $0.date == date }?.supplementsLog?.first?.dose }
        #expect(logged(yesterday) == "300 mg")
        #expect(logged(today) == "200 mg")
        #expect(input.days.first { $0.date == today }?.supplementDoseChanges
            == [ExportDoseChange(name: "Magnesium", from: "300 mg", to: "200 mg")])
    }
}
