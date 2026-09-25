import Foundation
import Testing
@testable import OnyxCore

/// Tonnage on the Hevy basis (Precision Lane C, founder decision Q13):
/// warm-ups out, body weight credited on a 100 % bodyweight movement, a
/// unilateral pair still scored once at its weaker side.
@Suite("Tonnage on the Hevy basis")
struct VolumeBasisTests {

    /// The founder's Thursday Upper B, 2026-09-24, every row as `workout_sets`
    /// holds it (session `c6803c0f`). The walk is a 0 kg warm-up; nothing in
    /// the deck is a bodyweight movement; three rows are L/R pairs.
    static let upperB: [VolumeSet] = [
        VolumeSet(weightKg: 0, reps: 0, setType: "warmup"),                       // Walk, 300 s
        VolumeSet(weightKg: 52, reps: 9), VolumeSet(weightKg: 52, reps: 8),      // Neutral-Grip Lat Pulldown
        VolumeSet(weightKg: 42.5, reps: 11), VolumeSet(weightKg: 42.5, reps: 9), VolumeSet(weightKg: 40, reps: 11), // Chest Press
        VolumeSet(weightKg: 50, reps: 7), VolumeSet(weightKg: 42.5, reps: 12),   // Seated Cable Row (Wide Grip)
        VolumeSet(weightKg: 8.75, reps: 13), VolumeSet(weightKg: 8.75, reps: 12), // Single Arm Cable Crossover
        VolumeSet(weightKg: 5, reps: 16),                                          // Single Arm Lateral Raise
        VolumeSet(weightKg: 5, reps: 15, side: "L", pairId: "64e174c0"), VolumeSet(weightKg: 5, reps: 15, side: "R", pairId: "64e174c0"),
        VolumeSet(weightKg: 5, reps: 15), VolumeSet(weightKg: 5, reps: 14),
        VolumeSet(weightKg: 7.5, reps: 13),                                        // Single Arm Triceps Pushdown
        VolumeSet(weightKg: 7.5, reps: 12, side: "L", pairId: "5d4128fa"), VolumeSet(weightKg: 7.5, reps: 11, side: "R", pairId: "5d4128fa"),
        VolumeSet(weightKg: 6.25, reps: 10, side: "L", pairId: "d4beb6ee"), VolumeSet(weightKg: 6.25, reps: 10, side: "R", pairId: "d4beb6ee"),
        VolumeSet(weightKg: 20, reps: 11), VolumeSet(weightKg: 18.75, reps: 11), VolumeSet(weightKg: 18.75, reps: 10), // Preacher Curl
    ]

    /// The rules move this session by exactly 0: its only warm-up carries no
    /// load and it has no bodyweight movement. 4409.00 is what `workout_sessions
    /// .total_volume_kg` holds; the 36.2 kg gap to Hevy's 4372.8 is NOT a rule
    /// difference (the wave record decomposes it) and no rule reproduces it.
    @Test("the founder's Upper B is 4409.00 on the Hevy basis, body weight known or not")
    func upperBIsUnmoved() {
        #expect(SessionVolume.sessionVolumeKg(Self.upperB) == 4409)
        #expect(SessionVolume.sessionVolumeKg(Self.upperB, bodyWeightKg: 61.2) == 4409)
    }

    @Test("a warm-up is out")
    func warmupExcluded() {
        let sets = [
            VolumeSet(weightKg: 60, reps: 15, setType: "warmup"),
            VolumeSet(weightKg: 100, reps: 10),
        ]
        #expect(SessionVolume.sessionVolumeKg(sets) == 1000)
    }

    @Test("a 100 % bodyweight movement at 0 kg credits body weight × reps")
    func bodyweightCredited() {
        let sets = [VolumeSet(weightKg: 0, reps: 8, bodyweight: true)]
        #expect(SessionVolume.sessionVolumeKg(sets, bodyWeightKg: 61.2) == 489.6)
    }

    @Test("no body weight known, no credit — nil is 0, as today")
    func unknownBodyWeightIsZero() {
        let sets = [VolumeSet(weightKg: 0, reps: 8, bodyweight: true)]
        #expect(SessionVolume.sessionVolumeKg(sets) == 0)
        #expect(SessionVolume.sessionVolumeKg(sets, bodyWeightKg: nil) == 0)
    }

    @Test("a loaded row on a bodyweight movement is scored as logged")
    func loadedBodyweightAsLogged() {
        let sets = [VolumeSet(weightKg: 10, reps: 8, bodyweight: true)]
        #expect(SessionVolume.sessionVolumeKg(sets, bodyWeightKg: 61.2) == 80)
    }

    @Test("a bodyweight warm-up and a bodyweight ghost weigh nothing")
    func bodyweightWarmupAndGhost() {
        let sets = [
            VolumeSet(weightKg: 0, reps: 8, setType: "warmup", bodyweight: true),
            VolumeSet(weightKg: 0, reps: 8, setType: "ghost", bodyweight: true),
        ]
        #expect(SessionVolume.sessionVolumeKg(sets, bodyWeightKg: 61.2) == 0)
    }

    @Test("a bodyweight pair scores once, at the weaker side, at body weight")
    func bodyweightPair() {
        let sets = [
            VolumeSet(weightKg: 0, reps: 10, side: "L", pairId: "p", bodyweight: true),
            VolumeSet(weightKg: 0, reps: 8, side: "R", pairId: "p", bodyweight: true),
        ]
        #expect(SessionVolume.sessionVolumeKg(sets, bodyWeightKg: 60) == 480)
    }

    @Test("a fixture row without the flag decodes as not bodyweight")
    func flagDecodesLeniently() throws {
        let json = #"{"weightKg": 40, "reps": 10}"#.data(using: .utf8)!
        let set = try JSONDecoder().decode(VolumeSet.self, from: json)
        #expect(set.bodyweight == false)
    }
}
