import Foundation
import OnyxCore
import Testing
@testable import OnyxData

/// The Crown's two clocks (overhaul A3): a scrub is one message and one amend,
/// however many rungs it crossed. Real delays, scaled down 10×.
@Suite("Effort scrub")
@MainActor
struct EffortScrubTests {

    @Test("five detents coalesce into one pulse and one amend, carrying the last rung")
    func fiveDetentsAreOneAmend() async throws {
        var pulses: [Double] = []
        var amends: [Double] = []
        let scrub = EffortScrub(pulseDelay: .milliseconds(15), settleDelay: .milliseconds(100),
                                pulse: { pulses.append($0) }, settle: { amends.append($0) })
        for rung in [7.5, 8, 8.5, 9, 9.5] {
            scrub.scrub(rung)
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(250))
        #expect(pulses == [9.5])
        #expect(amends == [9.5], "was one amend per detent before A3")
    }

    @Test("a pause longer than the pulse delay sends a pulse, but the amend still waits for the end")
    func pulsesWhileScrubbingAmendsOnce() async throws {
        var pulses: [Double] = []
        var amends: [Double] = []
        let scrub = EffortScrub(pulseDelay: .milliseconds(15), settleDelay: .milliseconds(100),
                                pulse: { pulses.append($0) }, settle: { amends.append($0) })
        scrub.scrub(8)
        try await Task.sleep(for: .milliseconds(50))
        scrub.scrub(9)
        try await Task.sleep(for: .milliseconds(250))
        #expect(pulses == [8, 9], "the phone follows the Crown")
        #expect(amends == [9])
    }

    @Test("the cover going away settles the rung at once, and only once")
    func flushSettlesOnce() async throws {
        var amends: [Double] = []
        let scrub = EffortScrub(pulseDelay: .milliseconds(15), settleDelay: .milliseconds(100),
                                pulse: { _ in }, settle: { amends.append($0) })
        scrub.flush()
        #expect(amends.isEmpty, "nothing scrubbed is nothing written — unrated stays unrated")
        scrub.scrub(8.5)
        scrub.flush()
        #expect(amends == [8.5])
        try await Task.sleep(for: .milliseconds(200))
        #expect(amends == [8.5], "the idle clock does not write it a second time")
    }

    @Test("an effort pulse from a W0 sender decodes with no set id")
    func effortWithoutSetIdDecodes() throws {
        let old = #"{"band":"hard","exerciseId":"hack-squat","rpe":8.5,"sessionId":"s-1","setIndex":2}"#
        let pulse = try OnyxJSON.decoder.decode(EffortPulse.self, from: Data(old.utf8))
        #expect(pulse.setId == nil)
        let now = EffortPulse(sessionId: "s-1", exerciseId: "hack-squat", setIndex: 2, rpe: 10, setId: "set-9")
        #expect(now.band == .failure)
        #expect(try OnyxJSON.decoder.decode(EffortPulse.self, from: OnyxJSON.encoder.encode(now)) == now)
    }
}
