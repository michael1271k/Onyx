import Testing
@testable import Onyx

/// The one rule that decides whether opening the InBody sheet and closing it
/// again writes a second weigh-in.
///
/// ── WHY THIS IS A TEST AND NOT A SCREENSHOT ─────────────────────────────────
/// W3 pre-fills every empty field from the last reading and from Apple Health.
/// A form that arrives full looks identical whether the pre-fill was written
/// into the edit buffer or held beside it — and in the first case Save is live
/// the instant the sheet opens, so dismissing an untouched screen commits a
/// duplicate reading dated today. Nothing about the pixels says which one
/// shipped; this does.
@Suite("InBody save gate")
struct InBodySaveGateTests {

    private typealias Field = InBodyField
    private let all = Array(Field.allCases)

    private func pending(
        stored: [Field: Double] = [:],
        draft: [Field: Double] = [:],
        seeded: Set<Field> = [],
        touched: Set<Field> = []
    ) -> Set<Field> {
        InBodySaveGate.pendingFields(
            all: all, stored: stored, draft: draft, seeded: seeded, touched: touched
        )
    }

    @Test("a day WITH a reading opens with Save disabled, however much was pre-filled")
    func untouchedSheetOnAReadingDayWritesNothing() {
        // What `onAppear` does: the draft is seeded from the DAY, and every
        // field the day does not have is offered from the last reading.
        let stored: [Field: Double] = [.weight: 64.8, .bodyFat: 15.2]
        let seeded: Set<Field> = [.muscle, .water, .protein, .bone, .bmr, .skeletal, .waist]

        #expect(pending(stored: stored, draft: stored, seeded: seeded).isEmpty)
    }

    @Test("a real edit opens the gate, and only for the field that changed")
    func onlyTheEditedFieldIsWritten() {
        let stored: [Field: Double] = [.weight: 64.8, .bodyFat: 15.2]
        var draft = stored
        draft[.weight] = 64.2

        let out = pending(stored: stored, draft: draft, seeded: [.muscle], touched: [.weight])
        #expect(out == [.weight])
    }

    @Test("a day with NO reading saves what the sheet seeded")
    func theFirstReadingOfTheDayIsSaveable() {
        // Nothing stored; the sheet offered the previous reading's figures.
        let seeded: Set<Field> = [.weight, .bodyFat, .muscle]
        let out = pending(stored: [:], draft: [:], seeded: seeded)
        #expect(out == seeded)
    }

    @Test("clearing a pre-filled field on a fresh day withdraws it from the save")
    func aClearedSeedIsNotWritten() {
        let seeded: Set<Field> = [.weight, .bodyFat, .muscle]
        // The user emptied Muscle: `touched` holds it, `draft` has nothing.
        let out = pending(stored: [:], draft: [:], seeded: seeded, touched: [.muscle])
        #expect(out == [.weight, .bodyFat])
    }

    @Test("clearing a field the DAY holds is not an edit — blank stays blank")
    func clearingAStoredFieldDoesNotWrite() {
        let stored: [Field: Double] = [.weight: 64.8, .bodyFat: 15.2]
        var draft = stored
        draft[.bodyFat] = nil

        #expect(pending(stored: stored, draft: draft, touched: [.bodyFat]).isEmpty)
    }

    @Test("typing a value a fresh day had none of is written even without a seed")
    func aTypedValueOnAnEmptyDayIsWritten() {
        let out = pending(stored: [:], draft: [.waist: 81.5], touched: [.waist])
        #expect(out == [.waist])
    }

    @Test("re-typing the value the day already holds writes nothing")
    func anIdenticalValueIsNotAnEdit() {
        let stored: [Field: Double] = [.weight: 64.8]
        #expect(pending(stored: stored, draft: [.weight: 64.8], touched: [.weight]).isEmpty)
    }

    // MARK: What a save may derive a mass from

    @Test("a mass is never derived from a figure the gate refused to write")
    func seededPercentagesDoNotReachTheMassColumns() {
        // 09-17 holds a weight pulled from HealthKit and nothing else. The
        // sheet seeded last week's percentages. The athlete corrects the WAIST
        // and saves.
        let stored: [Field: Double] = [.weight: 65.2]
        let writing: [Field: Double] = [.waist: 81.5]

        let inputs = InBodySaveGate.massInputs(stored: stored, writing: writing)

        // The weight is the day's own, so a mass may use it...
        #expect(inputs[.weight] == 65.2)
        #expect(inputs[.waist] == 81.5)
        // ...but last week's body fat is not in here, so `derive` returns nil
        // for fat mass and the column is never written. Before this rule the
        // day grew six mass columns computed from a week-old reading while
        // every percentage column on it stayed null.
        #expect(inputs[.bodyFat] == nil)
        #expect(inputs[.muscle] == nil)
        #expect(inputs[.water] == nil)
        #expect(inputs[.protein] == nil)
        #expect(inputs[.bone] == nil)
    }

    @Test("a typed figure overrides the day's own for the masses it feeds")
    func writtenValuesWinOverStored() {
        let stored: [Field: Double] = [.weight: 65.2, .bodyFat: 18.0]
        let writing: [Field: Double] = [.bodyFat: 17.4]
        let inputs = InBodySaveGate.massInputs(stored: stored, writing: writing)
        #expect(inputs[.bodyFat] == 17.4)
        #expect(inputs[.weight] == 65.2)
    }
}
