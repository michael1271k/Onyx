import Foundation
import Testing
@testable import OnyxCore

/// The Train tab's sections, riding in the dashboard's row.
///
/// The claim under test is not "five booleans round-trip" — it is that a key
/// added to a shared payload cannot cost the payload anything it already held.
@Suite("Train layout — the third key on dashboard_layouts")
struct TrainLayoutTests {

    @Test("a payload with no train key shows everything")
    func absentMeansVisible() {
        let layout = Dashboard.trainLayout(from: ["v": 4.0, "phone": ["slots": []]])
        #expect(layout == .default)
        for section in TrainSection.allCases { #expect(layout.shows(section)) }
    }

    /// Every shape a corrupt row can take reads as the defaults — the same
    /// contract `fromStored` keeps, and for the same reason: a tab that came up
    /// half-empty because a JSON value was a number is worse than one that
    /// ignores it.
    @Test("nothing that is not a readable train object hides anything")
    func brokenShapesAreDefaults() {
        #expect(Dashboard.trainLayout(from: nil) == .default)
        #expect(Dashboard.trainLayout(from: [Any]()) == .default)
        #expect(Dashboard.trainLayout(from: ["train": 0]) == .default)
        #expect(Dashboard.trainLayout(from: ["train": NSNull()]) == .default)
        #expect(Dashboard.trainLayout(from: ["train": ["hidden": "cardio"]]) == .default)
        #expect(Dashboard.trainLayout(from: ["train": ["hidden": ["nonesuch"]]]) == .default)
    }

    @Test("a hidden section survives the round trip")
    func roundTrips() {
        let hidden = TrainLayout.default.setting(.cardio, visible: false).setting(.pastWeeks, visible: false)
        let payload = Dashboard.withTrain(hidden, in: ["v": 4.0])
        let read = Dashboard.trainLayout(from: payload)
        #expect(read.hidden == [.cardio, .pastWeeks])
        #expect(!read.shows(.cardio))
        #expect(read.shows(.trends))
    }

    /// Two devices that hid the same two sections in opposite orders must store
    /// the same bytes, or every read is a spurious sync round trip.
    @Test("the hidden list is stored in declaration order whatever order it was made in")
    func hiddenIsOrdered() {
        let a = TrainLayout.default.setting(.pastWeeks, visible: false).setting(.doors, visible: false)
        let b = TrainLayout.default.setting(.doors, visible: false).setting(.pastWeeks, visible: false)
        #expect(a.hidden == b.hidden)
        #expect(a.hidden == [.doors, .pastWeeks])
    }

    @Test("showing a section that was never hidden changes nothing but the stamp")
    func showingIsIdempotent() {
        let shown = TrainLayout.default.setting(.cardio, visible: true)
        #expect(shown.hidden.isEmpty)
        #expect(shown.updatedAt > 0)
    }

    @Test("hiding the same section twice does not store it twice")
    func hidingIsIdempotent() {
        let twice = TrainLayout.default.setting(.cardio, visible: false).setting(.cardio, visible: false)
        #expect(twice.hidden == [.cardio])
    }

    // MARK: - The key the tab shares

    /// THE defect this key could have introduced: dragging a dashboard tile
    /// putting the Train tab's Cardio card back.
    @Test("writing the dashboard carries the train key through untouched")
    func dashboardWriteKeepsTrain() {
        let stored = Dashboard.withTrain(
            TrainLayout.default.setting(.cardio, visible: false),
            in: ["v": 4.0, "phone": ["slots": []], "desktop": ["slots": []]]
        )
        let out = Dashboard.serializeLayout(Dashboard.defaultLayout(.phone), surface: .phone, other: stored)
        #expect(Dashboard.trainLayout(from: out).hidden == [.cardio])
        // …and the desktop side it has always carried is still there.
        #expect(out["desktop"] != nil)
    }

    /// The mirror image: writing the Train arrangement may not cost the
    /// dashboard a slot.
    @Test("writing the train key carries both dashboard surfaces through untouched")
    func trainWriteKeepsBothSurfaces() {
        let dashboard = Dashboard.serializeLayout(
            Dashboard.defaultLayout(.phone), surface: .phone, other: ["v": 4.0, "desktop": ["slots": []]]
        )
        let out = Dashboard.withTrain(TrainLayout.default.setting(.doors, visible: false), in: dashboard)
        #expect(Dashboard.fromStored(out, surface: .phone) == Dashboard.fromStored(dashboard, surface: .phone))
        #expect(out["desktop"] != nil)
        #expect(Dashboard.trainLayout(from: out).hidden == [.doors])
    }

    /// The payload `v` is the SIDES gate (`fromStored`), not a label. Bumping
    /// it for this key would have read every stored v4 row as "no sides" and
    /// handed every user the default dashboard.
    @Test("the train key does not disturb the payload version or the sides")
    func versionIsUntouched() {
        let before = Dashboard.serializeLayout(Dashboard.defaultLayout(.phone), surface: .phone)
        let after = Dashboard.withTrain(TrainLayout.default.setting(.trends, visible: false), in: before)
        #expect((after["v"] as? Double) == (before["v"] as? Double))
        #expect(Dashboard.fromStored(after, surface: .phone) == Dashboard.fromStored(before, surface: .phone))
    }

    /// A payload that has never held a dashboard at all — a row a Train-only
    /// edit minted — still reads as the default dashboard rather than nothing.
    @Test("a row holding only a train key is still a readable dashboard")
    func trainOnlyPayload() {
        let out = Dashboard.withTrain(TrainLayout.default.setting(.cardio, visible: false), in: nil)
        #expect(Dashboard.trainLayout(from: out).hidden == [.cardio])
        #expect(Dashboard.fromStored(out, surface: .phone).slots.count == WidgetId.allCases.count)
    }
}
