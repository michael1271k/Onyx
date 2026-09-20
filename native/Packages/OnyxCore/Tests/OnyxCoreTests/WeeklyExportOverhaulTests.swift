import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// The eight defects the report overhaul closed, each held open by one case.
//
// The golden fixture compares eight whole documents byte for byte, which catches
// a regression but cannot say WHAT rule broke — every failure looks the same and
// reads as "the document changed". These are the rules themselves, each stated
// on the smallest payload that can express it, so a later wave that reintroduces
// one is told which one.
//
// Built from JSON rather than the memberwise initialisers: the payload has
// twenty-six fields and a test that names them positionally breaks the day one
// is inserted, which is the opposite of what a regression test is for.
// ─────────────────────────────────────────────────────────────────────────────

private func build(_ json: String) throws -> String {
    let input = try JSONDecoder().decode(WeeklyExportInput.self, from: Data(json.utf8))
    return WeeklyExport.build(input)
}

/// The shell every case fills in — one day, and whatever `extra` adds.
private func payload(day: String = "{}", sessions: String = "[]", extra: String = "") -> String {
    """
    {
      "weekStart": "2026-09-14", "weekEnd": "2026-09-20", "programLabel": "Onyx",
      "days": [{
        "date": "2026-09-17", "weekdayLabel": "Thu", "isTrainingDay": true,
        "nutritionEstimated": false
        \(day.isEmpty || day == "{}" ? "" : ", " + day.dropFirst().dropLast())
      }],
      "sessions": \(sessions), "volumeByMuscle": [], "doms": []
      \(extra.isEmpty ? "" : ", " + extra)
    }
    """
}

private func session(_ exercises: String) -> String {
    """
    [{"date": "2026-09-17", "label": "Push", "exercises": \(exercises), "prs": []}]
    """
}

@Suite("Weekly export — the overhaul's eight rules")
struct WeeklyExportOverhaulTests {

    // MARK: - §5 · the heading that was not a heading

    @Test("an exercise whose every set is a warm-up prints no heading of its own")
    func theTreadmillDoesNotBleedIntoTheNextMovement() throws {
        let md = try build(payload(sessions: session("""
        [
          {"name": "Treadmill", "sets": [
            {"weightKg": 0, "reps": 0, "failure": false, "warmup": true,
             "durationSec": 300, "distanceKm": 0.37, "inclinePct": 2}
          ]},
          {"name": "Bench Press", "sets": [{"weightKg": 60, "reps": 10, "failure": false}]}
        ]
        """)))
        // The bare bold name that was reading as the next movement's label.
        #expect(!md.contains("**Treadmill**"))
        // It is still in the document — once, where a warm-up belongs.
        #expect(md.contains("warm-ups Treadmill"))
        #expect(md.contains("**Bench Press**"))
        // And a warm-up line does not start with the stripped ordinal's spacing.
        #expect(!md.contains("warm-ups Treadmill  "))
    }

    @Test("an exercise that was opened and never performed still says so")
    func anEmptyMovementKeepsItsHeading() throws {
        let md = try build(payload(sessions: session("""
        [{"name": "Calf Press", "sets": []}]
        """)))
        #expect(md.contains("**Calf Press** — no sets logged"))
    }

    // MARK: - §5 · the quality column

    @Test("a set quality renders inline, including the `+`-joined combinations")
    func qualitiesReachTheSetLine() throws {
        let md = try build(payload(sessions: session("""
        [{"name": "Row", "sets": [
          {"weightKg": 60, "reps": 10, "failure": false, "quality": "needed_warmup"},
          {"weightKg": 60, "reps": 9, "failure": false, "quality": "momentum+cut_short"},
          {"weightKg": 60, "reps": 8, "failure": false, "dropset": true}
        ]}]
        """)))
        // `needed_warmup` is spelled "Cold" by `SetTags`, not "needed warmup".
        #expect(md.contains("S1  60 × 10 cold"))
        // TWO qualities on one set, in the column's canonical order. A bare
        // dictionary lookup returned nil for this and printed nothing at all.
        #expect(md.contains("S2  60 × 9 momentum cut short"))
        #expect(md.contains("S3  60 × 8 drop"))
    }

    // MARK: - §5 · a duration is not a cardio axis

    @Test("a loaded set that was also timed keeps its load, and gains the clock")
    func aTimedLiftIsStillALift() throws {
        let md = try build(payload(sessions: session("""
        [{"name": "Squat", "sets": [
          {"weightKg": 100, "reps": 5, "failure": false, "rpe": 8, "durationSec": 72}
        ]}]
        """)))
        // The whole set: the load, the reps, the rating AND the measured time.
        #expect(md.contains("S1  100 × 5 @8 1:12"))
        // What it used to say, having taken the cardio branch.
        #expect(!md.contains("1:12 km/h"))
    }

    @Test("a treadmill warm-up — no load, no reps — is still a bout")
    func aDurationWithNoLiftUnderItIsCardio() throws {
        let md = try build(payload(sessions: session("""
        [{"name": "Treadmill", "sets": [
          {"weightKg": 0, "reps": 0, "failure": false, "durationSec": 300, "distanceKm": 0.37}
        ]}]
        """)))
        // Speed is derived from the pair and appears nowhere in the payload.
        // A bout's own axes are space-joined: `·` divides the FIELDS of a line
        // and one side of one set is a single field.
        #expect(md.contains("5:00 4.4 km/h 0.37 km"))
    }

    // MARK: - §5 · one plan row, one field

    @Test("`target` is not printed beside a prescription that already states it")
    func theRepWindowIsNotSaidTwice() throws {
        let both = try build(payload(sessions: session("""
        [{"name": "Fly", "repWindow": "12–15", "sets": [{"weightKg": 15, "reps": 13, "failure": false}],
          "prescription": {"sets": 3, "reps": "12–15", "loadKg": 15}}]
        """)))
        #expect(both.contains("prescribed 3 × 12–15 @ 15 kg"))
        #expect(!both.contains("target 12–15"))

        // A movement the plan does not name today keeps the bare window, which
        // `Ceilings.repWindow` found on some OTHER day of the program.
        let windowOnly = try build(payload(sessions: session("""
        [{"name": "Fly", "repWindow": "12–15", "sets": [{"weightKg": 15, "reps": 13, "failure": false}]}]
        """)))
        #expect(windowOnly.contains("**Fly** — target 12–15"))
    }

    @Test("rest reaches the document, planned and measured")
    func restIsPrinted() throws {
        let md = try build(payload(sessions: session("""
        [{"name": "Fly", "restTargetSec": 90, "restActualSec": 104,
          "sets": [{"weightKg": 15, "reps": 13, "failure": false}]}]
        """)))
        #expect(md.contains("rest 90 s · actual rest 104 s"))
    }

    // MARK: - §4 · a powder is food

    @Test("the day's fibre and macros include what the stack delivered")
    func theStackCountsTowardTheDay() throws {
        let md = try build(payload(day: """
        {"calories": 2000, "proteinG": 160, "carbsG": 200, "fatG": 60,
         "nutrientsFood": {"fiber": 19},
         "nutrientsStack": {"kcal": 17, "carbs": 4.4, "fiber": 3.9}}
        """))
        // 19 + 3.9, and 2,000 + 17 — neither figure was reaching this row.
        #expect(md.contains("fiber 23"))
        #expect(md.contains("2,017 kcal"))
        #expect(md.contains("160/204/60"))
        // And the contribution is named, so the total can be split back apart.
        #expect(md.contains("of which stack 17 kcal · 4.4 C · fiber 3.9"))
    }

    // MARK: - §4 · the bout belongs to the day

    @Test("every day states its cardio, including the days that had none")
    func cardioIsADayLevelFact() throws {
        let quiet = try build(payload())
        #expect(quiet.contains("  cardio none"))

        let walked = try build(payload(
            sessions: session("""
            [{"name": "Bench Press", "sets": [{"weightKg": 60, "reps": 10, "failure": false}]}]
            """),
            extra: """
            "cardio": [{"date": "2026-09-17", "kind": "walk", "durationMin": 42, "distanceM": 3600,
                        "kcal": 178, "avgHr": 103, "startedAt": "2026-09-17T08:14:00", "source": "health"}]
            """))
        #expect(walked.contains("  cardio Walk · from 08:14 · 42.0 min · 3.60 km · 178 kcal · avg HR 103"))
        // NOT inside the session block, which is where it used to be filed.
        // Bounded at §6: §8 explains the word and would match forever.
        let sessionBlock = walked
            .components(separatedBy: "## 5 · SESSIONS")[1]
            .components(separatedBy: "## 6 · ")[0]
        #expect(!sessionBlock.contains("cardio"))
    }

    @Test("a manual row's stamp is labelled as the moment it was typed")
    func aTypedBoutDoesNotClaimAStart() throws {
        let md = try build(payload(extra: """
        "cardio": [{"date": "2026-09-17", "kind": "walk", "durationMin": 42,
                    "startedAt": "2026-09-17T21:03:00", "source": "manual"}]
        """))
        #expect(md.contains("typed 21:03"))
        #expect(!md.contains("from 21:03"))
    }

    // MARK: - §3 · the tape

    @Test("the waist has a column, and the headers are the app's own words")
    func theWaistIsInTheTable() throws {
        let md = try build(payload(extra: """
        "bodyComp": [{"date": "2026-09-17", "weightKg": 84.2, "waistCm": 82, "bodyFatPct": 18.4}]
        """))
        #expect(md.contains("Waist (cm)"))
        #expect(md.contains("Body fat (%)"))
        // Padded to the header's width, like every cell in the table.
        #expect(md.contains("| 2026-09-17 |       84.20 |       82.0 |         18.4 |"))
        // The abbreviations that appeared in no screen the athlete has ever seen.
        #expect(!md.contains("| BF% |"))
        #expect(md.contains("waist 82.0 cm"))
    }

    // MARK: - §8

    @Test("the legend is the eighth section and states the scales")
    func theLegendIsLast() throws {
        let md = try build(payload())
        let headings = md.components(separatedBy: "\n").filter { $0.hasPrefix("## ") }
        #expect(headings.last == "## 8 · LEGEND")
        #expect(md.contains("DOMS 0–5"))
    }
}
