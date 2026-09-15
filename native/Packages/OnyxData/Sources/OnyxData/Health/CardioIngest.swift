import Foundation
import OnyxCore

/// What one automatic pass did.
///
/// Two counters and not a bool, because they are two different pieces of news.
/// `inserted` is a bout the ledger did not have — the thing the feature exists
/// for. `filled` is a bout it already had, whose blanks Health could answer:
/// the heart rate and the ascent nobody types, added to a row somebody did.
/// A toast that said "3 workouts synced" for three rows it merely annotated
/// would be claiming credit for work it did not do.
public struct CardioIngestReport: Sendable, Equatable {
    public var inserted = 0
    public var filled = 0

    public init(inserted: Int = 0, filled: Int = 0) {
        self.inserted = inserted
        self.filled = filled
    }

    public var isEmpty: Bool { inserted == 0 && filled == 0 }

    static func + (a: Self, b: Self) -> Self {
        Self(inserted: a.inserted + b.inserted, filled: a.filled + b.filled)
    }
}

public extension HealthSync {

    /// Every mapped cardio bout Apple Health holds for today and yesterday,
    /// into the ledger, without being asked.
    ///
    /// ── WHY THIS EXISTS AT ALL ──────────────────────────────────────────────
    /// Every piece of this was already built and none of it ran on its own.
    /// `HealthKitReader.workouts` reads the bouts, `WorkoutSample` carries the
    /// distance, energy, heart rate and ascent, `CardioImport.matchingRow` is a
    /// golden-tested duplicate rule, and `cardio_logs` has a column for each
    /// figure. The only thing standing between a walk and the ledger was a
    /// person remembering to open a sheet and tap a card — for a bout their
    /// watch had already recorded, in an app on the same phone.
    ///
    /// ── TODAY AND YESTERDAY, FOR `syncRecent`'s REASON ──────────────────────
    /// Today because it is the visible day; yesterday because Apple's own
    /// dedupe between a watch and a phone can land a bout minutes to hours
    /// after it ended, and an evening walk synced at 21:00 is finalised well
    /// after the last sync of the day that contains it. Two days is the same
    /// window `syncRecent` uses for the daily metrics and for the same reason.
    ///
    /// ── WHAT IT REFUSES TO DO ───────────────────────────────────────────────
    /// Overwrite. `CardioImport.merge` only ever fills a blank — see its own
    /// doc comment for why an unattended process must never replace a figure a
    /// person typed. A matched row whose blanks Health cannot fill is not
    /// written at all, so a launch on a day with nothing new costs one read and
    /// no rows.
    ///
    /// Errors are swallowed per bout, not per pass: a single malformed sample
    /// must not cost the other four their import, and Health being unavailable
    /// or denied is an empty report rather than a throw — the same courtesy
    /// `syncRecent` extends, and for the same reason. There is nothing a person
    /// can do differently about "denied" and "no bouts recorded".
    @discardableResult
    func syncCardioBouts(now: Date = Date(), calendar: Calendar = .current) async throws -> CardioIngestReport {
        let today = LogicalDayISO.string(now, calendar: calendar)
        let yesterday = NightWindow.previousDay(today)
        var out = CardioIngestReport()
        for day in [today, yesterday] {
            out = out + (try await ingestCardio(day: day, now: now, calendar: calendar))
        }
        return out
    }

    /// One local day's bouts.
    ///
    /// The availability guard is HERE and not on `syncCardioBouts`, because
    /// this is the function every caller routes through — the day loop above,
    /// and anything that later wants one specific date. A guard on the loop
    /// alone leaves a store that refuses to answer looking like a store with no
    /// bouts on it, for every caller but one.
    @discardableResult
    func ingestCardio(day dateISO: String, now: Date = Date(), calendar: Calendar = .current) async throws -> CardioIngestReport {
        guard reader.isAvailable else { return CardioIngestReport() }
        guard let start = HealthSync.localMidnight(dateISO, calendar: calendar),
              let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return CardioIngestReport() }

        let found = (try? await reader.workouts(start: start, end: end)) ?? []
        // `isLifting` is excluded for the same reason the sheet excludes it: a
        // strength session is a `workout_sessions` row with its own sets, and
        // filing it as cardio would double-count its energy against the day.
        //
        // ── AND THE BOUT BELONGS TO THE DAY IT STARTED IN (W1) ───────────────
        // `reader.workouts` deliberately has no `.strictStartDate`, so a walk
        // from 23:40 to 00:20 OVERLAPS two days and is returned by both of this
        // pass's queries. It used to be filed under each of them: two rows, two
        // dates, one physical walk — the duplicate no same-day rule can see,
        // and the one the new `(user_id, hk_uuid)` unique index would reject on
        // push, jamming the row in the outbox forever.
        //
        // The window is already computed above, so the day a bout belongs to is
        // the day its START falls in. That is the same instant `created_at`
        // already claims for an imported row, so the row and its date now agree.
        //
        // ponytail: a bout that started before the two-day window and ran into
        // it is no longer imported. It was only ever imported under the wrong
        // date, and `syncCardioBouts` scans two days — a bout that started on
        // the third is out of scope by the same rule as every other.
        let bouts = found.filter {
            !$0.isLifting && $0.cardioKind != nil && $0.start >= start && $0.start < end
        }
        if bouts.isEmpty { return CardioIngestReport() }

        var stored = try database.cardioRows(userId: userId, date: dateISO)
        var out = CardioIngestReport()

        for bout in bouts {
            guard let kind = bout.cardioKind else { continue }
            // LOWERCASED, every time it is rendered. `UUID.uuidString` is
            // uppercase and Postgres renders a uuid lowercase; SQLite compares
            // TEXT byte for byte. A key written one way and pulled back the
            // other stops matching itself, and the duplicate returns — which is
            // the whole defect, wearing a different hat. `UserIdCasingTests`
            // greps the tree for exactly this.
            let key = bout.uuid.uuidString.lowercased()
            let match = CardioImport.matchingRow(
                hkUuid: key,
                kind: kind, start: bout.start, durationMin: bout.durationMin,
                date: dateISO, in: stored.map(CardioImport.Existing.init)
            )

            // TOTAL energy is a second read and only worth making when the bout
            // has an active figure to add it to: resting alone is not the cost
            // of a walk, and a total that silently equalled active would be a
            // claim that lying down for forty minutes is free.
            var totalKcal: Double?
            if let active = bout.activeKcal,
               let resting = try? await reader.quantity(
                   HealthCatalogue.restingEnergyIdentifier, reduce: .sum, start: bout.start, end: bout.end
               ) {
                totalKcal = (active + resting).rounded()
            }

            let incoming = CardioImport.Fields(
                distanceM: bout.distanceM.map { $0.rounded() },
                durationMin: (bout.durationMin * 10).rounded() / 10,
                activeKcal: bout.activeKcal.map { $0.rounded() },
                totalKcal: totalKcal,
                avgHr: bout.avgHr.map { $0.rounded() },
                elevationM: bout.elevationM.map { $0.rounded() }
            )

            guard let match else {
                // ── `created_at` IS THE BOUT'S START ON AN IMPORTED ROW ─────
                // Not the instant of the import. `CardioImport.matchingRow`
                // reads it as a start on the next pass, and this is the field
                // the export prints as `start_time`. Writing `now` here would
                // make every automatic import look like it happened at launch
                // and make the duplicate rule match the wrong bout.
                let row = CardioLogRow(
                    id: newOnyxID(), userId: userId, date: dateISO, kind: kind,
                    distanceM: incoming.distanceM, durationMin: incoming.durationMin,
                    fromHealthkit: true, createdAt: bout.start,
                    activeKcal: incoming.activeKcal, totalKcal: incoming.totalKcal,
                    avgHr: incoming.avgHr, elevationM: incoming.elevationM,
                    // The key, from now on. Every later pass matches this row
                    // outright instead of guessing at its start.
                    hkUuid: key
                )
                try Task.checkCancellation()
                try database.addCardio(row)
                stored.append(row)
                out.inserted += 1
                continue
            }

            guard let index = stored.firstIndex(where: { $0.id == match.id }) else { continue }
            let before = CardioImport.Fields(stored[index])
            let after = CardioImport.merge(stored: before, incoming: incoming)

            // ── THE ROW THE WINDOW FOUND GETS THE KEY (W1) ──────────────────
            // A row imported before `hk_uuid` existed, or typed by hand, was
            // matched by the five-minute window. Stamping the bout's uuid on it
            // retires that guess for this row forever — the next pass matches it
            // outright. Only ever onto a BLANK: two bouts can fuzzy-match one
            // hand-typed row, and letting the second overwrite the first's key
            // would rewrite the row on every launch for the rest of the day.
            let adoptsKey = stored[index].hkUuid == nil

            // A write that changes nothing is a row version, an outbox item and
            // a push for no reason. Most launches land here.
            if after == before && !adoptsKey { continue }

            var row = stored[index]
            row.apply(after)
            if adoptsKey { row.hkUuid = key }
            try Task.checkCancellation()
            try database.addCardio(row)
            stored[index] = row
            // ── AND ADOPTING IT IS NOT NEWS ─────────────────────────────────
            // `filled` is what the toast says out loud: "a bout you logged
            // gained its heart rate and ascent". A key nobody can see on a
            // screen gained nothing a person would recognise, so a pass that
            // only stamped uuids reports an EMPTY report and puts up no toast.
            if after != before { out.filled += 1 }
        }

        return out
    }
}

// MARK: - Row ↔ Fields

extension CardioImport.Fields {
    init(_ row: CardioLogRow) {
        self.init(
            distanceM: row.distanceM,
            durationMin: row.durationMin,
            // Pre-migration rows carry the active figure in `kcal` alone, and a
            // merge that read only `active_kcal` would see a blank and fill it
            // with Health's — overwriting by the back door, which is the one
            // thing this path must not do.
            activeKcal: row.activeKcal ?? row.kcal,
            totalKcal: row.totalKcal,
            avgHr: row.avgHr,
            elevationM: row.elevationM,
            inclinePct: row.inclinePct
        )
    }
}

extension CardioLogRow {
    mutating func apply(_ fields: CardioImport.Fields) {
        distanceM = fields.distanceM
        durationMin = fields.durationMin
        activeKcal = fields.activeKcal
        totalKcal = fields.totalKcal
        avgHr = fields.avgHr
        elevationM = fields.elevationM
        inclinePct = fields.inclinePct
    }
}

extension CardioImport.Existing {
    init(_ row: CardioLogRow) {
        self.init(
            id: row.id, date: row.date, kind: row.kind, durationMin: row.durationMin,
            createdAt: row.createdAt, fromHealthkit: row.fromHealthkit ?? false,
            hkUuid: row.hkUuid
        )
    }
}
