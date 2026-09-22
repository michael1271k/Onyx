import Testing
@testable import OnyxCore

@Suite("Today's relevance ordering — the hero moves, the page does not")
struct DashboardRelevanceTests {

    private func layout(_ ids: [WidgetId], updatedAt: Double = 0) -> DashboardLayout {
        DashboardLayout(
            slots: ids.enumerated().map { StackSlot(id: "s\($0.offset)", size: .m, items: [$0.element]) },
            hidden: [],
            updatedAt: updatedAt
        )
    }
    private func order(_ l: DashboardLayout) -> [WidgetId] { l.slots.flatMap(\.items) }

    @Test("morning leads with sleep, recovery, the session")
    func morning() {
        let out = Dashboard.relevanceOrdered(layout([.fuel, .water, .train, .recovery, .sleep]), minuteOfDay: 7 * 60)
        #expect(order(out) == [.sleep, .recovery, .train, .fuel, .water])
    }

    @Test("evening leads with fuel, water, tomorrow")
    func evening() {
        let out = Dashboard.relevanceOrdered(layout([.sleep, .recovery, .train, .fuel, .water]), minuteOfDay: 20 * 60)
        #expect(order(out) == [.fuel, .water, .train, .sleep, .recovery])
    }

    @Test("midday moves nothing")
    func midday() {
        let start = layout([.sleep, .recovery, .train, .fuel, .water])
        #expect(Dashboard.relevanceOrdered(start, minuteOfDay: 14 * 60) == start)
    }

    @Test("an arranged layout is never re-ordered")
    func pinned() {
        let start = layout([.fuel, .water, .train, .recovery, .sleep], updatedAt: 1_726_000_000_000)
        #expect(Dashboard.relevanceOrdered(start, minuteOfDay: 7 * 60) == start)
    }

    @Test("every card survives, in every band")
    func nothingIsLost() {
        let start = layout(WidgetId.allCases)
        for minute in stride(from: 0, to: 1440, by: 30) {
            let out = Dashboard.relevanceOrdered(start, minuteOfDay: minute)
            #expect(Set(order(out)) == Set(WidgetId.allCases))
            #expect(out.slots.count == start.slots.count)
            #expect(out.hidden == start.hidden)
        }
    }

    @Test("unranked cards keep their stored order behind the leaders")
    func stable() {
        let out = Dashboard.relevanceOrdered(layout([.steps, .micros, .sleep, .bar, .cardio]), minuteOfDay: 6 * 60)
        #expect(order(out) == [.sleep, .steps, .micros, .bar, .cardio])
    }

    @Test("a stack is ranked by the best card in it")
    func stackTakesItsBest() {
        let stacked = DashboardLayout(
            slots: [
                StackSlot(id: "a", size: .m, items: [.steps, .cardio]),
                StackSlot(id: "b", size: .m, items: [.micros, .sleep]),
            ],
            hidden: [], updatedAt: 0
        )
        let out = Dashboard.relevanceOrdered(stacked, minuteOfDay: 8 * 60)
        #expect(out.slots.map(\.id) == ["b", "a"])
    }
}
