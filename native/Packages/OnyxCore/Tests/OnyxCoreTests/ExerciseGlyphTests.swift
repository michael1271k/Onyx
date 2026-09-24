import Foundation
import Testing
@testable import OnyxCore

/// Overhaul C1 (decision Q13) — one SF Symbol per movement PATTERN.
///
/// The golden is a hand-written table, not a dump of the code under test: it
/// names the pattern every catalogue movement is FOR, and the resolver has to
/// agree with it. A movement the table does not know must land on the one
/// documented fallback, never on a guess.
@Suite("Exercise glyphs — pattern → SF Symbol")
struct ExerciseGlyphTests {

    /// Every movement the founder's templates prescribe, plus the bout names
    /// a warm-up card and a Health import carry.
    static let golden: [String: ExerciseGlyph.Pattern] = [
        "Bicep Curl DB": .arms, "Hammer Curl": .arms, "Hammer Curl DB": .arms,
        "Preacher Curl": .arms, "Reverse EZ-Bar Curl": .arms, "Seated DB Wrist Curl": .arms,
        "Seated Incline DB Curl": .arms, "Overhead Triceps Extension": .arms,
        "Rope Triceps Pushdown": .arms, "Single Arm Triceps Pushdown": .arms,
        "Butterfly Pec Deck": .fly, "Pec Deck": .fly, "Single Arm Cable Crossover": .fly,
        "Lateral Raise DB": .fly, "Single Arm Lateral Raise": .fly,
        "Chest Press": .press, "Chest Press Machine": .press, "Incline DB Press": .press,
        "Shoulder Press": .press,
        "Lat Pulldown": .verticalPull, "Neutral-Grip Lat Pulldown": .verticalPull,
        "Straight Arm Pulldown": .verticalPull, "Straight-Arm Pulldown": .verticalPull,
        "Seated Cable Row": .horizontalPull, "Seated Cable Row (V-Grip)": .horizontalPull,
        "Seated Cable Row (Wide Grip)": .horizontalPull, "Face Pull": .horizontalPull,
        "Hack Squat": .squat, "Leg Press": .squat, "Leg Extension": .squat, "Hip Adduction": .squat,
        "Hip Thrust": .hinge, "RDL DB": .hinge, "Romanian Deadlift": .hinge, "Seated Leg Curl": .hinge,
        "Calf Press": .calf,
        "Crunch Machine": .core, "Hanging Knee Raise": .core, "Hollow Rock": .core,
        "Lying Leg Raises": .core, "Reverse Crunch": .core, "Russian Twist": .core,
        "Side Plank": .hold,
        "Treadmill": .treadmill, "Walk": .walk, "Run": .run, "Stair Stepper": .stairs,
        "Elliptical": .elliptical, "Cycling": .cycle, "Rowing": .rowErg, "HIIT": .intervals,
    ]

    @Test("every catalogue movement resolves to the pattern it is for")
    func catalogueResolves() throws {
        let url = try #require(Bundle.module.url(forResource: "plan-templates", withExtension: "json", subdirectory: "Fixtures"))
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let plans = try #require(json["plans"] as? [[String: Any]])
        let names = Set(plans.flatMap { ($0["days"] as? [[String: Any]] ?? []).flatMap {
            ($0["exercises"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        } })
        #expect(names.count >= 40, "the fixture still holds the catalogue")
        for name in names {
            #expect(Self.golden[name] != nil, "\(name) has no golden pattern — add it")
        }
        for (name, pattern) in Self.golden {
            #expect(ExerciseGlyph.pattern(for: name) == pattern, "\(name)")
            #expect(ExerciseGlyph.symbol(for: name) == pattern.symbol, "\(name)")
        }
    }

    @Test("an unknown movement lands on the one documented fallback")
    func unknownFallsBack() {
        for name in ["Zercher Thing", "", "   "] {
            #expect(ExerciseGlyph.pattern(for: name) == nil)
            #expect(ExerciseGlyph.symbol(for: name) == ExerciseGlyph.fallback)
        }
        // A name the dictionary knows only by its primary mover still resolves.
        #expect(ExerciseGlyph.pattern(for: "Machine Fly") == .fly)
    }

    @Test("about twenty symbols, and the fallback is not a pattern's own")
    func symbolBudget() {
        let symbols = Set(ExerciseGlyph.Pattern.allCases.map(\.symbol))
        #expect((14...22).contains(symbols.count))
        #expect(!symbols.contains(ExerciseGlyph.fallback))
    }
}
