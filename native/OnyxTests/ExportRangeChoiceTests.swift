import Foundation
import OnyxCore
import Testing
@testable import Onyx

/// The Shortcuts enum and the domain enum are one set of cases (W7).
///
/// ── WHY THIS TEST IS THE ONLY THING HOLDING THEM TOGETHER ───────────────────
/// `ExportRange` lives in OnyxCore, which is Foundation-only and stays so, and
/// the App Intents metadata extractor requires `caseDisplayRepresentations` to
/// be a literal dictionary it can read out of the source — so it cannot be
/// derived from `ExportRange.label`. `ExportRangeChoice` is therefore a second
/// declaration of the same four cases, and `ExportRangeChoice.range` falls back
/// to `.sinceLastExport` for a raw value it does not recognise.
///
/// Without this, a fifth `ExportRange` case never appears in Shortcuts, and a
/// renamed raw value makes a saved Shortcut silently export a DIFFERENT span
/// than the one its owner picked — with no compile error anywhere.
@Suite("Export range — two declarations, one set of cases")
struct ExportRangeChoiceTests {

    @Test("the two enums declare exactly the same raw values")
    func caseSetsMatch() {
        #expect(Set(ExportRangeChoice.allCases.map(\.rawValue))
                == Set(ExportRange.allCases.map(\.rawValue)))
        #expect(ExportRangeChoice.allCases.count == ExportRange.allCases.count)
    }

    /// And every one of them round-trips — so `range` never reaches its
    /// fallback for a case the app actually offers.
    @Test("every choice resolves to its own range, never to the fallback")
    func everyChoiceResolves() {
        for choice in ExportRangeChoice.allCases {
            #expect(ExportRange(rawValue: choice.rawValue) != nil, "\(choice.rawValue) is not an ExportRange")
            #expect(choice.range.rawValue == choice.rawValue, "\(choice.rawValue) resolved to \(choice.range.rawValue)")
        }
    }

    /// Every case Shortcuts shows has a display title. A missing entry is not a
    /// compile error — the dictionary is a literal, and a case left out of it
    /// renders as a blank row in the picker.
    @Test("every choice has a display representation")
    func everyChoiceHasATitle() {
        for choice in ExportRangeChoice.allCases {
            #expect(ExportRangeChoice.caseDisplayRepresentations[choice] != nil,
                    "\(choice.rawValue) has no DisplayRepresentation")
        }
    }
}
