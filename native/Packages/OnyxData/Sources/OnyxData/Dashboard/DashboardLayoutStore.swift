import Foundation
import GRDB
import OnyxCore

/// The dashboard arrangement — one `dashboard_layouts` row per user, read live
/// and written through the outbox like every other mirrored row.
///
/// ── THE ROW HOLDS BOTH SURFACES; THE APP OWNS ONE ────────────────────────────
/// `layout` is the v4 payload with a `phone` and a `desktop` side. The phone is
/// the only surface this app has, but the desktop side is still the web's and
/// is carried through unparsed on every write (`Dashboard.serializeLayout`'s
/// `other`), so arranging the phone here never wipes a desktop arrangement made
/// on the web. When Wave 9 retires the web the desktop side simply stops being
/// written by anyone.
public extension AppDatabase {

    /// The stored payload as `JSONSerialization` reads it — `nil` when there is
    /// no row or the text is not JSON. The reader (`Dashboard.fromStored`) treats
    /// both as the defaults.
    func dashboardLayoutStream(userId: String) -> AsyncThrowingStream<StoredDashboardLayout?, any Error> {
        stream(ValueObservation.tracking { db in
            try DashboardLayoutRow.filter(Column("user_id") == userId).fetchOne(db).map(StoredDashboardLayout.init)
        })
    }

    /// Write the phone's arrangement, keeping whatever the other surface holds,
    /// and queue the row.
    func saveDashboardLayout(userId: String, _ layout: DashboardLayout, now: Date = Date()) throws {
        try writer.write { db in
            let existing = try DashboardLayoutRow.filter(Column("user_id") == userId).fetchOne(db)
            let other = existing.map(StoredDashboardLayout.init)?.object
            let payload = Dashboard.serializeLayout(layout, surface: .phone, other: other)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            var row = existing ?? DashboardLayoutRow(userId: userId, layout: JSONText(raw: ""), updatedAt: now)
            row.layout = JSONText(raw: String(decoding: data, as: UTF8.self))
            row.updatedAt = now
            try row.save(db)
            try Self.enqueueRowUpsert(
                table: DashboardLayoutRow.databaseTableName,
                id: try Self.rowID(table: DashboardLayoutRow.databaseTableName, key: ["user_id": userId], in: db),
                in: db
            )
        }
    }

    /// The Train tab's hidden sections, out of the same row (W6).
    ///
    /// A plain read and not a stream, deliberately: the Train tab is ONE
    /// detached pass on appear and on every dismissal (`WorkoutWeek`'s header
    /// states why), so a `ValueObservation` here would be the only live
    /// subscription on a screen built not to have any — and the one thing that
    /// changes this value on THIS device is the menu the user just used, which
    /// writes through `saveTrainLayout` and refreshes.
    func trainLayout(userId: String) -> TrainLayout {
        let row = try? read { db in
            try DashboardLayoutRow.filter(Column("user_id") == userId).fetchOne(db)
        }
        return Dashboard.trainLayout(from: row.map(StoredDashboardLayout.init)?.object)
    }

    /// Write the Train arrangement, keeping BOTH dashboard surfaces, and queue
    /// the row.
    ///
    /// The mirror of `saveDashboardLayout` above, key for key: that one writes
    /// the phone side and carries the desktop and the train keys through; this
    /// one writes the train key and carries both surfaces through. Neither
    /// parses what the other owns.
    func saveTrainLayout(userId: String, _ layout: TrainLayout, now: Date = Date()) throws {
        try writer.write { db in
            let existing = try DashboardLayoutRow.filter(Column("user_id") == userId).fetchOne(db)
            let payload = Dashboard.withTrain(layout, in: existing.map(StoredDashboardLayout.init)?.object)
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            var row = existing ?? DashboardLayoutRow(userId: userId, layout: JSONText(raw: ""), updatedAt: now)
            row.layout = JSONText(raw: String(decoding: data, as: UTF8.self))
            row.updatedAt = now
            try row.save(db)
            try Self.enqueueRowUpsert(
                table: DashboardLayoutRow.databaseTableName,
                id: try Self.rowID(table: DashboardLayoutRow.databaseTableName, key: ["user_id": userId], in: db),
                in: db
            )
        }
    }
}

/// A `dashboard_layouts` row, decoded once. `object` is what
/// `Dashboard.fromStored` and `serializeLayout(other:)` take.
public struct StoredDashboardLayout: Sendable {
    public let raw: String
    public let updatedAt: Date

    public init(_ row: DashboardLayoutRow) {
        raw = row.layout.raw
        updatedAt = row.updatedAt
    }

    /// Not stored as `Any` on the struct — `Any` is not `Sendable`, and decoding
    /// a few hundred bytes of JSON on read is cheaper than teaching the type
    /// system about it.
    public var object: Any? {
        try? JSONSerialization.jsonObject(with: Data(raw.utf8))
    }

    public var layout: DashboardLayout {
        Dashboard.fromStored(object ?? [:], surface: .phone)
    }

    /// The Train tab's sections, off the same decoded object (W6).
    public var train: TrainLayout {
        Dashboard.trainLayout(from: object)
    }
}
