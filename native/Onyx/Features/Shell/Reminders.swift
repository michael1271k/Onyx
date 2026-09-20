import Foundation
import GRDB
import OnyxCore
import OnyxData
import UserNotifications

// ─────────────────────────────────────────────────────────────────────────────
// THE TWO THINGS THAT ONLY GET LOGGED IF SOMETHING ASKS.
//
// Every other figure in this app arrives on its own: the watch files the steps,
// the scale files the weight, the logger files the sets. Two do not. A fatigue
// rating is a person answering a question about themselves, and the tape is a
// person fetching a tape — and the weekly audit keeps finding the same two
// gaps, a waking slot on the Sunday and the whole of the Saturday, and a waist
// column with one reading a fortnight in it.
//
// ── WHY A WEEK OF ONE-SHOTS AND NOT A REPEATING TRIGGER ──────────────────────
// A repeating `UNCalendarNotificationTrigger` fires forever and cannot be told
// that today's rating is already in — iOS gives no hook to cancel one instance
// of a repeat, and there is no background refresh on a free developer account
// (`native/README.md`) to do it from. So a daily repeat would nag three times a
// day on the days the athlete was diligent, which is the fastest way to have
// notifications turned off altogether.
//
// One-shots for the coming week instead, re-armed on every foreground and
// skipping every slot already answered. Twenty-two pending notifications
// against iOS's limit of sixty-four.
//
// ponytail: the week is the ceiling. Go seven days without opening the app and
// the reminders run out — which is a person who has stopped logging anyway, and
// the alternative is a repeat that cannot be silenced.
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
enum OnyxReminders {

    /// The toggle, in `UserDefaults`. Off until the athlete turns it on: an app
    /// that asks for notification permission at launch is an app that gets
    /// "Don't Allow", and then nothing here can ever run.
    static let enabledKey = "onyx.reminders.enabled"

    /// Everything this file schedules carries the prefix, so a refresh can
    /// clear its own pending requests without touching anyone else's.
    private static let prefix = "onyx.reminder."

    /// How many days ahead to arm.
    private static let horizonDays = 7

    /// When each fatigue slot is worth asking about. The slot NAMES are
    /// `WeeklyExport.fatigueLabels`' own — the same strings `fatigue_logs.slot`
    /// stores after `Fatigue.normalizeSlot`, so "already answered" is a
    /// straight comparison and not a mapping.
    private static let fatigueTimes: [String: (hour: Int, minute: Int)] = [
        "Waking": (9, 0),
        "Midday": (14, 0),
        "Before training": (17, 0),
        "After training": (20, 30),
        "Night": (21, 30),
    ]

    /// Thursday, in `Calendar`'s 1 = Sunday numbering, at eight.
    private static let waistWeekday = 5
    private static let waistHour = 8

    // MARK: - Permission

    /// Ask, and report what the athlete said. Called from the toggle and
    /// nowhere else.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    // MARK: - Scheduling

    /// Re-arm the coming week. Safe to call on every foreground: it clears its
    /// own pending requests first, so nothing accumulates and nothing doubles.
    static func refresh(
        database: AppDatabase, userId: String, now: Date = Date(), calendar: Calendar = .current
    ) {
        let centre = UNUserNotificationCenter.current()
        guard UserDefaults.standard.bool(forKey: enabledKey) else { cancelAll(); return }

        let today = LogicalDay.iso(now, calendar: calendar)
        let horizon = ISODate.addDays(today, horizonDays - 1) ?? today

        // One read for both questions. A reminder is not worth a second
        // transaction, and asking twice could see two different days.
        let plan = try? database.read { db -> Plan in
            let answered = try FatigueLogRow
                .filter(Column("user_id") == userId && Column("date") >= today && Column("date") <= horizon)
                .fetchAll(db)
                .reduce(into: Set<String>()) { $0.insert("\($1.date)|\($1.slot)") }
            let waisted = try DailyLogRow
                .filter(Column("user_id") == userId && Column("date") >= today && Column("date") <= horizon)
                .fetchAll(db)
                .reduce(into: Set<String>()) { out, row in if row.waistCm != nil { out.insert(row.date) } }
            return Plan(answered: answered, waisted: waisted, context: nil)
        }
        // `scheduleContext(userId:today:)` is the app target's public door onto
        // the plan — the same one Today, the era picker and the session
        // analysis read through. Its own read; a reminder is not worth holding
        // a transaction open across two questions.
        guard var plan else { return }
        plan.context = try? database.scheduleContext(userId: userId, today: today)

        /* The AWAIT form, not the completion one. `getPendingNotificationRequests`
           hands its array back on a queue of its own, and under Swift 6 that is
           a region this actor cannot send `plan` into — the async spelling
           keeps the whole sequence on the main actor, which is also the only
           way the clear and the re-arm cannot interleave with a second
           foreground. */
        let armed = plan
        Task { @MainActor in
            let pending = await centre.pendingNotificationRequests()
            centre.removePendingNotificationRequests(
                withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            for request in requests(plan: armed, from: today, now: now, calendar: calendar) {
                try? await centre.add(request)
            }
        }
    }

    static func cancelAll() {
        let centre = UNUserNotificationCenter.current()
        Task { @MainActor in
            let pending = await centre.pendingNotificationRequests()
            centre.removePendingNotificationRequests(
                withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        }
    }

    // MARK: - The week's requests

    private struct Plan: Sendable {
        /// `"2026-09-20|Waking"` for every rating already given.
        var answered: Set<String>
        /// Dates whose `daily_logs` row already carries a waist.
        var waisted: Set<String>
        /// The plan, for the day type. Nil when it could not be resolved, and
        /// then every day is asked its REST-day slots: waking, midday, night.
        /// Waking is on both lists, which is the slot the audit keeps finding
        /// empty, so the fallback still covers the reported gap.
        var context: ScheduleContext?
    }

    private static func requests(
        plan: Plan, from today: String, now: Date, calendar: Calendar
    ) -> [UNNotificationRequest] {
        var out: [UNNotificationRequest] = []
        for offset in 0..<horizonDays {
            guard let date = ISODate.addDays(today, offset) else { continue }
            /* THE DAY'S OWN SLOTS. A training day is asked before and after the
               session; a rest day at midday and at night. Asking a rest day
               "how did the session feel" is a question with no answer, and the
               export would have nowhere to file the reply. */
            let training = plan.context.map { Schedule.isTrainingDayIn($0, date) } ?? false
            for slot in WeeklyExport.fatigueLabels(isTrainingDay: training) {
                guard !plan.answered.contains("\(date)|\(slot)"),
                      let time = fatigueTimes[slot],
                      let fire = at(date, hour: time.hour, minute: time.minute, calendar: calendar),
                      fire > now
                else { continue }
                out.append(request(
                    id: "\(prefix)fatigue.\(date).\(slot)",
                    title: "\(slot) check-in",
                    body: "One tap on Pulse — the week reads \(slot.lowercased()) as a gap otherwise.",
                    fire: fire, calendar: calendar))
            }
            // ── THE TAPE, ON THE DAY IT IS TAKEN ────────────────────────────
            // One weekday, because a waist read on a different day of the week
            // is a different measurement: the tape moves with the gut, and the
            // gut moves with the last two meals. Thursday is the athlete's own
            // day; a Thursday that already has a reading is not reminded.
            guard let day = ISODate.dayNumber(date) else { continue }
            let weekday = ISODate.weekday(dayNumber: day) + 1
            if weekday == waistWeekday, !plan.waisted.contains(date),
               let fire = at(date, hour: waistHour, minute: 0, calendar: calendar), fire > now {
                out.append(request(
                    id: "\(prefix)waist.\(date)",
                    title: "Waist",
                    body: "Tape measure, beside the weigh-in. It is the one body figure nothing measures for you.",
                    fire: fire, calendar: calendar))
            }
        }
        return out
    }

    private static func request(
        id: String, title: String, body: String, fire: Date, calendar: Calendar
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // A one-shot: `repeats: false`, so an answered slot simply is not
        // re-armed on the next foreground and the reminder disappears.
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        return UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    /// A wall-clock instant on an ISO day, in the athlete's own calendar.
    private static func at(_ dateISO: String, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        let parts = dateISO.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute))
    }
}
