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

    /// What all of the above were called before the app was renamed Onyx (W2).
    ///
    /// The container, the folder and the file all changed name in one commit,
    /// and a store the previous build wrote is a store with real unsynced sets
    /// in it. `adoptLegacyStore` renames it forward rather than leaving it
    /// stranded beside an empty new one.
    ///
    /// In practice the App Group half is dead code today: the entitlement has
    /// never been signed (it needs the paid Developer Program — Gate 0), so
    /// every store that exists is the Application Support fallback.
    ///
    /// ── AND IT STAYS DEAD AFTER GATE 0 UNLESS THE ENTITLEMENT SAYS SO ───────
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` returns non-nil
    /// only for a group id listed in the BINARY's entitlements, and
    /// `Onyx.entitlements` lists `group.app.onyx.health` alone. So provisioning
    /// the new group does not wake this branch: it returns nil, the `if let` is
    /// skipped, and nothing is adopted or lost — there is simply nothing there
    /// to adopt, because no build ever wrote to the legacy group either.
    ///
    /// Do not read this as a safety net. If a build ever DOES ship having
    /// written to `group.app.helix.health`, that id has to go into the
    /// entitlements array in the same commit, or this cannot see it.
    static let legacyAppGroupID = "group.app.helix.health"
    static let legacyFolderName = "Helix"
    static let legacyFileName = "helix.sqlite"

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

    /// Rename and relocate any store an earlier build left behind. APP ONLY.
    ///
    /// Call once, at launch, BEFORE opening the store — never from an
    /// extension. A store that predates the container is moved across with its
    /// WAL and SHM: a pool opened on the sqlite alone would replay a stale
    /// checkpoint and the last unsynced sets would be gone.
    ///
    /// Idempotent. Every step is a "move if the source exists and the
    /// destination does not", so a second call after a successful first is a
    /// series of no-ops.
    public static func adoptLegacyStores() {
        let appSupport = URL.applicationSupportDirectory.appending(path: "Onyx", directoryHint: .isDirectory)
        // The rename first, in whichever container the store is actually in.
        // Application Support is the one that matters today; the App Group is
        // reachable only once the entitlement is signed, and `containerURL`
        // answers nil until it is, which makes that half a no-op rather than a
        // branch to remember.
        adoptLegacyStore(into: appSupport, from: URL.applicationSupportDirectory.appending(path: legacyFolderName, directoryHint: .isDirectory))
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return }
        let shared = container.appending(path: "Onyx", directoryHint: .isDirectory)
        adoptLegacyStore(into: shared, from: container.appending(path: legacyFolderName, directoryHint: .isDirectory))
        if let legacyContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: legacyAppGroupID) {
            adoptLegacyStore(into: shared, from: legacyContainer.appending(path: legacyFolderName, directoryHint: .isDirectory))
        }
        moveStoreIfNeeded(from: appSupport, to: shared)
    }

    /// `Helix/helix.sqlite` → `Onyx/onyx.sqlite`, once.
    static func adoptLegacyStore(into new: URL, from old: URL) {
        move(from: old, named: legacyFileName, to: new, named: fileName)
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
        try writer.read { db in
            for table in ["profiles", "user_goals", "daily_logs"] {
                if let id = try String.fetchOne(db, sql: "SELECT user_id FROM \(table) LIMIT 1") { return id }
            }
            return nil
        }
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
        //   · `exercises.slug` — the legacy `helix5-…` id as an ALIAS column,
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

        return migrator
    }
}

extension AppDatabase {

    /// Repoint legacy slug-stamped sets at the catalogue row they belong to.
    ///
    /// Extracted from `v23.catalogueIds` so it can be run against a database
    /// whose rows are already in the mixed state a real device is in — a
    /// migration that only ever runs on a fresh schema is a migration nothing
    /// has tested.
    static func adoptCatalogueIds(_ db: Database) throws {
        // By the server's own alias for the legacy id, pulled down with the row.
        try db.execute(sql: """
            UPDATE workout_sets
               SET exercise_id = (
                   SELECT e.id FROM exercises e WHERE e.slug = workout_sets.exercise_id
               )
             WHERE exercise_id LIKE 'helix5-%'
               AND EXISTS (
                   SELECT 1 FROM exercises e WHERE e.slug = workout_sets.exercise_id
               )
            """)
        // Then by the SHADOW rows this app used to insert so a slug-stamped set
        // had something to point at: their id IS the slug and their name is the
        // movement, so the real row is the other one carrying the same name.
        try db.execute(sql: """
            UPDATE workout_sets
               SET exercise_id = (
                   SELECT c.id FROM exercises c
                     JOIN exercises legacy ON legacy.id = workout_sets.exercise_id
                    WHERE lower(trim(c.name)) = lower(trim(legacy.name))
                      AND c.id <> legacy.id
                    LIMIT 1
               )
             WHERE exercise_id LIKE 'helix5-%'
               AND EXISTS (
                   SELECT 1 FROM exercises c
                     JOIN exercises legacy ON legacy.id = workout_sets.exercise_id
                    WHERE lower(trim(c.name)) = lower(trim(legacy.name))
                      AND c.id <> legacy.id
               )
            """)
    }
}

// MARK: - Reads

extension AppDatabase {
    /// Sessions for a day, newest first.
    public func sessions(on date: String) throws -> [WorkoutSession] {
        try writer.read { db in
            try WorkoutSession
                .filter(Column("date") == date)
                .order(Column("started_at").desc)
                .fetchAll(db)
        }
    }

    /// Live-updating sets for a session, in logged order.
    ///
    /// A `ValueObservation` rather than a fetch: the logger writes a set and the
    /// list redraws, with no refresh call, no invalidation key and no chance of
    /// the two disagreeing.
    public func observeSets(sessionId: String) -> ValueObservation<ValueReducers.Fetch<[WorkoutSet]>> {
        ValueObservation.tracking { db in
            try WorkoutSet
                .filter(Column("session_id") == sessionId)
                // `fold_order` is the fold's arrival tiebreak, carried into the
                // table so two devices render a duplicated set_index in the
                // same order. Sorting on set_index alone leaned on rowid order,
                // which SQLite does not promise.
                .order(Column("set_index"), Column("fold_order"))
                .fetchAll(db)
        }
    }

    /// One session by id. The drainer's read: it pushes the row as it stands
    /// now, never a copy captured when the queue item was written.
    public func session(id: String) throws -> WorkoutSession? {
        try writer.read { db in try WorkoutSession.fetchOne(db, key: id) }
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
    public func sets(sessionId: String) throws -> [WorkoutSet] {
        try writer.read { db in
            try WorkoutSet
                .filter(Column("session_id") == sessionId)
                .order(Column("set_index"), Column("fold_order"))
                .fetchAll(db)
        }
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
    public func liveSession(dayKey: String, date: String) throws -> WorkoutSession? {
        try writer.read { db in
            try WorkoutSession
                .filter(Column("date") == date
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
    /// The caller should reach this on the FIRST WRITE and not on appearing.
    /// Called from `onAppear`, it leaves an empty session row behind every time
    /// the tab is opened and closed again.
    @discardableResult
    public func openSession(
        userId: String,
        dayKey: String,
        date: String,
        startedAt: Date = Date()
    ) throws -> WorkoutSession {
        if let live = try liveSession(dayKey: dayKey, date: date) { return live }
        return try writer.write { db in
            // Re-checked inside the transaction: the read above is not part of
            // it, and two writers (the phone and, at Wave 5, the watch) racing
            // on the same split would otherwise each create a row.
            if let live = try WorkoutSession
                .filter(Column("date") == date
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
    /// `attach` deliberately does not create a session row, so opening the
    /// logger and leaving costs nothing and needs none of this. What this is for
    /// is the session you started, logged a set into, and then realised was the
    /// wrong day — where closing it would leave a one-set workout in the history,
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
    public func discardSession(id: String) throws -> Bool {
        try writer.write { db in
            guard try WorkoutSession.fetchOne(db, key: id) != nil else { return false }

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
            return true
        }
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
    public func setSessionStart(id: String, startedAt: Date) throws {
        try writer.write { db in
            guard var session = try WorkoutSession.fetchOne(db, key: id) else { return }
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
        id: String, durationMin: Double? = nil, avgBpm: Int? = nil, caloriesBurned: Int? = nil,
        measured: Bool = true
    ) throws -> SessionEditing.Outcome? {
        guard durationMin != nil || avgBpm != nil || caloriesBurned != nil else { return nil }
        return try updateMetrics(
            sessionId: id, durationMin: durationMin, avgBpm: avgBpm, calories: caloriesBurned,
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
        try writer.write { db in
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
