import Foundation
import GRDB
import OnyxCore

/// The local SQLite store — **the app's only read path**.
///
/// ── THE RULE ────────────────────────────────────────────────────────────────
/// Views read from here and from nowhere else. Nothing in the UI awaits a
/// network call to draw. Sync writes into this store in the background, and
/// `ValueObservation` pushes the change into the views. That is what makes the
/// app instant offline and, more to the point, instant *online* — the "loading"
/// state that a remote-first app spends its life in simply does not exist.
///
/// It is also what replaces roughly 500 lines of the web app: the react-query
/// persister with its 96 KB per-query cap and 1.5 MB budget, the `buster: 'v22'`
/// cache-version string, the JSON-safety walk that strips Maps and Sets before
/// serialising, and the 24 `localStorage` keys. None of that is architecture; it
/// is all working around the browser not having a database.
public final class AppDatabase: Sendable {
    /// Deliberately not `public`.
    ///
    /// A caller holding the writer can insert straight into `workout_sets`. It
    /// compiles, it looks right, and the next append deletes it — `reproject`
    /// rebuilds the table from the log. Exposing it would make the whole
    /// event-sourcing discipline a convention with no enforcement, on the one
    /// property every new target reaches for first. `@testable import` gives
    /// the tests what they need without it.
    let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
        // Rescore at the door (W2): TEMP triggers on the writer connection,
        // outside the migrated schema. See `RescoreDoor`.
        try writer.write { db in try RescoreDoor.install(db) }
    }

    /// A connection that must not migrate — the widget extension's read-only
    /// pool. Only the app owns the schema; an extension that ran the migrator
    /// against a file the app has open would race it on the one thing neither
    /// can recover from.
    init(unmigrated writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// The App Group the app and the widget extension share the file through.
    public static let appGroupID = "group.app.onyx.health"
    static let fileName = "onyx.sqlite"

    /// The defaults suite the app, the widget extension and the watch bridge
    /// all read the theme out of. **Every caller goes through this.**
    ///
    /// ── WHY AN ACCESSOR AND NOT FOUR COPIES OF ONE EXPRESSION ───────────────
    /// Four call sites wrote `UserDefaults(suiteName: appGroupID) ?? .standard`
    /// — the app's `@AppStorage` store, `OnyxWidgets.init`,
    /// `OnyxProvider.theme()` and `AppearanceView.commit`. That fallback is not
    /// a shared suite with a different name: `.standard` is the CALLING
    /// PROCESS's own domain, so under it the app writes the theme to the app's
    /// plist and the extension reads the extension's. The widget never sees the
    /// write at all. It does not fail, it does not log, and it does not look
    /// broken — the tiles simply stay on whatever palette the extension booted
    /// with, which reads as "the theme works on some widgets and not others".
    ///
    /// The fallback stays, because `sharedFolder()` has the same shape: a
    /// free-team build has no App Group entitlement, and a nil suite there must
    /// not cost the APP its own memory of the theme. What changes is that it is
    /// one place, it is named, and it says out loud what it costs.
    ///
    /// ponytail: `.standard` fallback — the widget's palette is stale under it.
    /// Gate 0 (the paid Developer Program, a signed App Group entitlement) is
    /// what removes it; then this can `precondition` on the suite instead.
    public static func appGroupDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            // Reachable only if the suite name collides with the main bundle id
            // or the global domain, which would be a build-configuration
            // mistake rather than a runtime condition. Trapping in DEBUG is
            // right: nothing downstream can be correct after it.
            assertionFailure("UserDefaults(suiteName: \(appGroupID)) is nil — the suite name collides with a reserved domain")
            return .standard
        }
        #if DEBUG
        _ = unsharedContainerWarning
        #endif
        return defaults
    }

    #if DEBUG
    /// The condition that actually bites, said ONCE per process.
    ///
    /// `UserDefaults(suiteName:)` hands back a suite for any name that is not
    /// reserved, so the assertion above can never fire on the bug this exists
    /// for. What decides whether the app and the extension are looking at the
    /// SAME suite is the App Group container, and
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` is the only thing
    /// that answers it.
    ///
    /// A `print` and not an `assert`: the entitlement is unsigned on a free
    /// team (Gate 0 — see `sharedFolder()`), so this is TRUE on every simulator
    /// launch, and a trap would take the screenshot loop down on every run
    /// rather than make the condition visible in it.
    ///
    /// A lazy `static let` is the once-guard: the runtime serialises its
    /// initialiser and runs it exactly once. `Mutex` is not available here —
    /// OnyxData declares `.macOS(.v14)` and Synchronization needs 15.
    private static let unsharedContainerWarning: Void = {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) == nil else { return }
        print("""
            [Onyx] No App Group container for \(appGroupID) — theme defaults fall back to \
            this process's own suite. The app and the widget extension are NOT reading one \
            value, so widget palettes will not follow a theme change. Needs the paid \
            Developer Program and a signed App Group entitlement (Gate 0).
            """)
    }()
    #endif

    public enum OpenError: Error, Equatable {
        /// `readOnly(folderURL:)` found no database — the app has not run yet.
        case missingDatabase(String)
    }

    /// Where the store lives: the App Group container, so the widget extension
    /// can read it, with the app's own Application Support folder as the
    /// fallback when there is no container (a free-team build has no App
    /// Groups).
    ///
    /// ── PURE. IT RESOLVES A PATH AND TOUCHES NOTHING ────────────────────────
    /// This used to perform the legacy-store migration as a side effect, and it
    /// has TWO callers: the app at launch, and `OnyxProvider` in the widget
    /// extension. So a widget refresh — a separate process, scheduled by the
    /// system, with a read-only handle, possibly while the app is mid-write —
    /// could rename the database out from under the app. It never fired in
    /// practice only because the App Group entitlement is unsigned and the
    /// legacy files do not exist; that is luck, not a design.
    ///
    /// The migration now lives in `adoptLegacyStores()`, which the APP calls
    /// once at launch and the widget never calls at all.
    public static func sharedFolder() -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return URL.applicationSupportDirectory.appending(path: "Onyx", directoryHint: .isDirectory) }
        return container.appending(path: "Onyx", directoryHint: .isDirectory)
    }

    /// Relocate the store into the App Group container once there is one.
    /// APP ONLY.
    ///
    /// Call once, at launch, BEFORE opening the store — never from an
    /// extension. The store is moved across with its WAL and SHM: a pool
    /// opened on the sqlite alone would replay a stale checkpoint and the last
    /// unsynced sets would be gone.
    ///
    /// Idempotent. Every step is a "move if the source exists and the
    /// destination does not", so a second call after a successful first is a
    /// series of no-ops. Today it is also a no-op in full: the App Group
    /// entitlement needs the paid Developer Program (Gate 0), `containerURL`
    /// answers nil until it is signed, and every store that exists is the
    /// Application Support fallback.
    ///
    /// ── THE PREDECESSOR'S STORE IS NO LONGER ADOPTED (Expansion W1) ────────
    /// This also renamed a store written under the previous app's container,
    /// folder and file names. That path went with the brand in 7.0.0, and it
    /// could go because it had never fired: its App Group id was not in
    /// `Onyx.entitlements`, so `containerURL` answered nil for it, and its
    /// Application Support half looked for a folder no shipped build ever
    /// wrote. A device that somehow still holds one must install 6.8.1 once
    /// before this release to have it adopted.
    public static func adoptLegacyStores() {
        let appSupport = URL.applicationSupportDirectory.appending(path: "Onyx", directoryHint: .isDirectory)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return }
        moveStoreIfNeeded(from: appSupport, to: container.appending(path: "Onyx", directoryHint: .isDirectory))
    }

    static func moveStoreIfNeeded(from old: URL, to new: URL) {
        move(from: old, named: fileName, to: new, named: fileName)
    }

    /// Move a store and BOTH of its sidecars, or move nothing.
    ///
    /// The `-wal` and `-shm` are not optional extras: a pool opened on the
    /// sqlite file alone replays a stale checkpoint, and the last unsynced sets
    /// are gone. An existing destination is never overwritten — a store already
    /// at the new name is the newer one by definition.
    private static func move(from old: URL, named oldName: String, to new: URL, named newName: String) {
        let fm = FileManager.default
        let oldStore = old.appendingPathComponent(oldName).path
        let newStore = new.appendingPathComponent(newName).path
        guard fm.fileExists(atPath: oldStore), !fm.fileExists(atPath: newStore) else { return }
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] where fm.fileExists(atPath: oldStore + suffix) {
            try? fm.moveItem(atPath: oldStore + suffix, toPath: newStore + suffix)
        }
    }

    /// The on-disk store.
    ///
    /// `.completeUntilFirstUserAuthentication`, not `.completeUnlessOpen`: a
    /// widget timeline is computed while the phone is locked, by a process that
    /// did not have the file open beforehand, so "unless open" would hand the
    /// extension a file it cannot read at exactly the moment it runs. The
    /// database holds training logs, not credentials — the session token lives
    /// in the Keychain and nowhere near this file — so the first unlock after
    /// boot is protection enough.
    public static func onDisk(folderURL: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let url = folderURL.appendingPathComponent(fileName)

        var config = Configuration()
        config.foreignKeysEnabled = true
        #if DEBUG && targetEnvironment(simulator)
        // Every statement, in the console, during development. The single most
        // useful thing when a query returns fewer rows than it should.
        //
        // ── SIMULATOR, NOT `DEBUG` — the same reason `migrator` gives ────────
        // GRDB's `TraceEvent` description is `expandedSQL`: the parameters are
        // substituted in, so this prints every weight, body-fat percentage,
        // sleep figure and the user's UUID, not just the statement text. This
        // project signs with a free Apple team, so the build running on the
        // PHONE is a Debug build — gated on `DEBUG` alone, a real body's
        // measurements go to the device system log and into any sysdiagnose.
        config.prepareDatabase { db in
            db.trace { print("[SQL] \($0)") }
        }
        #endif

        let pool = try DatabasePool(path: url.path, configuration: config)
        #if !os(macOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
        return try AppDatabase(pool)
    }

    /// The widget extension's view of the store: read-only, never migrated,
    /// and absent until the app has run once. Throws `OpenError` for that last
    /// case so the extension can show "open ONYX" rather than an empty tile.
    public static func readOnly(folderURL: URL) throws -> AppDatabase {
        let url = folderURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OpenError.missingDatabase(url.path)
        }
        var config = Configuration()
        config.readonly = true
        config.foreignKeysEnabled = true
        return AppDatabase(unmigrated: try DatabasePool(path: url.path, configuration: config))
    }

    /// Fires after every committed write — an event append, a day edit, a
    /// mirror pull — so the app can ask WidgetKit to reload. Whole database,
    /// not a region: the widgets read nearly every table and the cost of a
    /// spurious reload is one snapshot build. Cancel the return value to stop.
    public func onCommit(_ handler: @escaping @Sendable () -> Void) -> AnyDatabaseCancellable {
        DatabaseRegionObservation(tracking: .fullDatabase)
            .start(in: writer, onError: { _ in }, onChange: { _ in handler() })
    }

    /// The one user this mirror holds. The widget extension has no auth
    /// session, so it asks the store whose data it is — `profiles` first, then
    /// any row that carries a `user_id`.
    public func knownUserId() throws -> String? {
        try writer.read { db in try Self.knownUserId(db) }
    }

    /// The same question inside a transaction. EVERY table that carries a
    /// `user_id` is asked, off `sqlite_master` rather than a list: the
    /// account-switch erase (`prepareForUser`) hangs off this answer, and a
    /// store holding nothing but one half-synced session must still say
    /// whose it is. `profiles` and `user_goals` go first because they are the
    /// rows a sign-in writes before anything else.
    static func knownUserId(_ db: Database) throws -> String? {
        for table in try userTables(db) {
            if let id = try String.fetchOne(db, sql: "SELECT user_id FROM \"\(table)\" LIMIT 1") { return id }
        }
        return nil
    }

    /// Every table with a `user_id` column, read off the schema so the list
    /// cannot go stale — the same rule `eraseLocalData` follows.
    static func userTables(_ db: Database) throws -> [String] {
        let names = try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> 'grdb_migrations'
            ORDER BY CASE name WHEN 'profiles' THEN 0 WHEN 'user_goals' THEN 1 ELSE 2 END, name
            """)
        return try names.filter { name in try db.columns(in: name).contains { $0.name == "user_id" } }
    }

    /// An in-memory store, for tests.
    ///
    /// `deviceId` is injectable so a test can play two devices against each
    /// other with a predictable fold tiebreak. In the app it is always nil and
    /// the store generates one on first use.
    public static func inMemory(deviceId: String? = nil) throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let db = try AppDatabase(DatabaseQueue(configuration: config))
        if let deviceId {
            try db.writer.write { conn in
                try conn.execute(
                    sql: "INSERT INTO device_state (row_id, device_id, lamport) VALUES ('local', ?, 0)",
                    arguments: [deviceId]
                )
            }
        }
        return db
    }

    // MARK: - Migrations

    /// ── MIGRATIONS ARE APPEND-ONLY, ALWAYS ──────────────────────────────────
    /// Never edit a registered migration; add another. An edited migration runs
    /// on a fresh install and not on yours, so the two diverge silently and the
    /// only symptom is a query that works on one device.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG && targetEnvironment(simulator)
        // In the simulator a schema change wipes and rebuilds rather than
        // requiring a new migration for every experiment.
        //
        // ── SIMULATOR, NOT `DEBUG` ──────────────────────────────────────────
        // This project signs with a free Apple team, so the build running on
        // the phone IS a Debug build. Gated on `DEBUG` alone, adding a column
        // would wipe SQLite on the device — including the `outbox`, whose own
        // doc comment says finishing a workout is the one action that must
        // never be lost. It would take every unsynced set with it, silently.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1.logger") { db in
            try db.create(table: "exercises") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("primary_muscle", .text)
                t.column("secondary_muscles", .text)
                t.column("equipment", .text)
                t.column("is_unilateral", .boolean)
                t.column("is_bodyweight", .boolean)
            }

            try db.create(table: "workout_sessions") { t in
                t.primaryKey("id", .text)
                t.column("user_id", .text).notNull()
                t.column("day_key", .text)
                t.column("date", .text).notNull().indexed()
                t.column("started_at", .datetime)
                t.column("ended_at", .datetime)
                t.column("duration_min", .double)
                t.column("session_rpe", .double)
                t.column("notes", .text)
                t.column("is_pending_sync", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "workout_sets") { t in
                t.primaryKey("id", .text)
                // Spelled out rather than `belongsTo`, which derives a camelCase
                // `sessionId` column. Every column here must match the Postgres
                // name exactly — see `columnNamesMatchPostgres` in the tests.
                t.column("session_id", .text).notNull()
                    .references("workout_sessions", onDelete: .cascade)
                t.column("exercise_id", .text).notNull()
                    .references("exercises", onDelete: .restrict)
                t.column("set_index", .integer).notNull()
                // NOT NULL with no default: a set without a load is 0 kg, which
                // is a real bodyweight set. A NULL here would mean "unknown",
                // and nothing in the domain knows what to do with that.
                t.column("weight_kg", .double).notNull()
                t.column("reps", .integer).notNull()
                t.column("set_type", .text).notNull().defaults(to: "normal")
                t.column("side", .text)
                t.column("pair_id", .text)
                t.column("est_1rm_kg", .double)
                t.column("is_pending_sync", .boolean).notNull().defaults(to: false)
            }
            try db.create(
                index: "idx_sets_session_order",
                on: "workout_sets",
                columns: ["session_id", "set_index"]
            )

            try db.create(table: "outbox") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("payload", .blob).notNull()
                // The whole point of the queue: a retry must not double-apply.
                t.column("idempotency_key", .text).notNull().unique()
                t.column("created_at", .datetime).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("last_error", .text)
                t.column("status", .text).notNull().defaults(to: "pending")
            }
            try db.create(
                index: "idx_outbox_ready",
                on: "outbox",
                columns: ["status", "created_at"]
            )
        }

        // ── v2 ──────────────────────────────────────────────────────────────
        // Sets stop being rows you edit and become a log you append to. See
        // `SetEvent` for why: two devices editing one live session cannot both
        // UPDATE a row without one of the writes vanishing silently.
        //
        // `workout_sets` survives untouched, but its meaning changes: from here
        // on it is a **projection** of `set_events`, rebuilt by the fold inside
        // the same transaction as every append. Views keep reading it, so the
        // `ValueObservation` in `observeSets` needs no change at all.
        migrator.registerMigration("v2.setEvents") { db in
            try db.create(table: "set_events") { t in
                t.primaryKey("id", .text)
                t.column("session_id", .text).notNull()
                    .references("workout_sessions", onDelete: .cascade)
                // NOT a foreign key to `workout_sets`. The event log is the
                // source of truth and the sets table is derived from it, so the
                // dependency runs the other way — and an amend may legitimately
                // arrive before the append that creates the row it names.
                t.column("set_id", .text).notNull()
                t.column("device_id", .text).notNull()
                // The Lamport value. Indexed with device_id because that pair is
                // exactly the sort key the fold uses.
                t.column("seq", .integer).notNull()
                t.column("kind", .text).notNull()
                t.column("body", .blob).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("is_synced", .boolean).notNull().defaults(to: false)
            }
            try db.create(
                index: "idx_events_session_order",
                on: "set_events",
                columns: ["session_id", "seq", "device_id"]
            )
            try db.create(
                index: "idx_events_set",
                on: "set_events",
                columns: ["set_id"]
            )

            // One row, always. This device's identity and its logical clock.
            //
            // The clock lives in the database rather than in memory because it
            // must survive the app being killed: a counter that resets to zero
            // on relaunch would stamp new events *below* ones already written
            // and reorder the session under the user.
            try db.create(table: "device_state") { t in
                t.primaryKey("row_id", .text)
                t.column("device_id", .text).notNull()
                t.column("lamport", .integer).notNull().defaults(to: 0)
            }
        }

        // ── v3 ──────────────────────────────────────────────────────────────
        // The pencil: which device is currently the writer for a live session.
        // See `LiveSessionOwner` — this is a user-experience mechanism, not a
        // correctness one. The log already tolerates two writers; this stops the
        // phone and the watch from both offering a keyboard for the same set.
        migrator.registerMigration("v3.livePencil") { db in
            try db.create(table: "live_sessions") { t in
                t.primaryKey("session_id", .text)
                    .references("workout_sessions", onDelete: .cascade)
                t.column("owner_device_id", .text).notNull()
                t.column("owner_since", .datetime).notNull()
                // Lamport-stamped from the same clock as the events, so a
                // contested claim resolves by the same total order the fold uses.
                t.column("claim_seq", .integer).notNull()
            }
        }

        // ── v4 ──────────────────────────────────────────────────────────────
        // Three corrections, all found by review before any real data existed.
        migrator.registerMigration("v4.projectionCannotVetoTheLog") { db in
            // (a) `workout_sets.exercise_id` had a foreign key to `exercises`.
            //     That let a DERIVED table reject a fact: a set logged on the
            //     watch against an exercise this device has not synced would
            //     fail the projection insert, roll back the transaction, and
            //     take the whole ingest batch with it. The log is the source of
            //     truth and nothing downstream of it may refuse it.
            //
            // (b) `fold_order` carries the fold's arrival tiebreak. Without it
            //     `ORDER BY set_index` relied on rowid order matching insertion
            //     order — true today, but unspecified, and the one case the
            //     fold deliberately allows (two devices claiming the same
            //     set_index) is exactly where it would diverge between phone
            //     and watch.
            try db.create(table: "workout_sets_new") { t in
                t.primaryKey("id", .text)
                t.column("session_id", .text).notNull()
                    .references("workout_sessions", onDelete: .cascade)
                t.column("exercise_id", .text).notNull()
                t.column("set_index", .integer).notNull()
                t.column("weight_kg", .double).notNull()
                t.column("reps", .integer).notNull()
                t.column("set_type", .text).notNull().defaults(to: "normal")
                t.column("side", .text)
                t.column("pair_id", .text)
                t.column("est_1rm_kg", .double)
                t.column("is_pending_sync", .boolean).notNull().defaults(to: false)
                t.column("fold_order", .integer).notNull().defaults(to: 0)
            }
            try db.execute(sql: """
                INSERT INTO workout_sets_new
                    (id, session_id, exercise_id, set_index, weight_kg, reps,
                     set_type, side, pair_id, est_1rm_kg, is_pending_sync, fold_order)
                SELECT id, session_id, exercise_id, set_index, weight_kg, reps,
                       set_type, side, pair_id, est_1rm_kg, is_pending_sync, 0
                FROM workout_sets
                """)
            try db.drop(table: "workout_sets")
            try db.rename(table: "workout_sets_new", to: "workout_sets")
            try db.create(
                index: "idx_sets_session_order",
                on: "workout_sets",
                columns: ["session_id", "set_index", "fold_order"]
            )

            // (c) `idx_events_set` indexed `set_id` alone and no query used it —
            //     write cost on every append for nothing.
            try db.drop(index: "idx_events_set")
        }

        // ── v5 ──────────────────────────────────────────────────────────────
        // A claim now records whether it was a deliberate takeover or the
        // implicit one that happens when a device starts logging. Without the
        // distinction, `ingestOwnership` applied any superseding claim — so a
        // watch whose Lamport clock had run ahead could silently take the
        // pencil off a phone mid-set, purely by starting to log while out of
        // range. See `LiveSessionOwner.ingestOwnership`.
        migrator.registerMigration("v5.explicitTakeover") { db in
            try db.alter(table: "live_sessions") { t in
                t.add(column: "is_takeover", .boolean).notNull().defaults(to: false)
            }
        }

        // ── v6 ── The Nutrition screen's read cache.
        //
        // Two tables that hold NOTHING this device produced. Every field arrives
        // from Postgres and Postgres stays the source of truth for all of it, so
        // both can be dropped and refetched without losing a fact. They are in
        // the same database as `set_events` only because a screen that reads
        // from two stores has two places to be stale.
        //
        // Note what is absent: no `is_pending_sync`, no outbox kind, no write
        // path at all. A read cache that can be written locally is a write path
        // with no conflict rule, which is the thing the event log exists to
        // avoid. Editing a macro is a Wave 3 item and it will go through the
        // same append-only route the logger does.
        migrator.registerMigration("v6.nutritionReadCache") { db in
            try db.create(table: "nutrition_days") { t in
                // The logical day, `yyyy-MM-dd`. Text, like every other date in
                // this store — SQLite has no date type, and a string that sorts
                // correctly is worth more here than an epoch nobody can read in
                // a query.
                t.primaryKey("date", .text)
                // Every macro is nullable. Nil is "never tracked", which is not
                // zero: a day with no intake recorded says nothing about
                // adherence, and defaulting it to 0 would grade an untracked
                // day as a perfect deficit.
                t.column("calories", .double)
                t.column("protein_g", .double)
                t.column("carbs_g", .double)
                t.column("fat_g", .double)
                t.column("phase", .text)
                t.column("steps", .double)
                t.column("active_cal", .double)
                t.column("water_ml", .double)
                t.column("nutrition_exception", .text)
                // NOT NULL with a default, matching Postgres, where this column
                // is `boolean NOT NULL`. The flag is a statement about
                // confidence and "unknown" is not one of its values.
                t.column("nutrition_estimated", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "user_goals") { t in
                t.primaryKey("user_id", .text)
                // All nullable, as in Postgres. A missing calorie goal renders
                // the bar ungraded rather than graded against a guess — see the
                // `1955` incident in `useNutritionGoals`, where local state
                // seeded with a literal nobody chose was worse than no goal.
                t.column("calorie_goal", .integer)
                t.column("protein_goal_g", .integer)
                t.column("carbs_goal_g", .integer)
                t.column("fat_goal_g", .integer)
                t.column("water_goal_ml", .integer)
                t.column("steps_goal", .integer)
                t.column("goal_preset", .text)
            }
        }

        // ── v7 ── RPE lands in the projection.
        //
        // `workout_sets.rpe` has existed in Postgres since the beginning and
        // was simply never carried locally — the logger could store how heavy
        // a set was and not how hard it felt, which is half of the double
        // progression rule ("all work sets at the ceiling at RPE <= 8.5").
        //
        // Nullable, with no default. An unrated set must stay distinguishable
        // from a set rated zero; defaulting it would grade an untracked session
        // as effortless, which is the same class of mistake as defaulting a
        // missing calorie goal.
        //
        // `SetSnapshot` gains the field at the same time. That is a wire-format
        // change and it is a SAFE one in this direction only: a new build
        // decoding an old row sees the key absent and gets `nil`, which is the
        // correct answer for a set logged before ratings were stored. An old
        // build decoding a new row ignores the key. Neither loses a set.
        migrator.registerMigration("v7.setRpe") { db in
            try db.alter(table: "workout_sets") { t in
                t.add(column: "rpe", .double)
            }
        }

        // ── v8 ── The queue learns to wait.
        //
        // `outboxFailed` recorded `attempts` and `last_error` and nothing ever
        // read them, so a write the server will never accept — a CHECK
        // violation, an exercise that cannot be resolved — was retried at full
        // speed on every single drain, forever. On a phone that is radio time
        // and battery spent to earn the same 400.
        //
        // A timestamp rather than a counter-and-a-formula-at-read-time: the
        // drain query has to be able to skip an item with an index-friendly
        // comparison, and "when may this be tried again" is a fact about the
        // row, not something every reader should re-derive. NULL means "now" —
        // which is what every row queued before this migration means, and what
        // a fresh append means.
        migrator.registerMigration("v8.outboxBackoff") { db in
            try db.alter(table: "outbox") { t in
                t.add(column: "next_attempt_at", .datetime)
            }
        }

        // ── v9 ── The mirror. Twenty-six tables, generated, plus its cursors.
        //
        // ── AND THE TWO IT REPLACES ─────────────────────────────────────────
        // `v6.nutritionReadCache` created `nutrition_days` and `user_goals` for
        // one screen: a hand-joined view of three server tables, filled by four
        // hand-written queries in `NutritionSync`. The mirror pulls all three of
        // those tables — plus the other twenty-three — from a generated
        // catalogue, so keeping v6's pair would mean two pull paths writing
        // overlapping facts, and one of them would go stale the first time
        // nobody noticed.
        //
        // `user_goals` in particular COLLIDES: the mirror's version of that
        // table is the real one, all thirty-one columns of it, keyed on `id`
        // rather than on `user_id`. Only one of the two can exist.
        //
        // Dropping them loses nothing. Neither table ever held a fact this
        // device produced — v6's own comment says so — and both are refetched
        // on the first refresh.
        migrator.registerMigration("v9.mirror") { db in
            try db.drop(table: "nutrition_days")
            try db.drop(table: "user_goals")

            try Self.migrateMirrorV1(db)

            // How far each table has been pulled. One row per table, written
            // only by `setMirrorCursor`, which moves it forward and never back.
            try db.create(table: "sync_cursors") { t in
                t.primaryKey("table_name", .text)
                t.column("cursor_at", .datetime).notNull()
                t.column("pulled_at", .datetime).notNull()
            }
        }

        // When each table last synced, append-only. `sync_cursors` answers "how
        // far", this answers "when" — and keeps every answer, so the Settings
        // Sync Status section can show a history and a first-launch backfill
        // can be recognised by the table being empty for a user.
        migrator.registerMigration("v10.syncStatus") { db in
            try db.create(table: "sync_status") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("user_id", .text).notNull()
                t.column("table_name", .text).notNull()
                t.column("synced_at", .datetime).notNull()
                t.column("reason", .text).notNull()
                t.column("rows", .integer).notNull()
            }
            try db.create(index: "sync_status_user_table", on: "sync_status", columns: ["user_id", "table_name", "synced_at"])
        }

        // The four server columns the session wire row never carried. Measured
        // from an `HKWorkout` overlapping the session, or estimated (and
        // stamped as such) when there is none — see `SessionMetrics`. Nullable
        // like the server's; the two flags default false like the server's.
        migrator.registerMigration("v11.sessionMetrics") { db in
            try db.alter(table: "workout_sessions") { t in
                t.add(column: "avg_bpm", .integer)
                t.add(column: "calories_burned", .integer)
                t.add(column: "avg_bpm_estimated", .boolean).notNull().defaults(to: false)
                t.add(column: "calories_estimated", .boolean).notNull().defaults(to: false)
            }
        }

        // Every `user_id` in the store, spelled the way Postgres spells it.
        //
        // ── WHAT WAS IN THE STORE ───────────────────────────────────────────
        // `AppEnvironment.userIdString` returned `UUID.uuidString`, which is
        // uppercase; a Postgres `uuid` column renders lowercase. So a row this
        // device WROTE and the same row PULLED BACK carried different
        // `user_id` bytes, and SQLite compares TEXT byte for byte with no
        // collation on any of these columns. `Column("user_id") == userId`
        // therefore matched the handful of rows typed on this phone and none
        // of the hundreds synced to it. Six symptoms, one cause — see
        // `OnyxJSON.canonicalUserID`.
        //
        // ── WHY DUPLICATES EXIST, AND ONLY IN SOME TABLES ───────────────────
        // A table keyed on `id` never doubled: the pull found the row by its
        // uuid and rewrote `user_id` in place. A table the device upserts by a
        // NATURAL key did: the lookup missed the pulled row, so the write
        // minted a second one under a fresh uuid, and now both spellings sit
        // there. `MirrorCatalogue.conflict` is that natural key — introspected
        // from the server's unique indexes, not guessed — so the collapse can
        // be driven off the catalogue instead of a hand list that would fall
        // behind the schema.
        //
        // ── WHICH TWIN SURVIVES ─────────────────────────────────────────────
        // The lowercase one, always, and not because it is newer. It is a
        // verbatim copy of a server row, and `sync_cursors` has already moved
        // past it: delete it and it does not come back until its `updated_at`
        // changes, which is permanent loss. The uppercase twin's content was
        // pushed to that same server row through the same conflict target, so
        // it is either already inside the survivor or still in the outbox and
        // about to be — nothing is lost, at worst something is late. Today's
        // score is the visible case, and `DailyScoreStore` recomputes it on
        // the next tick regardless.
        // Reads `MirrorCatalogue.conflict` LIVE, so a later schema change moves
        // this migration: `stress_logs` went from `(user_id, date, slot)` to `id`
        // in W1, and a store still below v12 no longer twin-merges that table.
        migrator.registerMigration("v12.lowercaseUserIds") { db in
            let naturalKeys = Dictionary(
                uniqueKeysWithValues: MirrorCatalogue.tables.map { ($0.name, $0.conflict.split(separator: ",").map(String.init)) }
            )
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                 WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
                 ORDER BY name
                """)
            for table in tables {
                guard try db.columns(in: table).contains(where: { $0.name == "user_id" }) else { continue }
                let name = table.quotedDatabaseIdentifier

                if let key = naturalKeys[table], key.contains("user_id") {
                    // `IS` rather than `=` so a NULL key column matches a NULL
                    // one; every column here is NOT NULL today, and a
                    // regenerated catalogue may not be.
                    let rest = key.filter { $0 != "user_id" }
                        .map { "twin.\($0.quotedDatabaseIdentifier) IS \(name).\($0.quotedDatabaseIdentifier)" }
                    let match = (["twin.user_id = lower(\(name).user_id)"] + rest).joined(separator: " AND ")
                    try db.execute(sql: """
                        DELETE FROM \(name)
                         WHERE user_id <> lower(user_id)
                           AND EXISTS (SELECT 1 FROM \(name) AS twin WHERE \(match))
                        """)
                }

                try db.execute(sql: "UPDATE \(name) SET user_id = lower(user_id) WHERE user_id <> lower(user_id)")
            }
        }

        // The stack can be edited on the phone now, and an item that leaves it
        // is ARCHIVED rather than deleted — see `SupplementEditing`. A fresh
        // install gets the column from the regenerated mirror DDL at v9, so the
        // guard is what stops this failing on a store that never needed it.
        migrator.registerMigration("v13.supplementArchive") { db in
            guard try !db.columns(in: "custom_supplements").contains(where: { $0.name == "archived_at" }) else { return }
            try db.alter(table: "custom_supplements") { t in
                t.add(column: "archived_at", .datetime)
            }
        }

        // ── v14 ─────────────────────────────────────────────────────────────
        // How a set went, as opposed to how hard it was.
        //
        // Postgres has carried `workout_sets.quality` all along, with a CHECK
        // constraint holding the same six keys `SetQuality` lists; the local
        // store did not, so the logger's set-options sheet had nowhere to put
        // the answer. Exactly the shape of `v7.setRpe`, and safe for the same
        // reason: `SetSnapshot` gains the field at the same time, a new build
        // decoding an old event sees the key absent and gets `nil` — which is
        // the correct reading of a set logged before the question was asked —
        // and an old build decoding a new event ignores it. Neither loses a set.
        //
        // `nil` is not a value here. It means the question was never put, which
        // is why there is no "Clean" chip in the sheet: clean is the absence of
        // a claim, and a chip for it would write an assertion that the set was
        // inspected and passed.
        migrator.registerMigration("v14.setQuality") { db in
            guard try !db.columns(in: "workout_sets").contains(where: { $0.name == "quality" }) else { return }
            try db.alter(table: "workout_sets") { t in
                t.add(column: "quality", .text)
            }
        }

        // ── v15 ─────────────────────────────────────────────────────────────
        // The session's own aggregates, and the flag that says a human set the
        // duration.
        //
        // ── WHY THE THREE AGGREGATES COME LOCAL NOW ─────────────────────────
        // `SyncEngine` has left `total_volume_kg`, `set_count` and `pr_count`
        // NULL since Wave 3, on the honest grounds that `sessionVolumeKg`,
        // `countCommittedSets` and `prEngine` were not ported. All three are
        // ported now (`SessionVolume`, `Draft.totals`, `PrEngine`), and E1 is
        // the wave that makes it matter: editing a set on a CLOSED session
        // changes the tonnage, and a phone that rewrites the sets without
        // rewriting the total leaves the web reading a figure for a workout
        // that no longer exists. They are still nullable and still absent on a
        // session nothing has computed for — `nil` is not `0` here either.
        //
        // ── AND WHY `duration_edited` IS LOCAL-ONLY ─────────────────────────
        // Postgres has no such column and does not need one: it is not a fact
        // about the workout, it is a fact about who last wrote a number, and
        // the only reader is `closeSession` on this device deciding whether it
        // may re-derive `duration_min`. Same rule as `workout_sets.fold_order`
        // — derived local state, never sent. Inventing a server column for it
        // would put a value in the schema no other reader knows how to use.
        migrator.registerMigration("v15.sessionTotals") { db in
            let existing = Set(try db.columns(in: "workout_sessions").map(\.name))
            try db.alter(table: "workout_sessions") { t in
                if !existing.contains("total_volume_kg") { t.add(column: "total_volume_kg", .double) }
                if !existing.contains("set_count") { t.add(column: "set_count", .integer) }
                if !existing.contains("pr_count") { t.add(column: "pr_count", .integer) }
                if !existing.contains("duration_edited") {
                    t.add(column: "duration_edited", .boolean).notNull().defaults(to: false)
                }
            }
        }

        // ── v16 ─────────────────────────────────────────────────────────────
        // Which movement came first.
        //
        // `SyncTranslation` left `exercise_order` out of the upload since Wave
        // 3 on the honest grounds that "the local store does not track it", and
        // that was true: every session logged on this phone carries a NULL in
        // that column server-side, while every web-logged one is populated. The
        // reader that suffers is the session report, which orders by
        // `exercise_order` before `set_number` — so a phone workout comes back
        // in whatever order `set_number` happens to imply, and a reorder gesture
        // had nowhere to write.
        //
        // NULLABLE, and backfilled to nothing. A default of 0 would say every
        // historical movement opened its workout; a null says what is actually
        // known about them, which is nothing, and every reader on both sides
        // already handles it (`useSessionDetail` reads `?? 999`).
        //
        // The projection is NOT rebuilt here. `workout_sets` is a fold over
        // `set_events`, and the events that predate this migration carry no
        // order either — a `reprojectAll` would rewrite every row in the store
        // to put the same nulls back.
        migrator.registerMigration("v16.exerciseOrder") { db in
            guard try !db.columns(in: "workout_sets").contains(where: { $0.name == "exercise_order" })
            else { return }
            try db.alter(table: "workout_sets") { t in
                t.add(column: "exercise_order", .integer)
            }
        }

        // ── A SESSION REPAIRED ON THE SERVER CANNOT OTHERWISE REACH A DEVICE ─
        // `TrainingPuller.applyPulledSets` refuses any session that has local
        // `set_events`, and it is right to: those sets are a FOLD over the
        // events, so pulled rows would be deleted by the very next append and
        // the two would disagree in between. The guard has no exception, which
        // makes it a permanent block for a session repaired out of band.
        //
        // 2026-09-07 is that session. Sixteen of its twenty-one weighted sets
        // had survived the tombstoned-`storeId` void bug, `exercise_order` was
        // null on every row and the three aggregates were never written; the
        // server now holds all of it, plus the treadmill set. Without this the
        // device that logged it folds its truncated log forever AND pushes it
        // back over the repair on the next edit — the repair would lose.
        //
        // So the local fold for these ids is dropped: the events, the
        // projection, and anything queued that names them. The next pull then
        // sees a session with no events and adopts the server copy wholesale,
        // which is exactly the path a web-logged session already takes.
        //
        // ── AND THE CURSOR GOES WITH THEM ───────────────────────────────────
        // `pullTraining` asks for sessions `since` the stored cursor. The
        // repair's `updated_at` is already behind a device that has synced
        // since, so clearing the rows alone would leave them cleared and never
        // refilled — strictly worse than the stale fold. Dropping the cursor
        // costs one full training pull, once.
        migrator.registerMigration("v17.adoptRepairedSessions") { db in
            let repaired = ["b6a936a8-c730-413e-8c27-14575b093983"]
            for id in repaired {
                try db.execute(sql: "DELETE FROM set_events WHERE session_id = ?", arguments: [id])
                try db.execute(sql: "DELETE FROM workout_sets WHERE session_id = ?", arguments: [id])
                // The outbox keys nothing by session — the id lives inside the
                // JSON payload — so this matches on the payload itself. A
                // queued commit naming a repaired session is precisely the
                // write that would undo the repair.
                try db.execute(
                    sql: "DELETE FROM outbox WHERE instr(CAST(payload AS TEXT), ?) > 0",
                    arguments: [id]
                )
            }
            try db.execute(
                sql: "DELETE FROM sync_cursors WHERE table_name IN ('workout_sessions', 'workout_sets')"
            )
        }

        // ── v18 ─────────────────────────────────────────────────────────────
        // A set that is not reps and kilograms.
        //
        // `hotfix-polish.sql (git history)` gave Postgres `duration_sec`, `incline`
        // and `distance_km` on 2026-09-07 and wrote the first row that uses
        // them — the treadmill that opens that session, five minutes at incline
        // 2 for 0.37 km, carrying no load at all. None of it could reach this
        // device: the local table has two columns for a set's content and the
        // report renders them as `0kg × 0`, which states a load that does not
        // exist and hides the only three numbers the set has.
        //
        // Exactly the shape of `v14.setQuality` and `v16.exerciseOrder`, and
        // safe for the same reason: three NULLABLE columns, backfilled to
        // nothing, on a table every reader already treats nulls in. There is no
        // default to choose — a `duration_sec` of 0 would claim a set took no
        // time, which is a claim about all 2,190 historical rows at once.
        //
        // No new `SetEvent.Kind` goes with this. `Body.init(from:)` switches on
        // the kind with no fallback, so a kind is a one-way door; the axes ride
        // as OPTIONAL keys on the existing `.append` payload instead, which is
        // what `v7.setRpe` and `v16.exerciseOrder` both did.
        //
        // The projection is NOT rebuilt. `workout_sets` is a fold over
        // `set_events` and no event that predates this carries the axes, so a
        // `reprojectAll` would rewrite every row to put the same nulls back.
        // The one session that HAS them has no local events at all — `v17`
        // dropped them so the server copy could be adopted whole.
        migrator.registerMigration("v18.cardioSetFields") { db in
            let existing = Set(try db.columns(in: "workout_sets").map(\.name))
            guard !existing.isSuperset(of: ["duration_sec", "incline", "distance_km"]) else { return }
            try db.alter(table: "workout_sets") { t in
                if !existing.contains("duration_sec") { t.add(column: "duration_sec", .integer) }
                if !existing.contains("incline") { t.add(column: "incline", .double) }
                if !existing.contains("distance_km") { t.add(column: "distance_km", .double) }
            }
        }

        // ── v19 ─────────────────────────────────────────────────────────────
        // The fourth cardio axis: total ascent, in metres.
        //
        // `cardio-elevation.sql (git history)` is the Postgres half and the founder
        // runs it by hand, so until they do a null is not a gap — it is every
        // row. This column exists first precisely so that the day the server
        // grows it, the value has somewhere to land on the way down.
        //
        // ── AND IT IS STORED, NOT COMPUTED ──────────────────────────────────
        // `incline` × `distance_km` is the same number only while the incline
        // never moved. A real bout walks 2 %, then 4 %, then flat, and
        // `incline` keeps whichever reading the machine last showed — so the
        // product is a guess about the middle of the walk. The treadmill (and
        // HealthKit's `.elevationAscended`) measures the ascent directly.
        //
        // Same shape as `v18` one migration up, and safe for the same reason:
        // ONE nullable column, backfilled to nothing, on a table every reader
        // already treats nulls in. No default — a `0` would claim 2,190
        // historical rows were walked on the flat, which is a claim about sets
        // that were not walked at all.
        //
        // Guarded and never edited in place: `v18` is shipped, and a migration
        // that changes after a device has run it is a migration that device
        // will never run again.
        migrator.registerMigration("v19.cardioElevation") { db in
            let existing = Set(try db.columns(in: "workout_sets").map(\.name))
            guard !existing.contains("elevation_m") else { return }
            try db.alter(table: "workout_sets") { t in
                t.add(column: "elevation_m", .double)
            }
        }

        // ── v20 ─────────────────────────────────────────────────────────────
        // "The watch got this night wrong."
        //
        // HealthKit's sleep is the one reading in the app with no way to be
        // disputed. A phone left on the bed, a nap folded into the night, a long
        // lie-in read as nine hours of core — the number lands, the score reads
        // it, and nothing on any screen can say it is wrong. This column is that
        // dispute, and it deliberately does NOT move the score: correcting a
        // measurement by self-report is how a log becomes a wish. It marks the
        // reading in the export so the reader discounts it themselves.
        //
        // NULLABLE, unlike `sleep_onset_trouble` beside it. Not a three-state
        // fact — every reader treats nil and false identically — but a nil is
        // what `encodeIfPresent` needs to keep the column OUT of the push body
        // until Postgres grows it. See the note on `DailyLogRow`.
        //
        // `dashboard-polish.sql (git history)` is the Postgres half and the founder
        // runs it by hand. Until they do, the flag lives on this device and the
        // push drops it — see the note in that file.
        migrator.registerMigration("v20.sleepInaccurate") { db in
            let existing = Set(try db.columns(in: "daily_logs").map(\.name))
            guard !existing.contains("sleep_inaccurate") else { return }
            try db.alter(table: "daily_logs") { t in
                t.add(column: "sleep_inaccurate", .boolean)
            }
        }

        // ── v21 ─────────────────────────────────────────────────────────────
        // The generic data model (W2, 2026-09-10).
        //
        // Until now the founder's plan was compiled in: the three decks, the
        // dated phases, the nutrition ladder and its schedule, the asserted
        // record book and the supplement seed all lived in `OnyxCore` as
        // constants, and a second account inherited every one of them. This
        // migration is the local half of moving them into rows:
        //
        //   · `routines`, `plan_phases`, `lever_periods`, `stress_logs` — the
        //     four tables `native/schema/supabase.json` marks `since: 2`, created
        //     by the generated `migrateMirrorV2` (a fresh install runs V1 at v9
        //     and V2 here, in that order; this store runs V2 only).
        //   · Columns W2 added to tables the mirror already holds, altered in
        //     under the same guard `v13.supplementArchive` uses: the regenerated
        //     `migrateMirrorV1` names them for a fresh install, and the guard is
        //     what stops this failing on a store that got them that way.
        //   · `exercises.slug` — the legacy `onyx-…` id as an ALIAS column,
        //     so a set logged before W2 keeps resolving to its catalogue row
        //     through data rather than through `Program.onyx5` (D3). The rep
        //     window and rest columns ride along for W5's routine builder.
        //
        // `w2-generic-model.sql (git history)` is the Postgres half and the founder
        // pastes it by hand. Until they do, the four new tables pull nothing
        // (PGRST205, which the sync HOLDS rather than acknowledges since W1)
        // and the readers see an empty catalogue.
        migrator.registerMigration("v21.genericModel") { db in
            if try !db.tableExists("routines") {
                try Self.migrateMirrorV2(db)
            }

            // Every column is NULLABLE locally, even the ones Postgres declares
            // NOT NULL DEFAULT (`plans.is_legacy`, `target_profiles.kind`,
            // `custom_supplements.sort_order`): the DDL is pasted by hand, and
            // a pull that runs before the paste must still decode the row the
            // server has always served. nil reads as the default, and
            // `encodeIfPresent` keeps the column out of a push body until the
            // server grows it — the `sleep_inaccurate` rule (v20).
            func add(_ table: String, _ columns: [(String, Database.ColumnType)]) throws {
                let existing = Set(try db.columns(in: table).map(\.name))
                let missing = columns.filter { !existing.contains($0.0) }
                guard !missing.isEmpty else { return }
                try db.alter(table: table) { t in
                    for (name, type) in missing { t.add(column: name, type) }
                }
            }

            try add("exercises", [
                ("slug", .text), ("rest_sec", .integer),
                ("rep_floor", .integer), ("rep_ceiling", .integer),
                ("archived_at", .datetime),
            ])
            try add("cardio_logs", [("elevation_m", .double)])
            try add("plans", [("blurb", .text), ("is_legacy", .boolean), ("sort", .integer)])
            try add("plan_phase_goals", [
                ("label", .text), ("fiber_g", .integer), ("body_fat_ceiling_pct", .double),
            ])
            try add("target_profiles", [("kind", .text)])
            try add("personal_records", [("floor_value", .double)])
            try add("custom_supplements", [
                ("dose_amount", .double), ("dose_unit", .text), ("sort_order", .integer),
            ])
        }

        // ── v22 ─────────────────────────────────────────────────────────────
        // "Did I actually hold the rest I prescribed?"
        //
        // The plan's rest target has been in the export since v4; what it can
        // never say is whether the block was TRAINED at it. This column is the
        // measurement: the elapsed gap between committing one set and the next
        // of the same exercise, written by the native logger.
        //
        // NOT `rest_sec`, which is dead. That column held the web deck's
        // client stopwatch until 2026-08-19, never carried a value, and its
        // name still means the old thing — reusing it would make nil ambiguous
        // between "never measured" and "measured by a tool we deleted".
        //
        // NULLABLE with no default, the `sleep_inaccurate` rule (v20): a nil is
        // what `encodeIfPresent` needs to keep the column OUT of the push body
        // until Postgres grows it. `actual-rest.sql (git history)` is the Postgres
        // half and the founder runs it by hand; until they do the measurement
        // lives on this device, the push drops it, and the export prints the
        // plan alone — which is exactly what it did before.
        migrator.registerMigration("v22.actualRest") { db in
            let existing = Set(try db.columns(in: "workout_sets").map(\.name))
            guard !existing.contains("actual_rest_sec") else { return }
            try db.alter(table: "workout_sets") { t in
                t.add(column: "actual_rest_sec", .integer)
            }
        }

        // ── EVERY SET UNDER THE CATALOGUE'S ID (W6) ─────────────────────────
        // Before W6 a set logged on this phone was stamped with a slug of the
        // movement's name and a set pulled from the server with the catalogue's
        // uuid, so one movement wore two identities and every reader that keys
        // on `exercise_id` — the session summary, the volume fold, the PR
        // engine's own grouping — had to be taught to see through it. The
        // logger now resolves the catalogue row before it writes; this is the
        // history, brought to the same rule.
        //
        // Two passes, because the local catalogue answers in two ways. The
        // `slug` column is the server's own alias for the legacy id, pulled
        // down with the row. The second pass is for the SHADOW rows this app
        // used to insert so a slug-stamped set had something to point at: their
        // id IS the slug and their name is the movement, so the real row is the
        // other one with the same name. A shadow left behind holds no sets and
        // `exerciseCatalogStream`'s `HAVING COUNT(s.id) > 0` already hides it.
        //
        // A row that resolves to NOTHING keeps its slug. It is still a logged
        // rep, `ExerciseIndex` still resolves it on push, and losing one to
        // tidiness would be the only unrecoverable outcome here.
        migrator.registerMigration("v23.catalogueIds") { db in
            try Self.adoptCatalogueIds(db)
        }

        // ── v24 ─────────────────────────────────────────────────────────────
        // Stress becomes an EVENT log (Live UX W1, decision A5): any number of
        // rows a day, each stamped with when it was felt. `logged_at` is
        // nullable locally so a pull that ran before the column reached
        // Postgres (2026-09-15) still decodes; `logStress` always
        // stamps a time, so an event logged before that paste has a non-nil
        // `logged_at`, `encodeIfPresent` pushes it, and the server rejects the
        // row until the column exists. That failure is per-row: it lands in
        // `outboxFailed` and retries under `SyncBackoff` without jamming the
        // rest of the queue. A fresh install gets the column from the
        // regenerated `migrateMirrorV2`; the guard is for that.
        migrator.registerMigration("v24.stressEvents") { db in
            guard try !db.columns(in: "stress_logs").contains(where: { $0.name == "logged_at" }) else { return }
            try db.alter(table: "stress_logs") { t in
                t.add(column: "logged_at", .datetime)
            }
        }

        // ── v25 ─────────────────────────────────────────────────────────────
        // The estimated 1RM became Brzycki and stopped being gated on the
        // programmed rep floor (2026-09-15, founder decision). Both halves are
        // STORED — `workout_sets.est_1rm_kg` and `personal_records` — so a code
        // change alone would leave every historical number on the old formula
        // and every historical record judged by the old rule, with new sets
        // measured against them. That is not a cosmetic mismatch: a bar built
        // from Epley values is systematically lower for a 1–9 rep set and
        // higher for a long one, so records would fire and fail to fire for
        // reasons nobody could see.
        migrator.registerMigration("v25.brzyckiLedger") { db in
            try Self.adoptBrzyckiEstimates(db)
        }

        // ── v26 ─────────────────────────────────────────────────────────────
        // The Health ingest gets a key (Next-Gen W1, 2026-09-15).
        //
        // `HKWorkout.uuid` is the identity Apple assigns every bout, and until
        // now nothing stored it. The duplicate rule asked instead whether an
        // existing row's `created_at` fell within five minutes of the incoming
        // bout's start — which is a heuristic over a table with no start column,
        // and misses outright whenever `created_at` did not survive the round
        // trip. Every sync then re-inserted. `WeeklyExportBuilder` documents the
        // cost in its own header: Friday exported 23 copies of one walk.
        //
        // NULLABLE with no default, the `sleep_inaccurate` rule (v20): a nil is
        // what `encodeIfPresent` needs to keep the column OUT of a push body
        // until Postgres grows it. Unlike v20, though, this column is written
        // the moment the founder walks anywhere — so between this build landing
        // and the column reaching Postgres, an imported bout's push is
        // REJECTED by the server for an unknown column. That failure is per-row
        // (`outboxFailed`, retried under `SyncBackoff`) and clears itself on the
        // first sync after the paste, exactly as `v24.stressEvents` does. The
        // column was pasted 2026-09-15 (3.10.1), so that window is closed; the
        // guard stays because a store older than v26 can still open this build.
        //
        // A fresh install gets the column from the regenerated `migrateMirrorV1`;
        // the guard is for that.
        migrator.registerMigration("v26.healthWorkoutUuid") { db in
            let existing = Set(try db.columns(in: "cardio_logs").map(\.name))
            guard !existing.contains("hk_uuid") else { return }
            try db.alter(table: "cardio_logs") { t in
                t.add(column: "hk_uuid", .text)
            }
        }

        // ── v27 ─────────────────────────────────────────────────────────────
        // And the damage the missing key already did, collapsed. Once.
        //
        // v26 stops NEW duplicates. It cannot touch the ones already in the
        // store, and every one of them is still counted by every reader that
        // sums bouts, minutes or kilocalories — the week's cardio totals, the
        // Pulse session cards, the export (which works around it by deduping at
        // render time and reporting the count as an anomaly). This is the same
        // collapse, applied to the data instead of to the view.
        migrator.registerMigration("v27.collapseCardioDuplicates") { db in
            try Self.collapseCardioDuplicates(db)
        }

        // ── v28 ─────────────────────────────────────────────────────────────
        // The body gets two sides (Next-Gen W9, 2026-09-16).
        //
        // The atlas has drawn a left and a right path per bilateral muscle
        // since it was first drawn, and the hit test has always known which of
        // the two a tap landed in. `doms_logs` was the only thing in the way:
        // one row per `(user_id, date, muscle_group)`, so a left glute and a
        // right glute could not coexist even if the words for them existed —
        // and they did, in `DomsMuscles.sides` and in the export grammar, with
        // nothing able to write them.
        //
        // BOTH NULLABLE, and absence is the pre-v2 meaning: `side` nil is
        // "both", `sub_region` nil is "the whole muscle". That is what keeps a
        // bilateral rating byte-identical to what every build before this one
        // wrote — `encodeIfPresent` leaves a nil column OUT of the push body,
        // so a whole-muscle row's request is unchanged on the wire and its
        // export token is unchanged in the document.
        //
        // The same `v26` caveat applied and for the same reason: until the
        // columns reached Postgres, a ONE-SIDED rating's push was rejected for
        // an unknown column — per-row (`outboxFailed`, retried under
        // `SyncBackoff`), clearing itself on the first sync after. A bilateral
        // rating was unaffected, because it sends neither column. Pasted
        // 2026-09-16 (3.18.2); the guard stays for every store older than v28.
        //
        // A fresh install gets both from the regenerated `migrateMirrorV1`;
        // the guard is for every store that already exists.
        migrator.registerMigration("v28.domsLaterality") { db in
            let existing = Set(try db.columns(in: "doms_logs").map(\.name))
            let missing = ["side", "sub_region"].filter { !existing.contains($0) }
            guard !missing.isEmpty else { return }
            try db.alter(table: "doms_logs") { t in
                for column in missing { t.add(column: column, .text) }
            }
        }

        // ── v29 ─────────────────────────────────────────────────────────────
        // Where an edit STARTED, so Cancel knows what to take back.
        //
        // ── WHY THE MARK IS (device_id, seq) AND NOT A TIME OR AN ID ────────
        // The obvious watermark is "the newest event when the editor opened",
        // and both candidates for that are wrong here. `set_events.id` is a
        // uuid — there is no ordering in it at all — and `created_at` is a
        // DEVICE wall clock, which is the one thing `SetEvent` exists not to
        // trust. `seq` is the Lamport value: monotonic per device, and only per
        // device. So the honest statement is a pair — "every event THIS device
        // wrote for this session above N" — and it is also the useful one: it
        // names exactly this sitting's edits and cannot name a watch's
        // concurrent ones, which a revert must leave standing.
        //
        // ── AND WHY A TABLE, NOT TWO COLUMNS ON `workout_sessions` ──────────
        // That row is encoded toward the wire. Every column on it is a column
        // `SyncTranslation.sessionRow` may send and the server may answer with,
        // and the two ends already drift by hand-applied SQL more often than
        // anyone would like. A watermark is not a fact about the workout; it is
        // a fact about a screen that is open on this device right now, and it
        // belongs where `device_state` and `live_sessions` already live —
        // local-only, no mirror entry, no outbox.
        //
        // The foreign key is what makes `discardSession` correct for free: the
        // session goes, the mark goes with it.
        migrator.registerMigration("v29.sessionEditMarks") { db in
            try db.create(table: "session_edit_marks") { t in
                t.primaryKey("session_id", .text)
                    .references("workout_sessions", onDelete: .cascade)
                t.column("device_id", .text).notNull()
                t.column("seq", .integer).notNull()
            }
        }

        // ── v30 ─────────────────────────────────────────────────────────────
        // The waist, on the day it was measured (W3, 2026-09-17).
        //
        // ── AND YES, THIS IS THE THING THE SCHEMA SAID WOULD NEVER HAPPEN ───
        // `native/schema/supabase.json` has said since it was written that Onyx
        // does not do tape measurements, because a `body_measurements` TABLE is
        // a screen of girths and that has been deleted from this product twice.
        // The founder's W3 decision narrows the rule rather than reversing it:
        // the ONE figure the athlete actually takes gets a column beside the
        // weight it was taken with. There is still no table, and therefore still
        // nowhere for hips, thighs or arms to land.
        //
        // NULLABLE with no default, the `sleep_inaccurate` rule (v20). Unlike
        // v20 and v22 the Postgres half is ALREADY pasted — `daily_logs.waist_cm`
        // was introspected live on 2026-09-17 as `numeric`, nullable, no default
        // — so a push carries the column from the first save.
        migrator.registerMigration("v30.waistCm") { db in
            let existing = Set(try db.columns(in: "daily_logs").map(\.name))
            guard !existing.contains("waist_cm") else { return }
            try db.alter(table: "daily_logs") { t in
                t.add(column: "waist_cm", .double)
            }
        }

        // ── v31 ─────────────────────────────────────────────────────────────
        // Sleep v2 (W3, 2026-09-18): when the night began, and how often it
        // broke. `onset_time` is the first asleep sample; `awakenings` is the
        // count of merged awake intervals ≥ 5 min. Both NULLABLE with no
        // default, the v30 rule — a pre-W3 night has neither and the scorer
        // drops the terms rather than reading a zero.
        //
        // Guarded like v30 because `migrateMirrorV1` is generated from
        // `supabase.json` and a fresh install already has both columns. The
        // Postgres half is `w3-sleep-onset.sql` (its text is in
        // docs/CHANGELOG.md), which the founder pasted BEFORE this build: the outbox upsert carries the
        // columns from the first night synced, and PostgREST rejects a column
        // it cannot find.
        migrator.registerMigration("v31.sleepOnset") { db in
            let existing = Set(try db.columns(in: "sleep_sessions").map(\.name))
            try db.alter(table: "sleep_sessions") { t in
                if !existing.contains("onset_time") { t.add(column: "onset_time", .datetime) }
                if !existing.contains("awakenings") { t.add(column: "awakenings", .integer) }
            }
        }

        // ── v32 ─────────────────────────────────────────────────────────────
        // The predecessor web app's name leaves the DATA (Expansion W1,
        // decision 19). Two values carried it: the current era in
        // `plan_phases.era`, and the exercise-id prefix the logger stamps.
        //
        // ── WHY THIS IS ONE MIGRATION AND NOT FOUR ─────────────────────────
        // `adoptCatalogueIds` (v23) learned the lesson the hard way and its
        // header is worth re-reading: an exercise id lives in FOUR places at
        // once — the projection (`workout_sets`), the append bodies in
        // `set_events`, the catalogue's alias column (`exercises.slug`) and,
        // for a shadow row an older build inserted, the catalogue's own id.
        // Migrating a subset is worse than migrating none: the deck reads the
        // renamed id into `storedExerciseId`, an added set lands under it, and
        // the fold restores the rest of the session under the old one. One
        // movement, two identities, in one session, opened by the very
        // migration meant to close it. So all four move together, in one
        // transaction, or nothing does.
        //
        // ── WHAT IS DELIBERATELY NOT HERE ──────────────────────────────────
        // `personal_records`. Its `exercise_key` is a canonical DISPLAY NAME,
        // not an id — "Seated Cable Row (V-Grip)", never a slug (see
        // `PrRecorder.nameResolver`, and the live table, introspected
        // 2026-09-19: 81 rows, zero carrying the old brand). Renaming keys
        // there would invent a second history for every lift.
        //
        // The server half is `w1-onyx-wire.sql` — its text is in
        // docs/CHANGELOG.md — pasted by the founder. It is NOT symmetrical with this one, because the server's
        // `workout_sets.exercise_id` is a `uuid` with a live foreign key and
        // structurally cannot hold a slug — the slug reaches Postgres only
        // inside `set_events.body`, and `ExerciseIndex` resolves it to a uuid
        // on push. Four local tables, three server ones.
        migrator.registerMigration("v32.onyxWire") { db in
            try Self.adoptOnyxWire(db)
        }

        // ── v33 ─────────────────────────────────────────────────────────────
        // Export v6 (2026-09-20): the CURRENT prescription, and the one bit
        // that says which HRV a row is holding.
        //
        // ── `prescriptions` IS APPEND-ONLY, AND THAT IS THE POINT ──────────
        // The export printed `ProgramExercise.wk1Kg` as `prescribed` — the load
        // the program was COMPILED with in July — for two months while the
        // coach moved Incline DB Press 32 → 34, Lat Pulldown 45 → 50 and the
        // RDL 30 → 40. Every `load Δ` in the document was therefore drawn
        // against a number nobody had worked to since the block began.
        //
        // A prescription is an instruction with a date on it, so each paste
        // INSERTS a version and nothing is ever updated: "the top set went
        // 34 → 36 on the 14th" is the whole argument a progression review is
        // made of, and an UPDATE destroys it. `Prescriptions.current` resolves
        // the version in force on a given day.
        //
        // ── AND `hrv_overnight` ALREADY EXISTS IN POSTGRES ─────────────────
        // Introspected live on 2026-09-20: `daily_logs.hrv_overnight boolean`.
        // It has been there since readiness v9 and was never in
        // `native/schema/supabase.json`, so the mirror never carried it and
        // nothing on this device could read or write it — while `HealthSync`
        // computed the fact every sync and threw it away. That is why three
        // Friday mornings read 102 / 93.9 / 119.8 ms against a median near 60
        // and were flagged as artifacts: the column holds the OVERNIGHT mean
        // when the night's bed window resolves and the CALENDAR-DAY mean when
        // it does not, and `VitalsGate.hrvArtifact` was judging one against a
        // history of the other.
        //
        // Guarded like v30 and v31: `migrateMirrorV1` is generated from
        // `supabase.json` and a fresh install already has the column.
        migrator.registerMigration("v33.prescriptions") { db in
            try Self.migrateMirrorV3(db)
            let existing = Set(try db.columns(in: "daily_logs").map(\.name))
            if !existing.contains("hrv_overnight") {
                try db.alter(table: "daily_logs") { t in
                    t.add(column: "hrv_overnight", .boolean)
                }
            }
            /* The version ladder is resolved per exercise and per day, and both
               reads are `WHERE user_id = ? AND exercise_key = ?` followed by an
               ORDER BY on the pair that decides which version wins. */
            try db.create(
                index: "prescriptions_user_exercise",
                on: "prescriptions", columns: ["user_id", "exercise_key", "effective_from", "version"],
                ifNotExists: true)
        }

        // ── v34: the post-workout heart-rate cache (Expansion W5) ───────────
        // LOCAL ONLY, like `set_events`: decision 10 — the series is read
        // from Health at view time and never synced, and this row is what
        // stops a second open of the same session asking Health twice. No
        // outbox kind names it and no puller fills it; `eraseLocalData` finds
        // it through `sqlite_master` like every other table. `samples_json`
        // is nullable because the Hevy decision (`hevy_decision`) lives on
        // the same row and can land before any sample has: a null series is
        // a cache MISS, not an empty series — an empty read is never cached.
        migrator.registerMigration("v34.sessionTelemetry") { db in
            try db.create(table: "session_telemetry", ifNotExists: true) { t in
                t.primaryKey("session_id", .text)
                    .references("workout_sessions", onDelete: .cascade)
                t.column("samples_json", .blob)
                t.column("segments_json", .blob)
                t.column("source", .text)
                t.column("fetched_at", .datetime)
                t.column("hevy_decision", .text)
            }
        }

        // ── v35: a supplement's dose history (App Store sprint W5) ──────────
        // `custom_supplements` carried one dose and no date, so changing it
        // rewrote every day the item had been taken. `dose_periods` records
        // each dose it replaced (`OnyxCore.DosePeriod`); `Supplements.doseAt`
        // is its one reader. A fresh install gets the column from the
        // regenerated `migrateMirrorV1`; this is the guarded alter for a store
        // that already exists — the `v21.genericModel` shape.
        //
        // NULLABLE, the `sleep_inaccurate` rule (v20): nil on every row whose
        // dose has never changed, so `encodeIfPresent` keeps the key out of
        // those rows' push bodies. `w5-dose-periods.sql` is the Postgres half
        // and the founder pastes it by hand.
        migrator.registerMigration("v35.dosePeriods") { db in
            let existing = Set(try db.columns(in: "custom_supplements").map(\.name))
            guard !existing.contains("dose_periods") else { return }
            try db.alter(table: "custom_supplements") { t in
                t.add(column: "dose_periods", .text)
            }
        }

        // ── v36 ── Sessions this device has thrown away (App Store W4).
        //
        // LOCAL ONLY. A session open travels twice — as a message, for the
        // wrist that is waiting, and queued, for the one that is not — and
        // the two copies have no order between them. The late one must not
        // put back a workout that was discarded in between (Start, then an
        // immediate Cancel): `receiveSession` refuses an open for an id here.
        // An id and nothing else; `eraseLocalData` sweeps it with the rest.
        migrator.registerMigration("v36.sessionTombstones") { db in
            try db.create(table: "session_tombstones", ifNotExists: true) { t in
                t.primaryKey("id", .text)
            }
        }

        // ── v37 ── How long the watch was off the wrist (App Store W6).
        //
        // LOCAL ONLY. Derived on this phone from the presence of heart-rate
        // samples in Health (`WristCoverage`) and meaningless on a device that
        // cannot read the same Health store — so no outbox kind names it and
        // no DDL was needed. One row per day: the off-wrist minutes of that
        // day's night window. `eraseLocalData` sweeps it through
        // `sqlite_master` like every other table.
        // ponytail: only today and yesterday are re-derived (`syncRecent`).
        // An erased store keeps no older rows, so a rescore of an older
        // off-wrist night falls back to v9's zero-hour reading — and pushes
        // that `daily_scores` row. Backfill from Health if that ever matters.
        migrator.registerMigration("v37.wristCoverage") { db in
            try db.create(table: "wrist_coverage", ifNotExists: true) { t in
                t.column("user_id", .text).notNull()
                t.column("date", .text).notNull()
                t.column("off_wrist_min", .double).notNull()
                t.primaryKey(["user_id", "date"])
            }
        }

        // ── v38: a supplement's unmapped label ingredients (overhaul C3) ────
        // The DSLD import fills `micros` with what `NutrientTargets` can key
        // and keeps the rest BY NAME, so a label's selenium or ashwagandha is
        // on the item rather than silently dropped. A jsonb string array,
        // nullable: nil on every row the import did not write, so
        // `encodeIfPresent` keeps the key out of those push bodies. A fresh
        // install gets the column from the regenerated `migrateMirrorV1`; this
        // is the guarded alter for a store that already exists (v35's shape).
        migrator.registerMigration("v38.otherIngredients") { db in
            let existing = Set(try db.columns(in: "custom_supplements").map(\.name))
            guard !existing.contains("other_ingredients") else { return }
            try db.alter(table: "custom_supplements") { t in
                t.add(column: "other_ingredients", .text)
            }
        }

        // ── v40: a program's goal, and a day's notes (Precision E1) ─────────
        // `plans.goal_kind` (bulk | cut | recomp | muscle_mass | body_fat),
        // `plans.goal_target` (jsonb: `ProgramGoalTarget`) and
        // `routines.notes`, all nullable — nil on every row written before
        // them, so `encodeIfPresent` keeps the keys out of a push until the
        // founder's `docs/sql/precision-e-programs.sql` lands. A fresh install
        // gets them from the regenerated V1/V2 creates; this is the guarded
        // alter for a store that already exists (v38's shape). Numbered 40:
        // Lane C holds v39 — the NAME is the identity, the number only has to
        // stay monotonic.
        migrator.registerMigration("v40.programGoals") { db in
            let plans = Set(try db.columns(in: "plans").map(\.name))
            for column in ["goal_kind", "goal_target"] where !plans.contains(column) {
                try db.alter(table: "plans") { t in t.add(column: column, .text) }
            }
            let routines = Set(try db.columns(in: "routines").map(\.name))
            if !routines.contains("notes") {
                try db.alter(table: "routines") { t in t.add(column: "notes", .text) }
            }
        }

        return migrator
    }
}

extension AppDatabase {

    /// One physical bout is one row. Run once, by `v27`.
    ///
    /// ── THE KEY IS THE ONE `WeeklyExportBuilder` ALREADY COMPUTES ───────────
    /// `date | kind | start | duration | distance` — the three things that
    /// identify a bout physically, plus what it was and when. Two genuinely
    /// distinct walks that agree on all five are the same walk. The export has
    /// deduped on exactly this since it found 23 copies of one Friday walk, and
    /// reusing its key is what makes the collapse and the workaround agree about
    /// what a duplicate is.
    ///
    /// A row with NO `created_at` is never collapsed, for the export's own
    /// reason: the column is nullable with no default, and a key built from an
    /// absence is the same key for every such row — a Monday cycle and a Friday
    /// swim would fold into one, and the fold would look like a duplicate
    /// removed.
    ///
    /// ── WHICH ROW SURVIVES, AND WHY THE RULE IS WRITTEN TWICE ──────────────
    /// The one carrying the most non-null figures, ties broken by the lowest
    /// `id`. Most-non-null because the duplicates are not identical: an early
    /// import has the heart rate, a later one may have gained a total energy,
    /// and keeping the emptiest would lose measurements nothing can recover.
    /// Lowest id because a tie had to break the SAME WAY here and in the
    /// server-side collapse that ran once alongside it (3.10.1, applied
    /// 2026-09-15), for the rows no device will ever open again. Two
    /// deterministic rules that agree can both run; two that disagree delete
    /// each other's survivor. Anything that re-collapses `cardio_logs` from
    /// either side keeps this rule or repeats that argument.
    ///
    /// The losers are DELETED THROUGH THE OUTBOX, not just locally. `cardio_logs`
    /// pulls on a date window, so a row removed here and left on the server
    /// comes straight back on the next sync — a local-only collapse would undo
    /// itself and look like the migration never ran.
    static func collapseCardioDuplicates(_ db: Database) throws {
        let rows = try CardioLogRow.order(Column("id")).fetchAll(db)
        var seen: [String: CardioLogRow] = [:]
        var doomed: [String] = []

        func figures(_ row: CardioLogRow) -> Int {
            [row.distanceM, row.durationMin, row.kcal, row.activeKcal,
             row.totalKcal, row.avgHr, row.effort, row.inclinePct, row.elevationM]
                .reduce(0) { $0 + ($1 == nil ? 0 : 1) }
        }

        for row in rows {
            guard let started = row.createdAt else { continue }
            let key: String = [
                row.userId, row.date, row.kind, String(started.timeIntervalSince1970),
                row.durationMin.map { String($0) } ?? "",
                row.distanceM.map { String($0) } ?? "",
            ].joined(separator: "|")

            guard let kept = seen[key] else { seen[key] = row; continue }
            // `rows` is ordered by id, so the incumbent already holds the lower
            // one and only a strictly richer challenger takes its place.
            if figures(row) > figures(kept) {
                seen[key] = row
                doomed.append(kept.id)
            } else {
                doomed.append(row.id)
            }
        }

        for id in doomed {
            _ = try CardioLogRow.deleteOne(db, key: id)
            try enqueueRowDelete(table: CardioLogRow.databaseTableName, key: ["id": id], in: db)
        }
    }

    /// Re-derive every stored estimated 1RM, then rebuild the record ledger.
    ///
    /// ── THE LOG FIRST, THE PROJECTION SECOND — v23's RULE, AGAIN ────────────
    /// `workout_sets` is a PROJECTION of `set_events`, and `reproject` rebuilds
    /// a session's rows from the fold, reading `est1rmKg` straight out of the
    /// append body. Touching only the table would be undone by the first edit
    /// to any session — and half-undone at that, since the ledger would already
    /// have been replayed against the new numbers. So the bodies are rewritten
    /// with the same function and the table is brought along, exactly as the
    /// catalogue-id migration does one screen up.
    ///
    /// ── AND A STORED ESTIMATE IS NOT EVIDENCE OF ANYTHING ───────────────────
    /// `buildBaselines` reads a stored value in preference to recomputing one
    /// (`||` semantics — a stored 0 is missing). That is right while the stored
    /// value came from the same formula, and it is exactly what makes this
    /// migration necessary rather than optional: without it the old Epley
    /// numbers would go on winning the preference forever.
    ///
    /// Rows the formula now refuses — unloaded work, and anything past
    /// `OneRepMax.maxReps` — have their estimate CLEARED rather than left
    /// standing. A number the engine would no longer produce is not a record it
    /// should still be defending.
    static func adoptBrzyckiEstimates(_ db: Database) throws {
        // The log.
        for row in try Row.fetchAll(db, sql: "SELECT id, body FROM set_events") {
            guard let data = row["body"] as Data?,
                  let body = try? OnyxJSON.decoder.decode(SetEvent.Body.self, from: data),
                  case .append(var snapshot) = body
            else { continue }
            let next = OneRepMax.estimate(weight: snapshot.weightKg, reps: Double(snapshot.reps))
            guard next != snapshot.est1rmKg else { continue }
            snapshot.est1rmKg = next
            try db.execute(
                sql: "UPDATE set_events SET body = ? WHERE id = ?",
                arguments: [try OnyxJSON.encoder.encode(SetEvent.Body.append(snapshot)), row["id"] as String]
            )
        }

        // The projection, by the same function — so a session that is never
        // reprojected reads the same as one that is.
        for row in try Row.fetchAll(db, sql: "SELECT id, weight_kg, reps FROM workout_sets") {
            let next = OneRepMax.estimate(
                weight: (row["weight_kg"] as Double?) ?? 0,
                reps: Double((row["reps"] as Int?) ?? 0)
            )
            try db.execute(
                sql: "UPDATE workout_sets SET est_1rm_kg = ? WHERE id = ?",
                arguments: [next, row["id"] as String]
            )
        }

        // ── AND THE LEDGER, IN THE SAME TRANSACTION ─────────────────────────
        // `recomputeAll` replays every session chronologically, each judged
        // only against what came before it — the one pass that can RETRACT a
        // record as well as file one, which is what a formula change needs:
        // some Epley-era records no longer stand, and some sets that were
        // refused the axis by the rep-floor gate should have held it all along.
        //
        // Per user, because that is the parameter it takes; a device holds one
        // in practice and the loop costs nothing when it holds none. A fresh
        // install has no sessions and this is a no-op.
        for userId in try String.fetchAll(db, sql: "SELECT DISTINCT user_id FROM workout_sessions") {
            try PrRecorder.recomputeAll(db, userId: userId)
        }
    }

    /// Repoint legacy slug-stamped sets at the catalogue row they belong to.
    ///
    /// ── THE LOG FIRST, THE PROJECTION SECOND ────────────────────────────────
    /// `workout_sets` is a PROJECTION of `set_events` (v2), and `reproject`
    /// deletes every row of a session and rebuilds it from the fold, which
    /// reads `exercise_id` straight out of the append body. A migration that
    /// touched only the table would be undone by the first edit to any session
    /// — and worse, half-undone: the deck would already have read the migrated
    /// id into `storedExerciseId`, so an added set would land under the new id
    /// while the fold restored the rest under the old one. One movement, two
    /// identities, in one session, opened by the very migration meant to close
    /// it. So the append bodies are remapped too, with the same map, and the
    /// table is brought along rather than relied on.
    ///
    /// ── AND IT REFUSES RATHER THAN GUESSES ──────────────────────────────────
    /// A slug two catalogue rows answer to is left alone. `Crunch Machine` and
    /// `Crunch (Machine)` both slug to `onyx-crunch-machine`, both exist, and
    /// their `is_bodyweight` differs — picking one merges a bodyweight ladder
    /// into a 57.5 kg one, permanently. It is the same question
    /// `ExerciseIndex.id(forSlug:)` answers by throwing `ambiguousExercise`,
    /// and it gets the same answer here.
    ///
    /// A slug that resolves to nothing keeps its id. It is still a logged rep,
    /// `ExerciseIndex` still resolves it on push, and losing one to tidiness
    /// would be the only unrecoverable outcome available.
    static func adoptCatalogueIds(_ db: Database) throws {
        let map = try legacyExerciseIdMap(db)
        guard !map.isEmpty else { return }

        // The log. Only an append carries a snapshot, and only a snapshot
        // carries an exercise id; an amend cannot express one at all.
        for row in try Row.fetchAll(db, sql: "SELECT id, body FROM set_events") {
            guard let data = row["body"] as Data?,
                  let body = try? OnyxJSON.decoder.decode(SetEvent.Body.self, from: data),
                  case .append(var snapshot) = body,
                  let target = map[snapshot.exerciseId]
            else { continue }
            snapshot.exerciseId = target
            try db.execute(
                sql: "UPDATE set_events SET body = ? WHERE id = ?",
                arguments: [try OnyxJSON.encoder.encode(SetEvent.Body.append(snapshot)), row["id"] as String]
            )
        }

        // The projection, by the same map — so a session that is never
        // reprojected reads the same as one that is.
        for (slug, target) in map {
            try db.execute(
                sql: "UPDATE workout_sets SET exercise_id = ? WHERE exercise_id = ?",
                arguments: [target, slug]
            )
        }
    }

    /// The predecessor's brand leaves every stored value. Run once, by `v32`.
    ///
    /// ── THE ERA NEEDS NO OLD SPELLING TO FIND ITS ROWS ─────────────────────
    /// `PhaseEra` has exactly two cases, `ppl` and `onyx`, so "every era that
    /// is not `ppl`" names the rows to rewrite without this file spelling the
    /// retired brand — which is the point of the wave. A NULL era is left as
    /// it is: absent is not the same as this era, and `PhaseDef.era` is
    /// Optional precisely so a row that never claimed one keeps saying so.
    static func adoptOnyxWire(_ db: Database) throws {
        try db.execute(sql: """
            UPDATE plan_phases SET era = ?
             WHERE era IS NOT NULL AND era <> ? AND era <> ?
            """, arguments: [PhaseEra.onyx.rawValue, PhaseEra.ppl.rawValue, PhaseEra.onyx.rawValue])

        // The catalogue first, so the alias column and the shadow rows agree
        // with the projection that is about to point at them. No foreign key
        // enforces this locally (`TrainingPuller` relies on that), so the
        // order is for the reader, not for SQLite.
        // ── `UPDATE OR IGNORE`, BECAUSE `exercises.id` IS A PRIMARY KEY ─────
        // Two shadow rows whose stamps differ and whose bodies match — say a
        // `4-` and a `5-` generation of one movement — both want the same new
        // id, and the second UPDATE would raise a UNIQUE violation. That
        // throw would propagate out of `migrator.migrate` and out of
        // `AppDatabase.init`, so the app would not launch at all and there
        // would be no recovery short of deleting the store. Only one stamp
        // generation ever shipped, so this is unlikely — but the cost is
        // total and the guard is one word. Skipping the loser is also the
        // right answer on the merits: both rows named the same movement, and
        // the survivor is the one `adoptCatalogueIds` will resolve anyway.
        for (table, column) in [("exercises", "id"), ("exercises", "slug"),
                                ("workout_sets", "exercise_id")] {
            for old in try String.fetchAll(
                db, sql: "SELECT DISTINCT \(column) FROM \(table) WHERE \(column) IS NOT NULL"
            ) {
                guard let new = ExerciseSlug.restamped(old) else { continue }
                try db.execute(
                    sql: "UPDATE OR IGNORE \(table) SET \(column) = ? WHERE \(column) = ?",
                    arguments: [new, old]
                )
            }
        }

        // The log, by the same rule — and only an append can carry an id at
        // all: an amend cannot express one. Same walk as `adoptCatalogueIds`.
        for row in try Row.fetchAll(db, sql: "SELECT id, body FROM set_events") {
            guard let data = row["body"] as Data?,
                  let body = try? OnyxJSON.decoder.decode(SetEvent.Body.self, from: data),
                  case .append(var snapshot) = body,
                  let new = ExerciseSlug.restamped(snapshot.exerciseId)
            else { continue }
            snapshot.exerciseId = new
            try db.execute(
                sql: "UPDATE set_events SET body = ? WHERE id = ?",
                arguments: [try OnyxJSON.encoder.encode(SetEvent.Body.append(snapshot)), row["id"] as String]
            )
        }

        // ── AND THEN v23 AGAIN, BECAUSE v23'S PREDICATE MOVED WITH US ───────
        // `legacyExerciseIdMap` matches the prefix by name, and that name just
        // changed. A device that has already run v23 gets a no-op here: its
        // slugs resolved to catalogue uuids years ago and `onyxWireId` refuses
        // a uuid. A device coming from a build OLDER than v23 — which upgrades
        // through the whole migrator in one go — would otherwise have its
        // slugs renamed a moment after the only pass that maps them to the
        // catalogue had looked for the old spelling and found nothing. Running
        // it again after the rename is what keeps that path whole, and it is
        // idempotent by construction, so running it on everyone else is free.
        try adoptCatalogueIds(db)
    }

    /// Legacy slug → catalogue id, for every slug exactly ONE row answers for.
    ///
    /// Two sources, both of which a real device holds. The `slug` column is the
    /// server's own alias for the legacy id, pulled down with the row. The
    /// second is the shadow rows an older build inserted so a slug-stamped set
    /// had something to point at: their id IS the slug, and the real row is the
    /// other one carrying the same name.
    static func legacyExerciseIdMap(_ db: Database) throws -> [String: String] {
        var map: [String: String] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT slug, min(id) AS target FROM exercises
             WHERE slug IS NOT NULL AND slug LIKE 'onyx-%'
             GROUP BY slug HAVING count(*) = 1
            """) {
            map[row["slug"]] = row["target"]
        }
        for row in try Row.fetchAll(db, sql: """
            SELECT legacy.id AS slug, min(c.id) AS target
              FROM exercises legacy
              JOIN exercises c ON lower(trim(c.name)) = lower(trim(legacy.name)) AND c.id <> legacy.id
             WHERE legacy.id LIKE 'onyx-%'
             GROUP BY legacy.id HAVING count(*) = 1
            """) {
            let slug: String = row["slug"]
            if map[slug] == nil { map[slug] = row["target"] }
        }
        return map
    }
}

// MARK: - Reads

extension AppDatabase {
    /// One session, if it is THIS user's — the door every session-keyed read
    /// and write goes through (W11). `workout_sets` and `set_events` carry no
    /// `user_id` locally; ownership is the session's, so it is asked here once
    /// rather than re-derived at every caller.
    static func ownedSession(_ db: Database, id: String, userId: String) throws -> WorkoutSession? {
        try WorkoutSession.filter(Column("id") == id && Column("user_id") == userId).fetchOne(db)
    }

    /// The projected sets of a session that is THIS user's, in the fold's
    /// order. `fold_order` is the fold's arrival tiebreak, carried into the
    /// table so two devices render a duplicated set_index in the same order;
    /// sorting on set_index alone leaned on rowid order, which SQLite does not
    /// promise.
    static func ownedSets(sessionId: String, userId: String) -> QueryInterfaceRequest<WorkoutSet> {
        WorkoutSet
            .filter(
                sql: "session_id = ? AND EXISTS (SELECT 1 FROM workout_sessions WHERE id = ? AND user_id = ?)",
                arguments: [sessionId, sessionId, userId]
            )
            .order(Column("set_index"), Column("fold_order"))
    }

    /// Sessions for a day, newest first.
    public func sessions(on date: String, userId: String) throws -> [WorkoutSession] {
        try writer.read { db in
            try WorkoutSession
                .filter(Column("user_id") == userId && Column("date") == date)
                .order(Column("started_at").desc)
                .fetchAll(db)
        }
    }

    /// Live-updating sets for a session, in logged order.
    ///
    /// A `ValueObservation` rather than a fetch: the logger writes a set and the
    /// list redraws, with no refresh call, no invalidation key and no chance of
    /// the two disagreeing.
    public func observeSets(sessionId: String, userId: String) -> ValueObservation<ValueReducers.Fetch<[WorkoutSet]>> {
        ValueObservation.tracking { db in
            try Self.ownedSets(sessionId: sessionId, userId: userId).fetchAll(db)
        }
    }

    /// One session by id. The drainer's read: it pushes the row as it stands
    /// now, never a copy captured when the queue item was written.
    public func session(id: String, userId: String) throws -> WorkoutSession? {
        try writer.read { db in try Self.ownedSession(db, id: id, userId: userId) }
    }

    public func exercises() throws -> [Exercise] {
        try writer.read { db in
            try Exercise.order(Column("name")).fetchAll(db)
        }
    }

    /// The projected sets for a session, in the fold's own order.
    ///
    /// The non-observing twin of `observeSets`. The logger needs it exactly
    /// once — at attach, to fold what is already logged back onto the deck —
    /// and a `ValueObservation` for a single read is a subscription to cancel
    /// for no benefit.
    public func sets(sessionId: String, userId: String) throws -> [WorkoutSet] {
        try writer.read { db in try Self.ownedSets(sessionId: sessionId, userId: userId).fetchAll(db) }
    }

    /// The session for a split that is still being logged, if there is one.
    ///
    /// ── UNFINISHED IS THE WHOLE PREDICATE ───────────────────────────────────
    /// `ended_at IS NULL`. Without it, opening the logger after finishing a
    /// morning Upper A rejoins THAT session, and an evening Upper A hours later
    /// is appended to the morning's row — two workouts silently merged into one,
    /// with a duration spanning the gap between them. Two-a-days are real, and
    /// so is finishing a session and going back in to correct a set.
    ///
    /// Keyed on `(date, day_key)` and never on the weekday: a swap moves a
    /// workout to another date, and a Wednesday "Delts & Arms" landed in the
    /// Upper A curve exactly that way.
    public func liveSession(dayKey: String, date: String, userId: String) throws -> WorkoutSession? {
        try writer.read { db in
            try WorkoutSession
                .filter(Column("user_id") == userId
                        && Column("date") == date
                        && Column("day_key") == dayKey
                        && Column("ended_at") == nil)
                .order(Column("started_at"))
                .fetchOne(db)
        }
    }

    /// Find the unfinished session for a split, or open one.
    ///
    /// ── WHY IT IS LOOK-UP-OR-CREATE AND NOT CREATE ──────────────────────────
    /// `set_events.session_id` has a foreign key to `workout_sessions`, so a
    /// row must exist before the first append. A logger that created one on
    /// every launch would start a second session beside the one you are halfway
    /// through, and every set logged after the relaunch would be attributed to
    /// it — a split silently torn in two, with both halves well-formed.
    ///
    /// The caller should reach this on a deliberate START — the watch's Start
    /// button, the phone logger being presented by "Start workout" (App Store
    /// W4, `LoggerModel.begin`) — or on the first write, and never because a
    /// screen merely appeared. Called from a tab's `onAppear`, it would leave
    /// an empty session row behind every time the tab was opened and closed.
    @discardableResult
    public func openSession(
        userId: String,
        dayKey: String,
        date: String,
        startedAt: Date = Date()
    ) throws -> WorkoutSession {
        if let live = try liveSession(dayKey: dayKey, date: date, userId: userId) { return live }
        return try writer.write { db in
            // Re-checked inside the transaction: the read above is not part of
            // it, and two writers (the phone and, at Wave 5, the watch) racing
            // on the same split would otherwise each create a row.
            if let live = try WorkoutSession
                .filter(Column("user_id") == userId
                        && Column("date") == date
                        && Column("day_key") == dayKey
                        && Column("ended_at") == nil)
                .order(Column("started_at"))
                .fetchOne(db) {
                return live
            }
            let session = WorkoutSession(
                id: newOnyxID(), userId: userId, dayKey: dayKey, date: date,
                startedAt: startedAt, isPendingSync: true
            )
            try session.insert(db)
            return session
        }
    }

    /// What `receiveSession` did with a pulse.
    public enum SessionPulseOutcome: Sendable, Equatable {
        /// A row this device had never seen is now here, live. `superseded`
        /// is this device's own EMPTY live row for the same split that the
        /// arriving one beat — already discarded here; the caller tells the
        /// other device and, if it was holding it, moves to the winner.
        case opened(superseded: WorkoutSession?)
        /// A live row was closed at the sender's instant.
        case closed
        /// The row, its events and its sets are gone.
        case discarded
        /// Nothing to do: already known, already closed, already gone,
        /// tombstoned, or (for a finish or a discard) another account's.
        case unchanged
    }

    /// Apply the other device's session open, finish or discard (App Store W4).
    ///
    /// ── ORDER-SAFE BY CONSTRUCTION ──────────────────────────────────────────
    /// Every phase is idempotent and the three are monotonic: an open never
    /// rewrites a row that exists, so it cannot reopen a finished workout or
    /// move its start; a finish touches only a row that is still open; a
    /// discard touches only a row that is still open too, so a finish always
    /// beats one — the wrist's "throw this away" arriving after the phone has
    /// closed, ledgered and pushed the workout must not delete it.
    ///
    /// ── TWO DEVICES, ONE SPLIT, ONE WINNER ──────────────────────────────────
    /// Start on the phone with the watch app closed, open it and tap Start
    /// before the queued open lands, and each device has a live row for the
    /// same split. The earlier start wins (id breaks a tie) and the rule is
    /// applied on both devices, so both reach the same answer: the device
    /// holding the loser discards it — only if nothing was logged into it —
    /// and says so. A loser WITH sets is left alone; two logs cannot be
    /// merged by a rule this small, and a second session is the honest
    /// outcome for a workout that was genuinely logged twice.
    ///
    /// ── AND A LATE OPEN CANNOT REVIVE A DISCARDED ONE ───────────────────────
    /// An open travels twice, by message and by queue, in no order. Every
    /// discard on this device leaves the id in `session_tombstones`, and an
    /// open for one of those is refused.
    ///
    /// ── AN OPEN IS NOT QUEUED FOR UPLOAD ────────────────────────────────────
    /// The row reaches the server behind the first event that names it (the
    /// push's `ON CONFLICT DO NOTHING` ensure) and in full at the close, which
    /// `closeSession` queues — the same two roads a row this device opened
    /// takes. Queueing it here would push an empty open session nobody may
    /// ever log into, which `openSession` deliberately never does either.
    @discardableResult
    public func receiveSession(_ pulse: SessionPulse) throws -> SessionPulseOutcome {
        switch pulse.phase {
        case .open:
            return try writer.write { db in
                guard try WorkoutSession.fetchOne(db, key: pulse.sessionId) == nil,
                      try !(Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM session_tombstones WHERE id = ?)",
                                          arguments: [pulse.sessionId]) ?? false)
                else { return .unchanged }
                let arriving = WorkoutSession(
                    id: pulse.sessionId, userId: pulse.userId, dayKey: pulse.dayKey, date: pulse.date,
                    startedAt: pulse.startedAt, isPendingSync: true
                )
                try arriving.insert(db)
                let rival = try WorkoutSession
                    .filter(Column("user_id") == pulse.userId && Column("date") == pulse.date
                            && Column("day_key") == pulse.dayKey && Column("ended_at") == nil
                            && Column("id") != pulse.sessionId)
                    .order(Column("started_at"))
                    .fetchOne(db)
                guard let rival, Self.startsFirst(arriving, rival),
                      try SetEvent.filter(SetEvent.Columns.sessionId == rival.id).fetchCount(db) == 0,
                      try Self.discard(db, id: rival.id, userId: rival.userId)
                else { return .opened(superseded: nil) }
                return .opened(superseded: rival)
            }
        case .finished:
            guard let row = try session(id: pulse.sessionId, userId: pulse.userId), row.endedAt == nil else {
                return .unchanged
            }
            try closeSession(id: row.id, endedAt: pulse.endedAt ?? Date(), restTargetSec: pulse.restTargetSec)
            return .closed
        case .discarded:
            return try writer.write { db in
                guard try Self.ownedSession(db, id: pulse.sessionId, userId: pulse.userId)?.endedAt == nil,
                      try Self.discard(db, id: pulse.sessionId, userId: pulse.userId)
                else { return .unchanged }
                return .discarded
            }
        case .joined:
            // A fact about the other device's runtime, not about the row.
            return .unchanged
        }
    }

    /// Earlier start wins; the id settles a tie, so both devices agree.
    ///
    /// ── IN WHOLE SECONDS, BECAUSE THAT IS WHAT CROSSES ──────────────────────
    /// `OnyxJSON` writes ISO-8601 without a fraction, so the arriving row's
    /// start is truncated and the local one is not. Compared as they stand,
    /// two Starts inside one second each see the OTHER as earlier, each
    /// discards its own row, and the workout is gone on both devices. Floored
    /// to the second on both sides, that case is a tie and the id decides it
    /// the same way everywhere. A missing start sorts first, as SQLite's
    /// `ORDER BY started_at` sorts NULL — one rule for both reads.
    static func startsFirst(_ a: WorkoutSession, _ b: WorkoutSession) -> Bool {
        func second(_ s: WorkoutSession) -> Double { (s.startedAt?.timeIntervalSince1970 ?? -.infinity).rounded(.down) }
        return second(a) != second(b) ? second(a) < second(b) : a.id < b.id
    }

    /// A session for a day that has already happened (W2, decision 12).
    ///
    /// ── BORN CLOSED ─────────────────────────────────────────────────────────
    /// `openSession` makes a LIVE session: `ended_at` null, `liveSession` finds
    /// it, the logger runs a clock and a rest timer over it, the Live Activity
    /// follows it and the watch mirrors it. None of that is true of a workout
    /// done last Tuesday. So the row is created with `ended_at` already set —
    /// which is exactly the state `SessionEditing` and `attach(editing:)`
    /// accept — and the deck that opens on it is the EDIT deck: no timer, no
    /// activity, no pencil, every set through `SessionEditing` with its PR
    /// replay, and the duration typed into the finish sheet rather than read
    /// off a clock that never ran.
    ///
    /// `started_at` is local noon on the date, so the session sorts inside its
    /// own day on every device and the rescore door files it under that date.
    /// `duration_min` stays nil until the athlete types one; `ended_at` equals
    /// `started_at` until then, and `updateMetrics` moves neither.
    @discardableResult
    public func createRetroSession(
        userId: String, dayKey: String, date: String, calendar: Calendar = .current
    ) throws -> WorkoutSession {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let noon = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else { throw DatabaseError(message: "createRetroSession: not a date: \(date)") }
        return try writer.write { db in
            let session = WorkoutSession(
                id: newOnyxID(), userId: userId, dayKey: dayKey, date: date,
                startedAt: noon, endedAt: noon, isPendingSync: true
            )
            try session.insert(db)
            try Self.enqueueSessionUpsert(sessionId: session.id, in: db)
            return session
        }
    }

    /// Stamp a session finished, and queue the finished row for upload.
    ///
    /// `duration_min` is derived here rather than by the caller because a
    /// duration computed from a clock the row does not carry is a duration
    /// nobody can check.
    ///
    /// The enqueue is in the same transaction as the stamp, for the same reason
    /// `EventStore.commit` puts the append and its queue row in one: a session
    /// that is finished locally and absent from the queue is a workout that
    /// stops syncing with no symptom.
    /// - Parameter restTargetSec: the rest the last movement prescribes, for the
    ///   long-idle guard. The logger passes `ProgramExercise.restSec`; nil takes
    ///   `SessionDuration.defaultRestTargetSec`.
    @discardableResult
    public func closeSession(
        id: String,
        endedAt: Date = Date(),
        sessionRpe: Double? = nil,
        restTargetSec: Double? = nil
    ) throws -> WorkoutSession? {
        try writer.write { db in
            guard var session = try WorkoutSession.fetchOne(db, key: id) else { return nil }
            session.endedAt = endedAt
            // ── THE PAUSE COMES OFF, AND A LONG IDLE IS NOT TRAINING ────────
            // This was `endedAt − startedAt`, which is the same arithmetic that
            // recorded 2026-09-06's hour of work as 385 minutes on the web. One
            // rule now, in `OnyxCore`, with a vector — see `SessionDuration`.
            let events = try SetEvent
                .filter(SetEvent.Columns.sessionId == id)
                .fetchAll(db)
            // A seed with no clock to carry is stamped AT the session's start
            // (`seedEventLog`): it says nothing about when the set was logged, so
            // it must not become the "last set". Filtered out here, a session whose
            // only events are clockless seeds has no last set, and `SessionDuration`
            // then declines to cap rather than answering one rest.
            let opened = session.startedAt ?? .distantPast
            let lastSetAt = events
                .filter { ($0.kind == .append || $0.kind == .amend) && $0.createdAt > opened }
                .map(\.createdAt)
                .max()
            let derived = SessionDuration.compute(
                startedAt: session.startedAt,
                endedAt: endedAt,
                pausedSec: Self.pausedSeconds(events, now: endedAt),
                // The same fold, evaluated at the last set rather than at the
                // finish: a pause tapped AFTER the last set is inside the tail
                // the long-idle guard discards, and subtracting it from the
                // work as well would take those minutes twice.
                pausedBeforeLastSetSec: lastSetAt.map { Self.pausedSeconds(events, now: $0) } ?? 0,
                lastSetAt: lastSetAt,
                restTargetSec: restTargetSec
            )
            // ── A TYPED DURATION SURVIVES THE CLOSE ─────────────────────────
            // `duration_edited` says a person answered this, and the clock is
            // then not allowed to argue. Without the check, correcting the
            // duration in the finish sheet and then tapping Finish would hand
            // the number straight back to the arithmetic that was corrected.
            if let minutes = derived.minutes, !session.durationEdited { session.durationMin = minutes }
            // `nil` leaves the existing rating alone rather than clearing it —
            // an unrated session is not a session rated zero, and the battery
            // falls back to its own default rather than treating it as easy.
            if let sessionRpe { session.sessionRpe = sessionRpe }
            try session.update(db)
            try Self.enqueueSessionUpsert(sessionId: id, in: db)
            // The ledger, in the SAME transaction as the close. A record that
            // exists only because a later write succeeded is a record that
            // disappears when it does not. `user_id` comes off the session
            // rather than the environment: the record belongs to whoever owns
            // the workout, and that is a fact already on disk.
            //
            // NOT wrapped in a `try?`. `save.ts` treats its own PR write as
            // self-healing and ignores the failure, and it is right to: over
            // there the upsert is a separate HTTP request that can fail against
            // an un-migrated table while the session has already been saved.
            // Here it is three more statements inside a transaction that has
            // just written the session — there is no state in which one lands
            // and the other does not, so a failure means the store is broken
            // and swallowing it would only hide that.
            let prs = try PrRecorder.record(
                db, sessionId: id, userId: session.userId, dayKey: session.dayKey, date: session.date
            )
            // ── AND THE THREE AGGREGATES THE WEB HAS ALWAYS WRITTEN ─────────
            // `SyncEngine` left `total_volume_kg`, `set_count` and `pr_count`
            // NULL while `sessionVolumeKg`, `countCommittedSets` and `prEngine`
            // were unported. All three are ported, so a session finished on the
            // phone now carries the same figures a session finished on the web
            // does — and `SessionEditing` keeps them true afterwards.
            let sets = try WorkoutSet.filter(Column("session_id") == id).fetchAll(db)
            let totals = SessionEditing.totals(sets)
            session.totalVolumeKg = totals.volumeKg
            session.setCount = totals.count
            session.prCount = prs.prCount
            try session.update(db)
            // ── AND THE DECK ORDER, WHICH IS THE ONE THING THE SETS CARRY
            // AND THE NEXT SESSION DID NOT ────────────────────────────────
            // `moveExercise` writes `exercise_order` on the rows, so a reorder
            // reached the session report and stopped there: the next deck was
            // built from a compiled constant (rows since W2). `save.ts` has
            // upserted `routine_templates` on every web commit since the day it
            // was written, and this is the phone's half of it. In the same
            // transaction as the close, for the reason the ledger is.
            try RoutineOrder.save(db, session: session)
            return session
        }
    }

    /// Throw a session away — the workout did not happen.
    ///
    /// ── WHY THIS IS A DELETE AND NOT A CLOSE ────────────────────────────────
    /// Since App Store W4 Start opens the row (so the other device can follow
    /// before the first set), and cancelling out of an empty one comes through
    /// here too — cheaply: nothing was ever pushed for it. What this is really
    /// for is the session you started, logged a set into, and then realised was
    /// the wrong day — where closing it would leave a one-set workout in the history,
    /// in the trends, in the week's volume and in the PR ledger, and voiding
    /// every set would leave an empty session row that is indistinguishable
    /// later from a workout somebody abandoned.
    ///
    /// ── AND WHY THE QUEUE IS SWEPT BEFORE THE ROW GOES ──────────────────────
    /// The session may already have been pushed — the drain runs on every
    /// foreground — so the server is told to delete it too. Any outbox item
    /// still naming this session would put it straight back: the session upsert
    /// re-creates the row, and a queued set event re-creates the set. Both are
    /// removed in the SAME transaction as the delete, or a process killed in
    /// between resurrects exactly the workout the user just discarded.
    ///
    /// Locally it is one statement: `set_events`, `live_sessions` and
    /// `workout_sets` all cascade from `workout_sessions`.
    @discardableResult
    public func discardSession(id: String, userId: String) throws -> Bool {
        try writer.write { db in try Self.discard(db, id: id, userId: userId) }
    }

    static func discard(_ db: Database, id: String, userId: String) throws -> Bool {
        guard try Self.ownedSession(db, id: id, userId: userId) != nil else { return false }

        // Server-side deletes, queued while the ids are still readable.
        for set in try WorkoutSet.filter(Column("session_id") == id).fetchAll(db) {
            try Self.enqueueRowDelete(table: WorkoutSet.databaseTableName, key: ["id": set.id], in: db)
        }
        try Self.enqueueRowDelete(table: WorkoutSession.databaseTableName, key: ["id": id], in: db)

        // Anything still queued that would bring it back.
        try db.execute(
            sql: "DELETE FROM outbox WHERE idempotency_key = ?", arguments: ["session:\(id)"]
        )
        for item in try OutboxItem.fetchAll(db)
        where item.kind.hasPrefix(SyncKind.setEventPrefix) {
            guard let event = try? OnyxJSON.decoder.decode(SetEvent.self, from: item.payload),
                  event.sessionId == id
            else { continue }
            try item.delete(db)
        }

        try db.execute(sql: "DELETE FROM workout_sessions WHERE id = ?", arguments: [id])
        // So a late copy of this session's open cannot put it back (v36).
        try db.execute(sql: "INSERT OR IGNORE INTO session_tombstones (id) VALUES (?)", arguments: [id])
        return true
    }

    /// Move the session's start instant.
    ///
    /// ── WHY THE CLOCK IS ALLOWED TO EDIT A FACT ─────────────────────────────
    /// You start the deck, do a set, and only then notice you started it twenty
    /// minutes after you started training — or you opened it early and it has
    /// been running since. The hero's timer sheet corrects that, and the
    /// correction has to land HERE or `closeSession` derives `duration_min`
    /// from a start nobody believes: the timer would say 62 minutes and the
    /// stored session 82.
    ///
    /// `started_at` is not free-floating — `Era.forDate`, the PR date and every
    /// "when did you train" reader take it — so this is a correction and never
    /// a rebase around a pause. The pause ledger is untouched, which is the
    /// same rule `PauseControlling.setElapsed` states.
    public func setSessionStart(id: String, startedAt: Date, userId: String) throws {
        try writer.write { db in
            guard var session = try Self.ownedSession(db, id: id, userId: userId) else { return }
            session.startedAt = startedAt
            try session.update(db)
            try Self.enqueueSessionUpsert(sessionId: id, in: db)
        }
    }

    /// The two figures the athlete knows and the watch might not.
    ///
    /// ── WHY A HAND-ENTERED FIGURE IS STAMPED `estimated = false` ────────────
    /// `sessionsNeedingMetrics` revisits a session for fourteen days looking for
    /// an `HKWorkout` to measure, and it selects rows whose figures are absent
    /// OR estimated. A number you typed is neither: stamping it measured is what
    /// takes the session out of that query, so a later sync cannot quietly
    /// replace what you said with what the phone inferred. Same rule as the
    /// hand-corrected day in `ingest` — a correction wins.
    ///
    /// `nil` leaves a figure alone rather than clearing it; clearing one is not
    /// a thing the finish sheet can ask for and inventing the distinction here
    /// would be a fourth state nothing reads.
    /// `durationMin` was added in E1 and carries `duration_edited` with it: a
    /// duration a person typed is not the clock's to re-derive on close.
    ///
    /// ── ONE IMPLEMENTATION, TWO NAMES ───────────────────────────────────────
    /// The body moved to `SessionEditing`'s `updateMetrics`, which does the
    /// same three columns plus the aggregate recount every write of this row
    /// now owes. This stays because the finish sheet and `SessionMetrics` both
    /// call it, and two functions writing the same columns by slightly
    /// different rules is exactly how the provenance flags drift apart.
    @discardableResult
    public func setSessionMetrics(
        id: String, userId: String, durationMin: Double? = nil, avgBpm: Int? = nil, caloriesBurned: Int? = nil,
        measured: Bool = true
    ) throws -> SessionEditing.Outcome? {
        guard durationMin != nil || avgBpm != nil || caloriesBurned != nil else { return nil }
        return try updateMetrics(
            sessionId: id, userId: userId, durationMin: durationMin, avgBpm: avgBpm, calories: caloriesBurned,
            measured: measured
        )
    }

    /// The three figures the LAST session of this split came to.
    ///
    /// ── WHY THE FINISH SHEET WANTS THEM ─────────────────────────────────────
    /// Heart rate and calories arrive from the watch's own `HKWorkout`, which
    /// can be a day late — so the sheet that asks for them is routinely the one
    /// screen in the app that has nothing to show, and "—" is not a default
    /// anybody can improve on with a stepper that starts at zero. The previous
    /// session of the same split is: the same movements, the same rest, the same
    /// person, usually within a few percent.
    ///
    /// It is a DEFAULT and not a measurement, which is why the sheet writes it
    /// back with `measured: false` — see `updateMetrics`. A carried-over figure
    /// that stamped itself measured would take the session out of
    /// `sessionsNeedingMetrics` and so forbid the watch from ever correcting it,
    /// which is the exact failure the `avg_bpm = 2` clamp exists for.
    ///
    /// Finished sessions only, same `day_key`, strictly before `date`, most
    /// recent first — the same shape as `effortHistory`, and for the same
    /// reason: a Push day's cost tells you nothing about a Legs day's.
    public func previousSessionMetrics(
        userId: String, dayKey: String?, before date: String
    ) throws -> (durationMin: Double?, avgBpm: Int?, calories: Int?) {
        guard let dayKey else { return (nil, nil, nil) }
        return try writer.read { db in
            // Up to six back, not one: the figures are independently nullable,
            // so the last session may carry a duration and no heart rate while
            // the one before it has both. Each column takes the most recent
            // session that HAS it, which is what makes the sheet arrive full
            // rather than half full.
            let sessions = try WorkoutSession
                .filter(
                    Column("user_id") == userId
                        && Column("day_key") == dayKey
                        && Column("date") < date
                        && Column("ended_at") != nil
                )
                .order(Column("date").desc, Column("started_at").desc)
                .limit(6)
                .fetchAll(db)
            return (
                sessions.lazy.compactMap(\.durationMin).first,
                sessions.lazy.compactMap(\.avgBpm).first,
                sessions.lazy.compactMap(\.caloriesBurned).first
            )
        }
    }
}

// MARK: - Writes

extension AppDatabase {
    /// The queue, oldest first. Read-only — it does NOT reserve anything, so two
    /// workers calling this both get the same rows. Use `claimOutbox` to drain.
    ///
    /// Ordered by `rowid`, not `created_at`. `SetEvent` spends a dozen lines
    /// explaining that wall clocks step backwards under NTP and must never be
    /// sorted by, and then this queue — which decides the order facts reach the
    /// server — was sorting by `Date()`. `rowid` is insertion order and cannot
    /// invert among rows that both still exist.
    public func pendingOutbox(limit: Int = 50) throws -> [OutboxItem] {
        try writer.read { db in
            try OutboxItem
                .filter(Column("status") != OutboxItem.Status.inFlight.rawValue)
                .order(Column("rowid"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Reserve a batch for one worker, marking it `inFlight` in the same
    /// transaction as the read.
    ///
    /// `inFlight` existed as an enum case and a filter, and nothing ever set it
    /// — so the "two workers cannot pick up the same write" the old comment
    /// promised was not implemented. A foreground flush and a background task
    /// firing together both got the same 50 rows and both uploaded them.
    ///
    /// `now` is injectable so a test can prove the backoff without sleeping.
    public func claimOutbox(limit: Int = 50, now: Date = Date()) throws -> [OutboxItem] {
        try writer.write { db in
            let batch = try OutboxItem
                .filter(Column("status") != OutboxItem.Status.inFlight.rawValue)
                // NULL means "now" — every row queued before v8, and every
                // fresh append. `Column(...) == nil` renders `IS NULL`, which
                // is the only comparison NULL answers truthfully.
                .filter(Column("next_attempt_at") == nil || Column("next_attempt_at") <= now)
                .order(Column("rowid"))
                .limit(limit)
                .fetchAll(db)
            for var item in batch {
                item.status = .inFlight
                try item.update(db)
            }
            return batch
        }
    }

    /// Return abandoned reservations to the queue.
    ///
    /// Call at launch. A process killed mid-flight — which iOS does routinely —
    /// leaves rows marked `inFlight` with no worker, and without this sweep they
    /// are stranded forever: excluded from every future batch, never retried,
    /// never surfaced.
    @discardableResult
    public func resetInFlight() throws -> Int {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE outbox SET status = 'pending' WHERE status = 'in_flight'"
            )
            return db.changesCount
        }
    }

    /// EVERY local row, gone. Called on sign-out, after the outbox has drained.
    ///
    /// ── WHY sqlite_master AND NOT A LIST OF TABLES ──────────────────────────
    /// A hand-maintained list falls behind the schema silently, and the failure
    /// is the worst kind: the next user signs in and finds one table still full
    /// of somebody else's data, in a store the widget reads without any session
    /// at all. The schema itself is the only list that cannot go stale.
    /// `sqlite_master` is not user input, and the names are quoted regardless.
    ///
    /// The migration table is kept, deliberately: the schema is still correct,
    /// only its contents are wrong, and dropping the migration record would
    /// make the next open re-run every migration against tables that exist.
    /// `defer_foreign_keys` lets the deletes run in whatever order the catalog
    /// hands back rather than making this care about the reference graph.
    public func eraseLocalData() throws {
        try writer.write { db in try Self.eraseLocalData(db) }
    }

    static func eraseLocalData(_ db: Database) throws {
        let tables = try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table'
              AND name NOT LIKE 'sqlite_%'
              AND name <> 'grdb_migrations'
            """)
        try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
        for table in tables {
            try db.execute(sql: "DELETE FROM \"\(table)\"")
        }
    }

    /// The account-switch door (W11).
    ///
    /// A sign-in whose user is not the one this store belongs to erases the
    /// store BEFORE the first sync — the same `eraseLocalData()` sign-out
    /// runs, reached from the other direction. `sharedFolder()` has no user
    /// component, so without this a sign-in that skipped sign-out read the
    /// previous account's rows under the new one until its own sync landed.
    ///
    /// Returns nil when nothing had to happen — an empty store, or the same
    /// user signing back in — else the number of queued changes the previous
    /// account had not pushed and has now lost. `signOut()` drains the queue
    /// first and reports the remainder; a switch CANNOT drain, because the
    /// session in hand is the new user's and RLS would refuse the old rows.
    /// So the count is read before the erase and handed back, and the caller
    /// reports it exactly as sign-out reports its own. One transaction: the
    /// count and the erase describe the same store.
    public func prepareForUser(_ userId: String) throws -> Int? {
        try writer.write { db in
            guard let owner = try Self.knownUserId(db), owner != userId else { return nil }
            let unsynced = try Int.fetchOne(db, sql: "SELECT count(*) FROM outbox") ?? 0
            try Self.eraseLocalData(db)
            return unsynced
        }
    }

    /// `profiles.role` for one user, from the mirror. Nil when the row has not
    /// synced yet — which the caller must treat as "not an admin", not as an
    /// error. See `AppEnvironment.role`.
    public func role(userId: String) throws -> String? {
        try writer.read { db in
            try ProfileRow.filter(Column("user_id") == userId).fetchOne(db)?.role
        }
    }

    /// Return THESE reservations to the queue, if they are still reserved.
    ///
    /// The narrow twin of `resetInFlight`, for a drain to clean up after
    /// itself. Blanket-resetting at the end of a drain would also release rows
    /// a *concurrent* drain is still uploading — harmless for correctness,
    /// since every write here is idempotent, but it opens a window where the
    /// same batch is uploaded twice for no reason.
    ///
    /// The `status = 'in_flight'` guard is what makes it safe to call on every
    /// path: a row already acknowledged is gone, and a row already failed keeps
    /// its `failed` status and its backoff.
    @discardableResult
    public func returnToQueue(ids: [String]) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        return try writer.write { db in
            let placeholders = databaseQuestionMarks(count: ids.count)
            try db.execute(
                sql: """
                    UPDATE outbox SET status = 'pending'
                    WHERE status = 'in_flight' AND id IN (\(placeholders))
                    """,
                arguments: StatementArguments(ids)
            )
            return db.changesCount
        }
    }

    /// The server accepted it. Clear the pending flag on whatever it described.
    ///
    /// For a set event that means marking the event synced and rebuilding the
    /// session's projection, so `is_pending_sync` on the affected sets stops
    /// being true and the "queued" badge disappears from the UI on its own —
    /// the `ValueObservation` on `workout_sets` sees the rewrite and pushes it.
    /// How many rows are still waiting to reach the server.
    ///
    /// Read by sign-out, which erases the local store: work that never made it
    /// off the device is about to be discarded, and a user is owed the number.
    /// A bare count, with no status filter, because there is no terminal status
    /// to exclude: `outboxSucceeded` DELETES the row. The only two statuses a
    /// row can hold are `pending` and `in_flight`, and both mean "not yet on
    /// the server", which is exactly what this is asking.
    public func outboxPendingCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM outbox") ?? 0
        }
    }

    public func outboxSucceeded(_ id: String) throws {
        try writer.write { db in
            guard let item = try OutboxItem.fetchOne(db, key: id) else { return }

            if item.kind.hasPrefix("set_event.") {
                let parts = item.idempotencyKey.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { throw EventStoreError.unresolvableAck(item.idempotencyKey) }
                let eventId = String(parts[1])

                guard let sessionId = try String.fetchOne(
                    db,
                    sql: "SELECT session_id FROM set_events WHERE id = ?",
                    arguments: [eventId]
                ) else {
                    // The ack names an event this store does not have. Deleting
                    // the queue row anyway would strand the set: `is_synced`
                    // stays 0, the projection keeps reporting it pending, and
                    // nothing is left in the queue to ever clear it — a
                    // permanent "queued" badge on a set that is on the server.
                    throw EventStoreError.unresolvableAck(item.idempotencyKey)
                }

                try db.execute(
                    sql: "UPDATE set_events SET is_synced = 1 WHERE id = ?",
                    arguments: [eventId]
                )
                try Self.reproject(sessionId: sessionId, in: db)
            }

            _ = try OutboxItem.deleteOne(db, key: id)
        }
    }

    /// The server did not accept it. Record why and let it be retried.
    ///
    /// The item is NOT dropped after N attempts. A workout that cannot sync is a
    /// workout you still did, and a queue that gives up is a queue that loses
    /// data quietly — the failure belongs in front of the user, not in a
    /// discarded row.
    ///
    /// It does get slower, though. `SyncBackoff` decides when it may next be
    /// tried, from the attempt count this call just raised — computed here
    /// rather than by the caller so there is no path that records a failure and
    /// forgets to space out its retry.
    public func outboxFailed(_ id: String, error: String, now: Date = Date()) throws {
        try writer.write { db in
            guard var item = try OutboxItem.fetchOne(db, key: id) else { return }
            item.attempts += 1
            item.lastError = error
            item.status = .failed
            item.nextAttemptAt = now.addingTimeInterval(
                SyncBackoff.delay(attempts: item.attempts, jitter: Double.random(in: 0...1))
            )
            try item.update(db)
        }
    }

    /// The server has this session row.
    ///
    /// `openSession` stamps `is_pending_sync` and, until the drainer existed,
    /// nothing ever cleared it — so every session the logger opened stayed
    /// flagged for the life of the install, whatever the server actually had.
    /// The sets clear themselves through `reproject`; the session row needs
    /// this, because it is not a projection of anything.
    public func markSessionSynced(id: String) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE workout_sessions SET is_pending_sync = 0 WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Queue the session row itself for upload.
    ///
    /// ── WHY THIS IS NOT COVERED BY THE SET EVENTS ───────────────────────────
    /// Every append queues an item, and the drainer pushes the session row
    /// alongside the sets it names — so a session in progress reaches Postgres
    /// for free. Finishing one does not: `closeSession` writes `ended_at`,
    /// `duration_min` and `session_rpe` and there is no set event afterwards to
    /// carry them. Without this call the last thing every workout does never
    /// syncs, and the server keeps the session open forever.
    ///
    /// The payload is the session id and nothing else. The drainer reads the
    /// current row when it runs, so a queued item can never carry a stale copy
    /// of a session that was edited after it was queued.
    static func enqueueSessionUpsert(sessionId: String, in db: Database) throws {
        let key = "session:\(sessionId)"
        // Replace rather than accumulate. `idempotency_key` is UNIQUE, so a
        // second close (rating a session after finishing it) would throw; and
        // even without the constraint, N identical "push this session" items
        // are N round trips that all do the same thing.
        try db.execute(sql: "DELETE FROM outbox WHERE idempotency_key = ?", arguments: [key])
        var item = OutboxItem(
            kind: SyncKind.sessionUpsert,
            payload: try OnyxJSON.encoder.encode(SessionRef(sessionId: sessionId)),
            idempotencyKey: key
        )
        try item.insert(db)
    }
}
