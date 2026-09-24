import Foundation
import Testing
import OnyxCore
@testable import OnyxData
#if canImport(HealthKit)
import HealthKit
#endif

/// Overhaul C2 — a treadmill is a treadmill, not a walk.
///
/// Health files an indoor walk as `.walking` with `HKMetadataKeyIndoorWorkout`
/// set, and the reader never read the key, so every treadmill bout imported
/// as "walk" and the warm-up card named it "Walk".
@Suite("Treadmill kind")
struct TreadmillKindTests {

    @Test("the vocabulary offers a treadmill, after walk")
    func vocabulary() {
        #expect(CardioImport.treadmill == "treadmill")
        #expect(CardioImport.offered.contains(CardioImport.treadmill))
        #expect(CardioImport.offered.firstIndex(of: CardioImport.walk)! < CardioImport.offered.firstIndex(of: CardioImport.treadmill)!)
    }

    #if canImport(HealthKit)
    @Test("an indoor walk is a treadmill; outdoor or unknown stays a walk")
    func indoorWalkIsTreadmill() {
        #expect(HealthKitReader.cardioKind(.walking, indoor: true) == CardioImport.treadmill)
        #expect(HealthKitReader.cardioKind(.walking, indoor: false) == CardioImport.walk)
        #expect(HealthKitReader.cardioKind(.walking, indoor: nil) == CardioImport.walk)
        // Only a walk moves: an indoor run keeps its own kind.
        #expect(HealthKitReader.cardioKind(.running, indoor: true) == CardioImport.run)
        #expect(HealthKitReader.cardioKind(.cycling, indoor: true) == CardioImport.cycling)
        #expect(HealthKitReader.cardioKind(.yoga, indoor: true) == nil)
    }
    #endif
}
