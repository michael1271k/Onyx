import Foundation

/// Reads a day out of HealthKit and writes it into the store.
///
/// ── THE HOP THAT DISAPPEARED ────────────────────────────────────────────────
/// The web path was: plugin → JSON over the web-shell bridge → `syncDay` in the
/// browser → `POST /api/ingest` with a bearer token → `ingestDailyLog` on a
/// Netlify function in UTC → six Supabase round trips → the phone refetches what
/// it just sent. The function ran in UTC and could not know the user's day, so
/// `logicalTodayForUser` existed to read a timezone out of `user_goals` to work
/// out what "today" meant on a device it was not running on.
///
/// This runs on the device. The day is the device's own calendar day, the write
/// is local and instant, and the upload is the outbox's problem.
public actor HealthSync {

    let database: AppDatabase
    let reader: any HealthReading
    let userId: String

    public init(database: AppDatabase, reader: any HealthReading, userId: String) {
        self.database = database
        self.reader = reader
        self.userId = userId
    }

    /// Ask for permission. Safe to call on every launch: after the first, iOS
    /// resolves it without showing anything.
    @discardableResult
    public func requestAuthorization() async throws -> Bool {
        try await reader.requestAuthorization(read: HealthCatalogue.readTypes)
    }

    /// Today's running total, then yesterday's finalised one.
    ///
    /// ── THE ORDER IS THE POINT ──────────────────────────────────────────────
    /// Today first because it is the visible day. Yesterday second because it
    /// self-corrects whatever Apple recorded after the previous evening's last
    /// sync — a walk before bed after a 21:00 sync — and nothing on screen is
    /// waiting for it.
    ///
    /// Sequential, not concurrent. Two adjacent days' NIGHT WINDOWS are
    /// adjacent, and the sleep write replaces the night it finds; running them
    /// at once is the shape of the bug that used to make the dashboard flip back
    /// to "Awaiting Sleep Data" after a pull-to-refresh.
    @discardableResult
    public func syncRecent(now: Date = Date(), calendar: Calendar = .current) async throws -> [IngestReport] {
        let today = LogicalDayISO.string(now, calendar: calendar)
        var out = [try await sync(day: today, isToday: true, now: now, calendar: calendar)]
        let yesterday = NightWindow.previousDay(today)
        out.append(try await sync(day: yesterday, isToday: false, now: now, calendar: calendar))
        return out
    }

    /// One local day.
    ///
    /// `isToday` caps the window at `now` — a live running total — where a past
    /// day reads its whole midnight-to-midnight span. The bound matters for the
    /// `sum` metrics: querying a future window is not an error, it just returns
    /// the same number more slowly.
    @discardableResult
    public func sync(
        day dateISO: String, isToday: Bool, now: Date = Date(), calendar: Calendar = .current
    ) async throws -> IngestReport {
        guard reader.isAvailable else { return IngestReport() }
        guard let start = Self.localMidnight(dateISO, calendar: calendar) else { return IngestReport() }
        let end = isToday
            ? now
            : (calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))

        var payload = HealthPayload(date: dateISO)
        for metric in HealthCatalogue.metrics {
            // One metric that throws is one metric that is absent. A device
            // without a wrist temperature sensor must not cost the day its
            // steps, and `quantity` already treats "no samples" as `nil` —
            // this catches the rarer case where the store itself refuses.
            let raw = try? await reader.quantity(
                metric.identifier, reduce: metric.reduce, start: start, end: end
            )
            if let value = HealthCatalogue.round(raw, reduce: metric.reduce, scale: metric.scale) {
                payload[metric.key] = value
                /* ── AND, FOR A DIETARY MICRO, WHO WROTE IT ──────────────────
                   Only the micros, because only they have the problem: the
                   calcium that arrived at ~3,100 mg on seventeen days came from
                   the daily ingest with no way to name the contributor, and
                   `nutrition_entries` stores an aggregate that cannot be taken
                   apart afterwards. Steps and heart rate have no such question.

                   Same statistics query shape, one extra round trip per micro
                   per day — nine of them — and it is skipped entirely on a
                   reader that does not implement it (the default returns
                   empty). A failure here costs the attribution and never the
                   reading. */
                if HealthCatalogue.microKeys.contains(metric.key), metric.reduce == .sum {
                    let bySource = (try? await reader.quantityBySource(
                        metric.identifier, start: start, end: end
                    )) ?? [:]
                    if bySource.count > 0 { payload.microSources[metric.key] = bySource }
                }
            }
        }

        // Sleep has its own window — the night that ENDS on this morning — and
        // its own aggregation. It is not a metric of the calendar day.
        if let night = NightWindow.range(dateISO) {
            let samples = (try? await reader.sleepSamples(start: night.from, end: night.to)) ?? []
            payload.sleep = Sleep.aggregate(samples)
        }

        // ── OVERNIGHT HRV (readiness v9) ────────────────────────────────────
        // The watch takes an SDNN reading every few hours and during sleep,
        // and the daytime ones carry the day — a walk, a coffee, a meeting.
        // The readings inside the night's bed window are the ones that track
        // recovery (Plews 2013), so when the night is known the day's `hrv`
        // is their mean. A statistics query, like every other metric, so the
        // iPhone/Watch dedupe is Apple's. No night, or no samples inside it,
        // and the calendar-day mean stands, flagged as such.
        //
        // ── A HAND-EDITED NIGHT IS READ OVER THE STORED WINDOW (E2) ─────────
        // `writeSleep` already declines HealthKit's night when the user has
        // trimmed it, but the HRV mean was still taken over HealthKit's bed
        // window — so the next sync quietly re-widened the one number the trim
        // was supposed to move. The stored window wins here for the same
        // reason it wins there.
        let stored = try? database.manualNightWindow(userId: userId, date: dateISO)
        let hrvWindow: (start: Date, end: Date)? = stored
            ?? payload.sleep.flatMap { slept in
                guard let a = slept.bedStart, let b = slept.bedEnd, b > a else { return nil }
                return (a, b)
            }
        if let (bedStart, bedEnd) = hrvWindow,
           let overnight = try? await reader.quantity(HealthCatalogue.hrvIdentifier, reduce: .average, start: bedStart, end: bedEnd),
           let value = HealthCatalogue.round(overnight, reduce: .average) {
            payload[.hrv] = value
            payload.hrvOvernight = true
        }

        // Nothing in HealthKit's continuations is cancellation-aware, so the
        // 32-metric loop above runs to completion even after `signOut` cancels
        // this task. Checking HERE is what stops the write landing — in the
        // local store and then the outbox — under the id of the user who just
        // signed out.
        try Task.checkCancellation()
        return try database.ingest(payload, userId: userId, now: now)
    }

    // MARK: - Editing a night (E2)

    /// Re-window the night that ended on the morning of `dateISO`.
    ///
    /// Strategy A when the store has samples inside the new window — the
    /// stages re-sum from what the watch recorded — and strategy B when it has
    /// none (an unavailable store, or a night the watch never sampled)
    /// (`SleepTrim`, proportional). Overnight HRV is re-read over the NEW
    /// window and written to `daily_logs.hrv_ms`; no samples there leaves the
    /// stored figure alone. The row is written under the sleep sentinel, so
    /// `sync` cannot re-widen it. The caller runs the rescore cascade —
    /// `AppEnvironment.rescore(from: dateISO, reason: .sleepEdit)` — which is
    /// deliberately not this actor's to schedule.
    @discardableResult
    public func editSleepWindow(
        date dateISO: String, start: Date, end: Date, onset: Date? = nil, now: Date = Date()
    ) async throws -> SleepSessionRow {
        var night: SleepNight?
        var hrv: Double?
        if reader.isAvailable {
            // NOT `try?`: a store that throws here would silently turn strategy A
            // into B and stamp the proportional guess under the sentinel, where
            // the next sync could never correct it. The edit is user-initiated;
            // a thrown error is the honest outcome.
            let samples = try await reader.sleepSamples(start: start, end: end)
            night = Sleep.aggregate(samples, within: start, end)
            if let overnight = try? await reader.quantity(HealthCatalogue.hrvIdentifier, reduce: .average, start: start, end: end) {
                hrv = HealthCatalogue.round(overnight, reduce: .average)
            }
        }
        try Task.checkCancellation()
        return try database.editSleepWindow(
            userId: userId, date: dateISO, start: start, end: end, night: night, hrvMs: hrv, onset: onset, now: now
        )
    }

    /// Local midnight for a `yyyy-MM-dd`, in the device's own calendar — which
    /// is the whole reason this is on the device and not on a server.
    static func localMidnight(_ dateISO: String, calendar: Calendar) -> Date? {
        let parts = dateISO.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
