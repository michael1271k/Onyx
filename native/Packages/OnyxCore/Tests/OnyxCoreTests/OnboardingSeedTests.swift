import Foundation
import Testing
@testable import OnyxCore

// The arithmetic and the parsing a new account's first screens run on. Every
// number here is hand-computed — from W1 there is no TypeScript oracle to
// generate them from (D7).

@Suite("W5 · the MEV table")
struct VolumeLandmarkTests {

    /// A muscle missing from the table seeds a target of ZERO, and a zero
    /// target reads as "met" on the muscle sheet for the life of the account.
    @Test func everyLandmarkHasALandmark() {
        for muscle in LandmarkMuscle.allCases {
            #expect(VolumeLandmarks.table[muscle] != nil, "\(muscle.rawValue) has no volume landmark")
        }
        #expect(VolumeLandmarks.table.count == LandmarkMuscle.allCases.count)
    }

    /// MEV is the floor of the productive range and MAV its middle. A table
    /// where a muscle's minimum exceeded its maximum would seed a bulk with
    /// LESS volume than the cut it came from.
    @Test func mevNeverExceedsMav() {
        for (muscle, landmark) in VolumeLandmarks.table {
            #expect(landmark.mev <= landmark.mav, "\(muscle.rawValue): MEV \(landmark.mev) > MAV \(landmark.mav)")
            #expect(landmark.mev > 0, "\(muscle.rawValue) would seed an unmeetable zero")
        }
    }

    @Test func cutHoldsAtMevAndBulkReachesForMav() {
        let chest = VolumeLandmarks.table[.chest]!
        #expect(chest.target(for: .cut) == chest.mev)
        #expect(chest.target(for: .bulk) == chest.mav)
        // Maintaining trains on the cut's volume — it has no phase of its own.
        #expect(StartingGoal.maintain.phase == .cut)
        #expect(StartingGoal.cut.phase == .cut)
        #expect(StartingGoal.bulk.phase == .bulk)
    }

    /// The order the onboarding list and the Weekly-set-volume screen both read
    /// down the body in. `allCases` order is load-bearing (`Landmarks.swift`).
    @Test func startingFollowsDeclarationOrder() {
        #expect(VolumeLandmarks.starting(for: .cut).map(\.muscle) == LandmarkMuscle.allCases)
        #expect(VolumeLandmarks.weeklyTotal(for: .bulk) > VolumeLandmarks.weeklyTotal(for: .cut))
    }
}

@Suite("W5 · landmark tokens")
struct LandmarkTokenTests {

    /// The round trip that stops an imported movement earning nothing.
    ///
    /// `Abs/core` is the one that fails on `rawValue` — the slash is not folded
    /// by `from(token:)` — which is why `token` exists at all.
    @Test func everyStoredTokenResolvesBack() {
        for muscle in LandmarkMuscle.allCases {
            #expect(LandmarkMuscle.from(token: muscle.token) == muscle, "\(muscle.rawValue) does not round-trip")
        }
    }

    @Test func absCoreIsTheAwkwardOne() {
        #expect(LandmarkMuscle.from(token: LandmarkMuscle.absCore.rawValue) == nil)
        #expect(LandmarkMuscle.absCore.token == "abs")
        #expect(LandmarkMuscle.from(token: "abs") == .absCore)
    }
}

@Suite("W5 · starting macros")
struct StartingTargetsTests {

    /// The app draws a warning when the macros do not account for the calories
    /// (`SettingsModel.atwaterGap`). A seed that trips it on day one teaches
    /// the user to ignore it.
    @Test func theFourNumbersAlwaysAgree() {
        for goal in StartingGoal.allCases {
            for weight in stride(from: 40.0, through: 160.0, by: 2.5) {
                let t = StartingTargetsBuilder.build(weightKg: weight, goal: goal)
                #expect(t.atwaterKcal == t.kcal, "\(goal) at \(weight) kg: \(t.atwaterKcal) vs \(t.kcal)")
            }
        }
    }

    /// 80 kg, cutting. Protein 80 × 2.2 = 176 g. Fat 80 × 0.8 = 64 g.
    /// Budget 80 × 27 = 2,160 kcal. Carbs (2160 − 704 − 576) / 4 = 220 g.
    /// Restated: 176×4 + 220×4 + 64×9 = 704 + 880 + 576 = 2,160 kcal.
    /// Fibre 2.160 × 14 = 30.24 → 30 g.
    @Test func eightyKilosCutting() {
        let t = StartingTargetsBuilder.build(weightKg: 80, goal: .cut)
        #expect(t.proteinG == 176)
        #expect(t.fatG == 64)
        #expect(t.carbsG == 220)
        #expect(t.kcal == 2_160)
        #expect(t.fiberG == 30)
    }

    /// 80 kg, bulking. Protein 144 g, fat 80 g, budget 2,960.
    /// Carbs (2960 − 576 − 720) / 4 = 416 g. Restated 576 + 1664 + 720 = 2,960.
    @Test func eightyKilosBulking() {
        let t = StartingTargetsBuilder.build(weightKg: 80, goal: .bulk)
        #expect(t.proteinG == 144)
        #expect(t.fatG == 80)
        #expect(t.carbsG == 416)
        #expect(t.kcal == 2_960)
    }

    @Test func aGoalMovesTheNumbersTheRightWay() {
        let cut = StartingTargetsBuilder.build(weightKg: 75, goal: .cut)
        let hold = StartingTargetsBuilder.build(weightKg: 75, goal: .maintain)
        let bulk = StartingTargetsBuilder.build(weightKg: 75, goal: .bulk)
        #expect(cut.kcal < hold.kcal)
        #expect(hold.kcal < bulk.kcal)
        // Protein is highest where it defends lean mass.
        #expect(cut.proteinG > bulk.proteinG)
    }

    /// A mistyped 700 kg must not seed a 23,000 kcal target that every screen
    /// then grades against.
    @Test func aTypoIsClampedRatherThanBelieved() {
        let absurd = StartingTargetsBuilder.build(weightKg: 700, goal: .cut)
        let ceiling = StartingTargetsBuilder.build(weightKg: 300, goal: .cut)
        #expect(absurd == ceiling)
        let tiny = StartingTargetsBuilder.build(weightKg: 1, goal: .bulk)
        #expect(tiny == StartingTargetsBuilder.build(weightKg: 30, goal: .bulk))
    }

    /// Carbohydrate is the remainder and the remainder can go negative. Zero,
    /// never a negative gram count — and the kcal figure then honestly reports
    /// what protein and fat alone already cost.
    @Test func carbsNeverGoNegative() {
        let t = StartingTargetsBuilder.build(weightKg: 30, goal: .cut)
        #expect(t.carbsG >= 0)
        #expect(t.atwaterKcal == t.kcal)
    }

    /// Rates are percentages of bodyweight: half a kilo a week is gentle at
    /// 100 kg and brutal at 50.
    @Test func rateScalesWithTheAthlete() {
        let light = StartingTargetsBuilder.weeklyRate(weightKg: 55, goal: .cut)
        let heavy = StartingTargetsBuilder.weeklyRate(weightKg: 110, goal: .cut)
        #expect(light.max < 0 && light.min < light.max)
        #expect(heavy.min < light.min)
        #expect(StartingTargetsBuilder.weeklyRate(weightKg: 80, goal: .maintain) == (0, 0))
        let bulk = StartingTargetsBuilder.weeklyRate(weightKg: 80, goal: .bulk)
        #expect(bulk.min > 0 && bulk.max > bulk.min)
    }
}

@Suite("W5 · CSV import")
struct ExerciseCSVTests {

    @Test func aHeaderedFileReadsItsColumns() {
        let csv = """
        Exercise Name,Primary Muscle,Secondary Muscles,Equipment
        Zercher Squat,Quads,"Glutes, Abs",Barbell
        Meadows Row,Lats,Biceps,Barbell
        """
        let out = ExerciseCSV.parse(csv)
        #expect(out.rows.count == 2)
        #expect(out.rows[0].name == "Zercher Squat")
        #expect(out.rows[0].primaryMuscle == "Quads")
        #expect(out.rows[0].secondaryMuscles == ["Glutes", "abs"])
        #expect(out.rows[0].equipment == "Barbell")
        #expect(out.rows[0].isUnclassified == false)
        // Line 1 is the header, so the first movement is line 2.
        #expect(out.rows[0].line == 2)
        #expect(out.rows[1].line == 3)
    }

    /// A bare list has no header and its first line is a movement, not a
    /// heading.
    @Test func aHeaderlessListIsStillAList() {
        let out = ExerciseCSV.parse("Lat Pulldown\nSled Push\n")
        #expect(out.rows.map(\.name) == ["Lat Pulldown", "Sled Push"])
        #expect(out.rows[0].line == 1)
        // `MuscleMap` knows the pulldown; it does not know the sled push, and
        // that row carried no muscle column. (It was the Zercher squat until
        // Precision A1 taught the map a bare `squat`.)
        #expect(out.rows[0].isUnclassified == false)
        #expect(out.rows[1].isUnclassified == true)
        #expect(out.unclassified == 1)
    }

    /// The commas and newlines inside quotes are the only part of RFC 4180
    /// that actually bites.
    @Test func quotesSurviveCommasAndNewlines() {
        let csv = "name,equipment\n\"Row, Seated\",\"Cable\nmachine\"\n\"He said \"\"go\"\"\",Barbell\n"
        let out = ExerciseCSV.parse(csv)
        #expect(out.rows.count == 2)
        #expect(out.rows[0].name == "Row, Seated")
        #expect(out.rows[0].equipment == "Cable\nmachine")
        #expect(out.rows[1].name == "He said \"go\"")
    }

    @Test func semicolonsAndTabsAndCrlf() {
        let out = ExerciseCSV.parse("name;muscle\r\nHip Thrust;Glutes\r\n")
        #expect(out.rows.count == 1)
        #expect(out.rows[0].name == "Hip Thrust")
        #expect(out.rows[0].primaryMuscle == "Glutes")

        let tabbed = ExerciseCSV.parse("name\tmuscle\nCalf Raise\tCalves\n")
        #expect(tabbed.rows.first?.primaryMuscle == "Calves")
    }

    /// A SPLIT is the expensive mistake — the same movement under a second
    /// name, its history starting again at zero. The import never merges and
    /// never creates over an existing name.
    @Test func existingNamesAreFlaggedNotMerged() {
        let out = ExerciseCSV.parse("name\nbench press\nZercher Squat\n", existingNames: ["Bench Press"])
        #expect(out.rows.count == 2)
        #expect(out.rows[0].isDuplicate == true)
        #expect(out.rows[0].isImportable == false)
        #expect(out.duplicates == 1)
        #expect(out.importable.map(\.name) == ["Zercher Squat"])
    }

    /// A file naming one movement twice would otherwise write two rows and the
    /// unique index would reject the whole batch.
    @Test func aFileIsDeduplicatedAgainstItself() {
        let out = ExerciseCSV.parse("name\nHip Thrust\nhip thrust\n")
        #expect(out.rows.count == 1)
        // Line 1 is the header, line 2 is the movement that was kept, line 3 is
        // the repeat — and the repeat is the one reported.
        #expect(out.skipped == [3])
    }

    /// `secondary muscle` contains `muscle`; a containment pass that matched
    /// primary first would claim it and never read the real primary column.
    @Test func secondaryDoesNotStealThePrimaryColumn() {
        let csv = "Exercise,Secondary Muscle Group,Primary Muscle Group\nPullover,Triceps,Lats\n"
        let out = ExerciseCSV.parse(csv)
        #expect(out.rows[0].primaryMuscle == "Lats")
        #expect(out.rows[0].secondaryMuscles == ["Triceps"])
    }

    /// A muscle the landmark folder cannot place is DROPPED, never stored raw:
    /// a stored "Serratus" folds to nil at credit time and looks, in the
    /// database, exactly like a muscle that was recorded.
    @Test func unknownMusclesAreDroppedNotStored() {
        let out = ExerciseCSV.parse("name,muscle\nPullover,Serratus\n")
        #expect(out.rows[0].primaryMuscle == nil)
        #expect(out.rows[0].secondaryMuscles.isEmpty)
    }

    @Test func blankLinesAreNotErrors() {
        let out = ExerciseCSV.parse("name\nHip Thrust\n\n\nCalf Raise\n")
        #expect(out.rows.count == 2)
        #expect(out.skipped.isEmpty)
    }

    /// A nameless row IS an error, and it is reported by line so a person can
    /// go and look at it.
    @Test func namelessRowsAreReportedByLine() {
        let out = ExerciseCSV.parse("name,muscle\n,Chest\nHip Thrust,Glutes\n")
        #expect(out.rows.count == 1)
        #expect(out.skipped == [2])
    }

    /// A 5,000-line paste is someone's workout history, not their movement
    /// list.
    @Test func anAbsurdPasteIsTruncatedAndSaysSo() {
        let body = (1...(ExerciseCSV.maxRows + 50)).map { "Movement \($0)" }.joined(separator: "\n")
        let out = ExerciseCSV.parse("name\n" + body)
        #expect(out.rows.count == ExerciseCSV.maxRows)
        // Silence here is the failure: "500 movements" off a five-thousand-line
        // file is a workout history being imported as a catalogue.
        #expect(out.wasTruncated)
        #expect(ExerciseCSV.parse("name\nHip Thrust\n").wasTruncated == false)
    }

    @Test func anEmptyPasteIsEmptyAndNotACrash() {
        #expect(ExerciseCSV.parse("").isEmpty)
        #expect(ExerciseCSV.parse("\n\n  \n").isEmpty)
    }

    /// The primary is not repeated in the secondary list — the credit rule
    /// takes the max of the two, so a duplicate would be silent, but the stored
    /// row would still read as if the movement trained its primary twice.
    @Test func thePrimaryIsNotRepeatedInTheSecondaries() {
        let out = ExerciseCSV.parse("name,primary muscle,secondary muscles\nSquat,Quads,\"Quads, Glutes\"\n")
        #expect(out.rows[0].primaryMuscle == "Quads")
        #expect(out.rows[0].secondaryMuscles == ["Glutes"])
    }

    /// The whole reason the muscle column matters: a movement `MuscleMap` does
    /// not know still earns credit when the file said what it trains.
    @Test func taggedImportsEarnCreditThroughTheStoredFallback() {
        let out = ExerciseCSV.parse("name,primary muscle\nZercher Squat,Quads\n")
        let row = out.rows[0]
        #expect(row.isUnclassified == false)

        let movers = MuscleMap.resolveMovers(
            row.name, stored: [row.primaryMuscle].compactMap { $0 } + row.secondaryMuscles
        )
        let credit = MuscleCredit.weightedSets([
            MuscleCredit.Contribution(physicalSets: 3, movers: movers)
        ])
        #expect(credit[.quads] == 3)
    }

    /// The gap the test above found: this table grew around the founder's deck,
    /// which never wrote the words "Bench Press", so the most common barbell
    /// lift in the world credited nothing until W5.
    @Test func theFlatBenchTrainsAChest() {
        #expect(MuscleMap.movers("Bench Press")?.primary == ["chest"])
        #expect(MuscleMap.movers("Decline Bench Press")?.primary == ["chest"])
        // The four-token entry is more specific and still wins its own spelling.
        #expect(
            MuscleMap.movers("Incline Bench Press (Dumbbell)")?.secondary == ["triceps", "front_delts"]
        )
        // And it did not become a catch-all: a leg press is still a leg press.
        #expect(MuscleMap.movers("Leg Press")?.primary == ["quadriceps"])
    }
}
