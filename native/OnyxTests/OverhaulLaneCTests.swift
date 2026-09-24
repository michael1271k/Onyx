import Foundation
import SwiftUI
import UIKit
import Testing
import OnyxCore
import OnyxData
@testable import Onyx

/// Overhaul Lane C — the two app-side facts OnyxCore cannot check itself.
@Suite("Overhaul lane C")
struct OverhaulLaneCTests {

    /// OnyxCore is Foundation-only, so it holds the glyph names as strings; a
    /// typo there renders NOTHING (an empty `Image`), which no core test sees.
    @Test("every exercise glyph is a symbol this OS ships")
    func glyphsExist() {
        let names = ExerciseGlyph.Pattern.allCases.map(\.symbol) + [ExerciseGlyph.fallback]
        for name in names {
            #expect(UIImage(systemName: name) != nil, "\(name) is not an SF Symbol")
        }
    }

    @Test("a treadmill is labelled Treadmill with its own glyph")
    func treadmillLabel() {
        let kind = CardioKind(CardioImport.treadmill)
        #expect(kind.label == "Treadmill")
        #expect(kind.symbol == "figure.walk.treadmill")
        #expect(UIImage(systemName: kind.symbol) != nil)
        #expect(CardioKind.offered.contains(CardioImport.treadmill))
        #expect(CardioKind(CardioImport.walk).label == "Walk")
    }

    /// `session-hr` photographs the strip from a seeded CACHE row, so the row
    /// has to be one `SessionTelemetry` reads back — or the shot is empty.
    @MainActor
    @Test("the session-hr fixture's heart-rate cache reads back as a cut series")
    func heartRateFixtureReads() async throws {
        let closed = LoggerModel.previewTelemetry(closed: true)
        PreviewCatalogue.seed(closed.store)
        let sessionId = try #require(closed.model.sessionId)
        LoggerPreviews.seedHeartRate(closed.store, sessionId: sessionId)
        let environment = LoggerPreviews.environment(over: closed.store)
        let reading = try #require(await environment.telemetry.reading(sessionId: sessionId))
        #expect(!reading.samples.isEmpty)
        #expect(!reading.segments.isEmpty)
    }

    /// The warm-up card names the athlete's LAST bout — an indoor one is a
    /// treadmill now, so the card says so rather than "Walk".
    @MainActor
    @Test("the warm-up card names an indoor bout Treadmill")
    func warmupNamesTreadmill() throws {
        let user = "00000000-0000-0000-0000-00000000c0c2"
        let database = try AppDatabase.inMemory(deviceId: "lane-c-treadmill")
        try database.seedRows { db in
            try CardioLogRow(
                id: "c-1", userId: user, date: "2026-09-20", kind: CardioImport.treadmill,
                distanceM: 400, durationMin: 5, fromHealthkit: true, hkUuid: "u-1"
            ).insert(db)
        }
        let model = LoggerModel(
            day: PlanTemplates.day("onyx5", "arms"), phase: .bulk,
            store: database, userId: user
        )
        #expect(model.exercises.first?.name == "Treadmill")
    }
}
