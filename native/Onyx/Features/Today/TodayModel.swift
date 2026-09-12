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
    private(set) var feed: TodayFeed?
    private(set) var failure: String?

    /// Jiggle mode. Stacks stop rotating, taps stop opening sheets.
    var editing = false
    /// Whether the scene is in the foreground — the other reason a stack stops.
    var isActive = true
    var sheet: TodaySheet?

    /// A preview hands in a feed and skips the builder — no mirror to read.
    private let seededFeed: TodayFeed?

    init(database: AppDatabase, userId: String, feed: TodayFeed? = nil, layout: DashboardLayout? = nil) {
        self.database = database
        self.userId = userId
        self.seededFeed = feed
        self.feed = feed
        if let layout { self.layout = layout }
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
            for try await stored in database.dashboardLayoutStream(userId: userId) {
                layout = stored?.layout ?? Dashboard.defaultLayout(.phone)
            }
        } catch {
            if !(error is CancellationError) { failure = "The layout could not be read on this device." }
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
        let sessions = (try? database.sessions(on: date)) ?? []
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
            return items.isEmpty ? nil : StackSlot(id: s.id, size: s.size, items: items)
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

    private func apply(_ next: DashboardLayout) {
        guard next != layout else { return }
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
