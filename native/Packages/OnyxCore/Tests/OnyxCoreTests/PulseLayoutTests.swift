import Foundation
import Testing
@testable import OnyxCore

/// The Pulse squares' order, riding in the dashboard's row (W9).
///
/// The claim under test is the one `TrainLayoutTests` makes for the third key:
/// a fourth key on a shared payload cannot cost the payload anything it held.
@Suite("Pulse layout — the fourth key on dashboard_layouts")
struct PulseLayoutTests {

    @Test("a payload with no pulse key is the declaration order")
    func absentIsDefault() {
        let layout = Dashboard.pulseLayout(from: ["v": 4.0, "phone": ["slots": []]])
        #expect(layout == .default)
        #expect(layout.order == PulseSquare.allCases)
        #expect(PulseSquare.allCases == [.stress, .stressLog, .soreness, .fatigue, .scale, .stack])
    }

    @Test("nothing that is not a readable pulse object reorders anything")
    func brokenShapesAreDefaults() {
        #expect(Dashboard.pulseLayout(from: nil) == .default)
        #expect(Dashboard.pulseLayout(from: [Any]()) == .default)
        #expect(Dashboard.pulseLayout(from: ["pulse": 0]) == .default)
        #expect(Dashboard.pulseLayout(from: ["pulse": NSNull()]) == .default)
        #expect(Dashboard.pulseLayout(from: ["pulse": ["order": "stack"]]) == .default)
    }

    /// A square a later wave adds arrives at the END for everyone who has
    /// already saved an order; a name a later wave removes is dropped.
    @Test("missing squares are appended in declaration order, unknown names dropped, duplicates collapsed")
    func reconciles() {
        let read = Dashboard.pulseLayout(from: ["pulse": ["order": ["stack", "nonesuch", "stress", "stack"], "updatedAt": 3]])
        #expect(read.order == [.stack, .stress, .stressLog, .soreness, .fatigue, .scale])
        #expect(read.updatedAt == 3)
        #expect(PulseLayout(order: []).order == PulseSquare.allCases)
    }

    @Test("moving a square puts it at the target's position and closes the gap")
    func moves() {
        let moved = PulseLayout.default.moving(.stack, to: .stress)
        #expect(moved.order == [.stack, .stress, .stressLog, .soreness, .fatigue, .scale])
        #expect(moved.updatedAt > 0)
        let forward = PulseLayout.default.moving(.stress, to: .fatigue)
        #expect(forward.order == [.stressLog, .soreness, .fatigue, .stress, .scale, .stack])
        // Onto itself is a no-op, stamp included.
        #expect(PulseLayout.default.moving(.scale, to: .scale) == .default)
    }

    @Test("an order survives the round trip")
    func roundTrips() {
        let layout = PulseLayout.default.moving(.scale, to: .stress)
        let read = Dashboard.pulseLayout(from: Dashboard.withPulse(layout, in: ["v": 4.0]))
        #expect(read == layout)
    }

    // MARK: - The key the tab shares

    /// THE defect: dragging a dashboard tile putting the Pulse squares back.
    @Test("writing the dashboard carries the pulse key through untouched")
    func dashboardWriteKeepsPulse() {
        let stored = Dashboard.withPulse(
            PulseLayout.default.moving(.stack, to: .stress),
            in: Dashboard.withTrain(
                TrainLayout.default.setting(.cardio, visible: false),
                in: ["v": 4.0, "phone": ["slots": []], "desktop": ["slots": []]]
            )
        )
        let out = Dashboard.serializeLayout(Dashboard.defaultLayout(.phone), surface: .phone, other: stored)
        #expect(Dashboard.pulseLayout(from: out).order.first == .stack)
        #expect(Dashboard.trainLayout(from: out).hidden == [.cardio])
        #expect(out["desktop"] != nil)
    }

    /// The mirror image: writing the Pulse order may not cost the dashboard a
    /// slot, the Train tab a section, or the payload its version.
    @Test("writing the pulse key carries both surfaces and the train key through untouched")
    func pulseWriteKeepsTheRest() {
        let dashboard = Dashboard.withTrain(
            TrainLayout.default.setting(.doors, visible: false),
            in: Dashboard.serializeLayout(
                Dashboard.defaultLayout(.phone), surface: .phone, other: ["v": 4.0, "desktop": ["slots": []]]
            )
        )
        let out = Dashboard.withPulse(PulseLayout.default.moving(.scale, to: .stress), in: dashboard)
        #expect(Dashboard.fromStored(out, surface: .phone) == Dashboard.fromStored(dashboard, surface: .phone))
        #expect(out["desktop"] != nil)
        #expect(Dashboard.trainLayout(from: out).hidden == [.doors])
        #expect((out["v"] as? Double) == (dashboard["v"] as? Double))
        // …and a train write after it keeps the pulse key.
        let again = Dashboard.withTrain(.default, in: out)
        #expect(Dashboard.pulseLayout(from: again).order.first == .scale)
    }

    /// A row a Pulse-only edit minted is still a readable dashboard.
    @Test("a row holding only a pulse key is still a readable dashboard")
    func pulseOnlyPayload() {
        let out = Dashboard.withPulse(PulseLayout.default.moving(.stack, to: .stress), in: nil)
        #expect(Dashboard.pulseLayout(from: out).order.first == .stack)
        #expect(Dashboard.fromStored(out, surface: .phone).slots.count == WidgetId.allCases.count)
    }
}
