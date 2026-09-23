import Foundation
import Observation
import OnyxCore
import OnyxData
import OnyxUI

/// What the Today screen reads and writes.
///
/// ── THE ARRANGEMENT IS A ROW; THE NUMBERS ARE A BUILD ────────────────────────
/// Two inputs. The layout is one `dashboard_layouts` row, streamed, so a
/// rearrangement made on the web lands here without a refresh. The feed —
/// snapshot, coach, week-so-far — is rebuilt after any commit to the mirror
/// (debounced, off the main actor), because it reads two dozen tables and a
/// `ValueObservation` over all of them would re-run on every keystroke anyway.
///
/// Every edit goes through `Dashboard.*` (the vectored algebra) and then
/// `saveDashboardLayout`; the stream echoes the same value back, so the grid
/// never shows an arrangement the database does not hold.
@MainActor
@Observable
final class TodayModel {

    private let database: AppDatabase
    let userId: String

    private(set) var layout: DashboardLayout = Dashboard.defaultLayout(.phone)
    /// Whether the layout on this object came from the STREAM rather than from
    /// the field initialiser above.
    ///
    /// ── THE LAYOUT WAS NEVER LOST; IT WAS OVERWRITTEN (W7, F9) ──────────────
    /// `dashboard_layouts` has been synced both ways, keyed `user_id`, since
    /// the grid shipped — so "the dashboard forgets itself on a reinstall" was
    /// never a missing write. It is this: the field above starts at
    /// `Dashboard.defaultLayout(.phone)` because the screen has to draw
    /// something before the first `ValueObservation` yield, and the first yield
    /// is a database round trip AFTER the first frame. Any edit made in that
    /// window — and an edit is one drag, which `Arrangeable` will happily start
    /// the moment the grid appears — called `apply(_:)` on a layout derived
    /// from the DEFAULT, and `saveDashboardLayout` wrote it over the real row
    /// and enqueued the outbox upsert. The pull then arrived and was
    /// immediately correct about a row the app had just destroyed.
    ///
    /// The gate is one flag and it is on the WRITE, not on the read: drawing a
    /// default before the row lands is right, and saving one is never right.
    private var hasLoaded = false
    private(set) var feed: TodayFeed?
    private(set) var failure: String?

    /// Jiggle mode. Stacks stop rotating, taps stop opening sheets.
    var editing = false
    /// Whether the scene is in the foreground — the other reason a stack stops.
    ///
    /// Coming back to the foreground is also when the clock is re-read for the
    /// relevance order (§W6-B.3): a phone left on the Today tab from 11:00 to
    /// 18:00 crossed a band without a single yield from the layout stream, and
    /// this is the event that says the reader is looking again.
    var isActive = true {
        didSet { if isActive, !oldValue { layout = ranked(stored) } }
    }
    var sheet: TodaySheet?

    /// A preview hands in a feed and skips the builder — no mirror to read.
    private let seededFeed: TodayFeed?

    init(database: AppDatabase, userId: String, feed: TodayFeed? = nil, layout: DashboardLayout? = nil) {
        self.database = database
        self.userId = userId
        self.seededFeed = feed
        self.feed = feed
        // A seeded layout is a load: the shot harness and the previews hand one
        // in and then arrange it, and there is no stream behind them to yield.
        if let layout { self.layout = layout; hasLoaded = true }
    }

    /// The clock's order, applied on top — and only for a grid nobody has
    /// arranged. `Dashboard.relevanceOrdered` is where the rule lives and why;
    /// this is the one place the app tells it what time it is.
    ///
    /// Ranking on the way IN rather than on the way out to the grid, so a drag
    /// operates on the cards the reader is actually looking at: the drag writes
    /// a real `updatedAt`, which retires the ranking from that moment on, and
    /// what gets saved is the arrangement they made from what they saw.
    /// The layout as the STORE holds it, before any ranking.
    ///
    /// Ranking is not idempotent: the cards it does not name keep their
    /// CURRENT relative order, so ranking an already-ranked grid at a new hour
    /// gives a different answer from ranking the stored one. A phone left open
    /// from 11:00 to 18:00 and one relaunched at 18:00 would land on two
    /// different grids for the same row and the same clock.
    private var stored = Dashboard.defaultLayout(.phone)

    private func ranked(_ layout: DashboardLayout) -> DashboardLayout {
        Dashboard.relevanceOrdered(layout, minuteOfDay: Self.minuteOfDay)
    }

    /// The clock, with a DEBUG door.
    ///
    /// `ONYX_CLOCK_MINUTE=420` in the launch environment pins it to 07:00.
    /// The morning and evening orders are the whole of §W6-B.3 and they are
    /// proved by two screenshots, which means the shot loop has to be able to
    /// ask for a band — and `simctl status_bar` moves the CLOCK IN THE BAR
    /// and not the one `Date()` answers. A launch variable and not a deep
    /// link, for the reason `ONYX_START_TAB` gives.
    static var minuteOfDay: Int {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["ONYX_CLOCK_MINUTE"], let minute = Int(raw) {
            return minute
        }
        #endif
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    // MARK: - Reading

    private var commitObserver: AnyObject?
    private var rebuild: Task<Void, Never>?

    func observe() async {
        if seededFeed == nil {
            refresh()
            commitObserver = database.onCommit { [weak self] in
                Task { @MainActor in self?.scheduleRebuild() }
            }
        }
        defer { commitObserver = nil; rebuild?.cancel() }
        do {
            for try await row in database.dashboardLayoutStream(userId: userId) {
                stored = row?.layout ?? Dashboard.defaultLayout(.phone)
                layout = ranked(stored)
                // A device with no row yields `nil` — which is a LOAD. The
                // athlete's first drag on a fresh install has to be savable,
                // and "the stream answered" is the fact the gate needs, not
                // "the answer was non-empty".
                hasLoaded = true
            }
        } catch {
            if !(error is CancellationError) {
                // ── SAY WHAT IT COSTS, NOT JUST WHAT FAILED ─────────────────
                // A read failure leaves `hasLoaded` false, and `apply` refuses
                // every edit while it is — correctly, because saving an
                // arrangement this device has not read IS the clobber. But the
                // old sentence described the read and left the consequence to
                // be discovered: tiles snap back from a drag and nothing on
                // screen connects that to this banner. `.task` re-runs
                // `observe()` on the next appearance, so leaving the tab and
                // coming back is the retry, and the sentence says so.
                failure = "The layout could not be read on this device, so the grid cannot be rearranged \u{2014} a change would overwrite the arrangement this phone has not managed to load. Leave the tab and come back to try again."
            }
        }
    }

    /// Rebuild now — pull-to-refresh and a return to the foreground.
    func refresh() {
        guard seededFeed == nil else { return }
        rebuild?.cancel()
        let builder = TodayFeedBuilder(database: database, userId: userId)
        rebuild = Task.detached(priority: .userInitiated) { [weak self] in
            let built = try? builder.build()
            guard !Task.isCancelled, let built else { return }
            await MainActor.run { self?.feed = built }
        }
    }

    private func scheduleRebuild() {
        rebuild?.cancel()
        rebuild = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    var entry: OnyxTileEntry {
        OnyxTileEntry(date: Date(), snapshot: feed?.snapshot)
    }

    /// The session behind today's Workout tile, when one actually landed.
    ///
    /// The LONGEST of the day's sessions, which is the one the tile's own
    /// figures describe — `WidgetSnapshotBuilder` takes duration and RPE from
    /// the same session, and a tap that opened the other one would be a page
    /// disagreeing with the tile that opened it.
    ///
    /// A synchronous read on the main actor, deliberately: it is one indexed
    /// row by date, it happens once per tap, and the alternative — carrying the
    /// id through the feed — makes every rebuild pay for a value only a tap
    /// ever needs.
    var todaySessionId: String? {
        guard feed?.snapshot.workout.logged == true else { return nil }
        let date = feed?.snapshot.date ?? LogicalDay.today()
        let sessions = (try? database.sessions(on: date, userId: userId)) ?? []
        return sessions.max { ($0.durationMin ?? 0) < ($1.durationMin ?? 0) }?.id
    }

    // MARK: - What the phone draws

    /// The slots with the faces the phone has, in grid order. A slot whose
    /// every face is web-only is skipped, not deleted — see `WidgetId.isNative`.
    var visibleSlots: [StackSlot] {
        Self.projectNative(layout.slots)
    }

    static func projectNative(_ slots: [StackSlot]) -> [StackSlot] {
        slots.compactMap { s in
            let items = s.items.filter(\.isNative)
            return items.isEmpty ? nil : StackSlot(id: s.id, size: s.size, items: items, linked: s.linked)
        }
    }

    /// The gallery: hidden, and drawable here.
    var gallery: [WidgetId] {
        Dashboard.hiddenWidgets(layout).filter(\.isNative)
    }

    // MARK: - Editing

    func move(_ fromId: String, to toId: String) {
        apply(Dashboard.moveSlot(layout, fromId: fromId, toId: toId))
    }

    func stack(_ fromId: String, onto toId: String) {
        apply(Dashboard.stackSlots(layout, fromId: fromId, ontoId: toId))
    }

    func canStack(_ fromId: String, onto toId: String) -> Bool {
        Dashboard.canStack(Dashboard.slot(layout, at: fromId), Dashboard.slot(layout, at: toId))
    }

    /// Every tile this one could be dropped onto, for the long-press menu.
    ///
    /// ── ONE RULE, TWO ROUTES ────────────────────────────────────────────────
    /// The menu and the drag-and-hold both ask `Dashboard.canStack`, so the two
    /// ways into a stack can never disagree about which pairs are legal — a menu
    /// with its own size test is a second rule that drifts the first time
    /// `canStack` changes. It reads `visibleSlots`, not `layout.slots`: a slot
    /// whose every face is web-only is not on this screen, and a menu row that
    /// stacks onto a tile the user cannot see is a tile that vanishes.
    func stackTargets(_ slotId: String) -> [StackSlot] {
        let shown = visibleSlots
        guard let from = shown.first(where: { $0.id == slotId }) else { return [] }
        return shown.filter { Dashboard.canStack(from, $0) }
    }

    func resize(_ slotId: String) {
        apply(Dashboard.resizeSlot(layout, slotId: slotId))
    }

    /// Take the whole slot off the grid — every face goes to the tray.
    func remove(_ slotId: String) {
        guard let s = Dashboard.slot(layout, at: slotId) else { return }
        var next = layout
        for _ in s.items { next = Dashboard.removeFace(next, slotId: slotId, index: 0) }
        apply(next)
    }

    func removeFace(_ slotId: String, index: Int) {
        apply(Dashboard.removeFace(layout, slotId: slotId, index: index))
    }

    func unstack(_ slotId: String, index: Int) {
        apply(Dashboard.unstackFace(layout, slotId: slotId, index: index))
    }

    /// Unstack the face at a position on the GRID, which is not its position in
    /// the stored slot.
    ///
    /// ── TWO INDEX SPACES, AND THE MENU SPEAKS THE WRONG ONE ─────────────────
    /// The grid draws `visibleSlots`, whose items have been through
    /// `projectNative` — a slot the web stored as `[micros, water, sleep]`
    /// reaches the screen as `[water, sleep]`, because the phone has no face for
    /// `micros`. `Dashboard.unstackFace` indexes the STORED items. So the menu
    /// offering "Unstack Sleep" for visible index 1 would lift stored index 1,
    /// which is Water — the wrong face — and "Unstack Water" at visible 0 would
    /// lift `micros`, splitting off a slot the phone cannot draw and moving
    /// nothing the user can see.
    ///
    /// The web stacks without an `isNative` filter and `micros`, `bar` and
    /// `stack` are all small, so a mixed stack is a thing any web user can make.
    func unstackVisible(_ slotId: String, visibleIndex: Int) {
        guard let stored = Dashboard.slot(layout, at: slotId) else { return }
        let native = stored.items.indices.filter { stored.items[$0].isNative }
        guard native.indices.contains(visibleIndex) else { return }
        unstack(slotId, index: native[visibleIndex])
    }

    func reorderFace(_ slotId: String, from: Int, to: Int) {
        apply(Dashboard.reorderFace(layout, slotId: slotId, from: from, to: to))
    }

    func add(_ id: WidgetId) {
        apply(Dashboard.addWidget(layout, id))
    }

    /// Connect a stack, or disconnect it (W7, A9).
    func setLinked(_ slotId: String, _ linked: Bool) {
        apply(Dashboard.setLinked(layout, slotId: slotId, linked))
    }

    private func apply(_ next: DashboardLayout) {
        // ── NEVER PUSH A LAYOUT THIS OBJECT HAS NOT READ ────────────────────
        // See `hasLoaded`. The edit is refused outright rather than applied
        // locally and saved later: applying it would move the tiles under a
        // stream that is about to yield the real arrangement and move them
        // back, which is a grid that undoes a drag a fraction of a second
        // after it lands. The window is one database round trip on first
        // appearance.
        guard hasLoaded, next != layout else { return }
        layout = next
        do {
            try database.saveDashboardLayout(userId: userId, next)
        } catch {
            failure = "That arrangement could not be saved on this device."
        }
    }
}

/// What a tap opens.
enum TodaySheet: Identifiable, Hashable {
    /// The domain sheet behind one tile.
    case tile(WidgetId)
    /// The faces of one stack, for reordering.
    case stack(String)
    /// One finished session, in full.
    ///
    /// Not a `.tile(.train)` variant: the Workout tile's sheet used to draw
    /// `TodayLargeFace`, which ends in a seven-day list — so tapping a tile
    /// that says "you trained today" opened a page whose bottom half was other
    /// days, several of them labelled "missed". A finished session has its own
    /// page already (`SessionDetailView`), with the exercises, the ledger, the
    /// records and the atlas on it, and that is the page the tile means.
    case session(String)

    var id: String {
        switch self {
        case .tile(let w): "tile-\(w.rawValue)"
        case .stack(let s): "stack-\(s)"
        case .session(let s): "session-\(s)"
        }
    }
}
