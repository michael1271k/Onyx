import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Export v6 — the ten findings of the coach's second audit, one case each.
//
// Same reasoning as `WeeklyExportOverhaulTests`: the golden fixture compares
// whole documents and every failure in it reads as "the document changed". These
// say which RULE broke.
// ─────────────────────────────────────────────────────────────────────────────

private func build(_ json: String) throws -> String {
    let input = try JSONDecoder().decode(WeeklyExportInput.self, from: Data(json.utf8))
    return WeeklyExport.build(input)
}

private func payload(days: String, sessions: String = "[]", extra: String = "") -> String {
    """
    {
      "weekStart": "2026-09-14", "weekEnd": "2026-09-20", "programLabel": "Onyx",
      "days": \(days), "sessions": \(sessions), "volumeByMuscle": [], "doms": []
      \(extra.isEmpty ? "" : ", " + extra)
    }
    """
}

private func day(_ date: String, _ fields: String = "") -> String {
    """
    {"date": "\(date)", "weekdayLabel": "Thu", "isTrainingDay": true, "nutritionEstimated": false\(fields.isEmpty ? "" : ", " + fields)}
    """
}

@Suite("Weekly export v6 — the second audit")
struct WeeklyExportV6Tests {

    // MARK: - 1 · the current prescription

    @Test("the prescription prints its version, its cap, and the day measured against it")
    func prescriptionAndDeltas() throws {
        let md = try build(payload(days: "[\(day("2026-09-17"))]", sessions: """
        [{"date": "2026-09-17", "label": "Push", "prs": [], "exercises": [
          {"name": "Incline DB Press",
           "prescription": {"sets": 3, "reps": "8–12", "loadKg": 34, "rpeCap": 8,
                            "structure": "STRAIGHT", "leadRule": "ALTERNATE",
                            "effectiveFrom": "2026-09-15", "version": 3, "source": "prescription"},
           "sets": [
             {"weightKg": 36, "reps": 13, "rpe": 9, "failure": false},
             {"weightKg": 36, "reps": 10, "rpe": 8, "failure": false}
           ]}
        ]}]
        """))
        #expect(md.contains("prescribed 3 × 8–12 @ 34 kg cap @8 (v3 from 2026-09-15)"))
        // The best set is 36 × 13 — two kilograms up, one rep past the ceiling.
        #expect(md.contains("vs prescribed load +2.00 kg · reps +1"))
        // S1 was rated 9 against a cap of 8 and is named by its ordinal.
        #expect(md.contains("RPE cap 8 exceeded S1 @9"))
    }

    @Test("the July blueprint says so, and a ladder prints every rung")
    func blueprintAndLadder() throws {
        let md = try build(payload(days: "[\(day("2026-09-17"))]", sessions: """
        [{"date": "2026-09-17", "label": "Push", "prs": [], "exercises": [
          {"name": "Chest Press",
           "prescription": {"sets": 3, "reps": "8–12", "loadKg": 42.5,
                            "structure": "TOPSET_BACKOFF", "setLoads": [42.5, 37.5, 37.5],
                            "source": "prescription", "version": 1, "effectiveFrom": "2026-09-01"},
           "sets": [{"weightKg": 42.5, "reps": 10, "failure": false}]},
          {"name": "Fly",
           "prescription": {"sets": 3, "reps": "12–15", "loadKg": 15, "source": "plan"},
           "sets": [{"weightKg": 15, "reps": 13, "failure": false}]}
        ]}]
        """))
        #expect(md.contains("prescribed 3 × 8–12 @ 42.5/37.5/37.5 kg"))
        #expect(md.contains("(plan)"))
        // The ladder compares against the TOP SET, not an average of it.
        #expect(md.contains("vs prescribed load +0.00 kg · reps in window"))
    }

    // MARK: - 2 · the set-quality tally

    @Test("the session header counts the tagged sets and says which kind")
    func tagTally() throws {
        let md = try build(payload(days: "[\(day("2026-09-17"))]", sessions: """
        [{"date": "2026-09-17", "label": "Pull", "prs": [], "exercises": [
          {"name": "Seated Cable Row (Wide)", "sets": [
            {"weightKg": 42.5, "reps": 11, "rpe": 9, "failure": false, "quality": "momentum"},
            {"weightKg": 42.5, "reps": 10, "rpe": 9, "failure": false, "quality": "momentum"},
            {"weightKg": 42.5, "reps": 9, "failure": false, "quality": "needed_warmup"}
          ]}
        ]}]
        """))
        #expect(md.contains("tagged_sets 3 (momentum 2, cold 1)"))
        // And the token still rides on the set line it belongs to.
        #expect(md.contains("42.5 × 11 @9 momentum"))
    }

    // MARK: - 3 · a start the row cannot prove

    @Test("an imported bout says imported, a keyed one says from, a typed one says typed")
    func cardioProvenance() throws {
        let md = try build(payload(days: "[\(day("2026-09-17"))]", extra: """
        "cardio": [
          {"date": "2026-09-17", "kind": "walking", "durationMin": 32, "distanceM": 3350,
           "startedAt": "2026-09-17T21:11:02+03:00", "source": "import"},
          {"date": "2026-09-17", "kind": "walking", "durationMin": 18, "distanceM": 1900,
           "startedAt": "2026-09-17T07:05:00+03:00", "source": "health"}
        ]
        """))
        #expect(md.contains("imported 21:11"))
        #expect(md.contains("from 07:05"))
        #expect(md.contains("cardio start unprovable on 1 bout"))
    }

    // MARK: - 6 · one movement, one PR line

    @Test("a movement PRd twice in a week is listed once, at its best, and says so")
    func prDedupe() throws {
        let md = try build(payload(days: "[\(day("2026-09-17"))]", sessions: """
        [
         {"date": "2026-09-14", "label": "Push", "exercises": [],
          "prs": [{"name": "Chest Press", "weightKg": 42.5, "reps": 9, "axes": ["weight"]}]},
         {"date": "2026-09-17", "label": "Push", "exercises": [],
          "prs": [{"name": "Chest Press", "weightKg": 42.5, "reps": 12, "axes": ["reps"]}]}
        ]
        """))
        #expect(md.contains("Chest Press 42.5 × 12"))
        #expect(!md.contains("Chest Press 42.5 × 9"))
        #expect(md.contains("(2 sessions)"))
        // The axes are the WINNING record's own — never a union across the week.
        #expect(md.contains("PR reps · (2 sessions)"))
    }

    // MARK: - 7 · a flag carries its evidence

    @Test("a flagged HRV prints the raw value, which window it came from, and when it landed")
    func hrvEvidence() throws {
        let md = try build(payload(days: """
        [\(day("2026-09-17", """
        "hrvMs": 119.8, "hrvFlag": "beyond +22 ms of the 30-night median 60 ms",
        "hrvOvernight": true, "hrvSyncedAt": "2026-09-18T02:41:07+03:00"
        """)),
         \(day("2026-09-18", "\"hrvMs\": 58, \"hrvOvernight\": false"))]
        """))
        #expect(md.contains("raw 119.8 ms"))
        #expect(md.contains("overnight window"))
        #expect(md.contains("synced 2026-09-18 02:41"))
        // Two kinds of reading in one column cannot be averaged, and §7 says so.
        #expect(md.contains("mixed HRV provenance — 1 overnight, 1 calendar-day"))
    }

    // MARK: - 8 · SpO2

    @Test("a reading under 95 % is flagged on the day and named in the anomalies")
    func lowSpo2() throws {
        let md = try build(payload(days: "[\(day("2026-09-17", "\"bloodOxygenPct\": 94"))]"))
        #expect(md.contains("flags SpO2 low"))
        #expect(md.contains("SpO2 94.0 % on 2026-09-17 — below 95 %"))
        // 95 itself is the floor and is not under it.
        let ok = try build(payload(days: "[\(day("2026-09-17", "\"bloodOxygenPct\": 95"))]"))
        #expect(!ok.contains("SpO2 low"))
    }

    // MARK: - 9 · the insomnia tracker

    @Test("a night is named for a long onset, a broken night, or the athlete's own tag")
    func insomnia() throws {
        let md = try build(payload(days: """
        [\(day("2026-09-15", "\"bedTime\": \"2026-09-15T23:40:00+03:00\", \"sleepOnsetMin\": 62, \"awakeMin\": 20, \"sleepMin\": 370")),
         \(day("2026-09-16", "\"awakeMin\": 74, \"sleepMin\": 400")),
         \(day("2026-09-17", "\"sleepOnsetTrouble\": true, \"sleepMin\": 430")),
         \(day("2026-09-18", "\"sleepOnsetMin\": 12, \"awakeMin\": 18, \"sleepMin\": 450"))]
        """, extra: """
        "insomnia": [
          {"date": "2026-08-04", "tag": true}, {"date": "2026-08-19", "tag": true},
          {"date": "2026-09-15", "tag": false}, {"date": "2026-09-16", "tag": false},
          {"date": "2026-09-17", "tag": true}
        ]
        """))
        #expect(md.contains("insomnia nights 3 of 4 · 8w 5"))
        // 23:40 plus a 62-minute latency is 00:42 — past midnight, and wrapped.
        #expect(md.contains("2026-09-15 · onset_local 00:42 · onset 62 m · awake 20 m · duration 6 h 10 m"))
        #expect(md.contains("2026-09-16 · awake 74 m"))
        #expect(md.contains("2026-09-17 · duration 7 h 10 m · trouble falling asleep"))
        // The quiet night is not in the list. (Its DAILY row still prints, so
        // the indent is what distinguishes a tracker row from a day.)
        #expect(!md.contains("\n  2026-09-18 · "))
    }

    // MARK: - 10 · the tape

    @Test("the waist Δ is against the previous WAISTED scan")
    func waistDelta() throws {
        let md = try build(payload(days: "[\(day("2026-09-17"))]", extra: """
        "bodyComp": [
          {"date": "2026-09-15", "weightKg": 84.2, "waistCm": 82.4},
          {"date": "2026-09-16", "weightKg": 84.0},
          {"date": "2026-09-18", "weightKg": 83.8, "waistCm": 81.9}
        ]
        """))
        #expect(md.contains("Waist Δ (cm)"))
        #expect(md.contains("−0.5"))
        #expect(md.contains("waist Δ −0.5 cm"))
    }
}
