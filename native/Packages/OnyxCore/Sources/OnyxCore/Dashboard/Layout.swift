import Foundation

// The dashboard's arrangement — the slot algebra of the web app's `lib/dashboard/layout.ts`.
//
// ── WHAT IS HERE AND WHAT IS NOT ────────────────────────────────────────────
// The pure part: the catalogue, the sizes each widget has a body for, the
// stored-payload reader (all four versions), the wire form, and every
// operation the grid performs. NOT here: localStorage (`readLayout`,
// `writeLayout`) — that is storage, and Track S owns the GRDB copy — and
// `WIDGET_META`, which carries icons and belongs to the UI package.
//
// The reasoning behind each rule is in the TypeScript header and is not
// repeated. The one that must survive translation:
//
// > **A stack has ONE size** — the largest every face can draw — because a flip
// > must never change a tile's height. `clampSize` is the function that keeps
// > that true, and everything that changes a slot's faces routes through it.

/// Five sizes, five different ANSWERS — not one box at five scales.
public enum WidgetSize: String, Codable, Sendable, CaseIterable {
    case s, m, l, w, xl

    /// The order `clampSize` steps through.
    var rank: Int {
        switch self {
        case .s: return 0
        case .m: return 1
        case .l: return 2
        case .w: return 3
        case .xl: return 4
        }
    }
}

/// Which screen an arrangement belongs to. They do not sync to each other.
public enum DashboardSurface: String, Codable, Sendable {
    case phone, desktop
}

/// Every widget the dashboard knows how to render, **declared in first-run
/// order** — `allCases` is the catalogue order the TypeScript's `WIDGET_IDS`
/// carries, and `reconcile` appends in this order.
public enum WidgetId: String, Codable, Sendable, CaseIterable {
    case recovery, sleep, vitals, fuel, water, micros, deficit, train, bar
    // `trajectory` is W12's, and it sits beside `body` because it is the same
    // question asked over time. Declaration order IS the catalogue order that
    // `reconcile` appends in, so a new id lands where it reads rather than at
    // the end of the grid.
    case body, trajectory, muscle, volume, pr, consistency, steps, cardio, stack, fatigue
    // `daily` is W7's Mega Widget and is declared LAST on purpose. Declaration
    // order is the order `reconcile` appends in, so a twentieth id put anywhere
    // else would shift the tail of every stored layout — and the golden vectors
    // pin that tail. Last means "appended after everything that was already
    // there", which is what a device carrying a v4 row actually experiences.
    case daily
}

/// One position on the grid. `items` is ordered and MAY repeat a widget.
public struct StackSlot: Codable, Sendable, Equatable {
    public var id: String
    public var size: WidgetSize
    public var items: [WidgetId]
    /// A CONNECTED stack (W7, A9): its faces share one window rather than each
    /// resolving independently.
    ///
    /// ── WHAT IT MEANS ON A PHONE, WHICH IS NOT WHAT IT MEANS IN A PAYLOAD ───
    /// The storage is the whole of it here: the flag rides in the layout row,
    /// defaults false, and every reader that does not know about it behaves
    /// exactly as before. What the Today grid DOES with it is
    /// `SmartStackView`'s business — a linked slot drops its per-slot rotation
    /// phase so every connected stack turns over on one beat.
    public var linked: Bool

    public init(id: String, size: WidgetSize, items: [WidgetId], linked: Bool = false) {
        self.id = id
        self.size = size
        self.items = items
        self.linked = linked
    }

    // ── CODABLE BY HAND, FOR ONE KEY ────────────────────────────────────────
    // A property's default value is NOT consulted by Swift's synthesized
    // `init(from:)` — only by the memberwise initialiser. So the synthesized
    // decoder makes `linked` REQUIRED, and every stored layout, every golden
    // vector and every mirrored row written before W7 fails to decode with
    // `keyNotFound`. That is not a theoretical migration: it is the row on the
    // device right now.
    //
    // The encoder omits `linked` when it is false for the same reason
    // `serializeLayout` does: absent and false say the same thing, so writing
    // it would rewrite every payload to state what it already stated.

    enum CodingKeys: String, CodingKey { case id, size, items, linked }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        size = try c.decode(WidgetSize.self, forKey: .size)
        items = try c.decode([WidgetId].self, forKey: .items)
        linked = try c.decodeIfPresent(Bool.self, forKey: .linked) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(size, forKey: .size)
        try c.encode(items, forKey: .items)
        if linked { try c.encode(true, forKey: .linked) }
    }
}

public struct DashboardLayout: Codable, Sendable, Equatable {
    public var slots: [StackSlot]
    /// Widgets the user took OFF the grid, on purpose. Stored, not derived —
    /// see the TypeScript for the reappearing-widget bug that forced this.
    public var hidden: [WidgetId]
    /// Epoch ms of the last edit; 0 for a layout that has never been written.
    public var updatedAt: Double

    public init(slots: [StackSlot], hidden: [WidgetId], updatedAt: Double) {
        self.slots = slots
        self.hidden = hidden
        self.updatedAt = updatedAt
    }
}

public enum Dashboard {
    // MARK: Catalogue

    public static let allSizes: [WidgetSize] = WidgetSize.allCases
    /// Sizes only a desktop layout may hold — they span all four columns.
    public static let wideSizes: [WidgetSize] = [.w, .xl]
    public static let widgetIds: [WidgetId] = WidgetId.allCases

    /// The sizes each widget actually has a body for.
    public static let widgetSizes: [WidgetId: [WidgetSize]] = [
        .recovery: [.m, .l, .w, .xl],
        .sleep: [.s, .m, .l, .w, .xl],
        .vitals: [.s, .m, .l],
        .fuel: [.s, .m, .l],
        .micros: [.s, .m, .l],
        .water: [.s, .m],
        .deficit: [.s, .m, .l],
        .train: [.s, .m, .l],
        .bar: [.s, .m, .l],
        .body: [.s, .m, .l, .w, .xl],
        // Small is the rate and the arrival; medium adds the line and the
        // target band. No large — a weight curve is one series, and a taller
        // plot of one series is a stretched medium.
        .trajectory: [.s, .m],
        .muscle: [.s, .m, .l],
        .volume: [.s, .m, .l],
        .pr: [.s, .m],
        .consistency: [.s, .m, .l],
        .steps: [.s, .m, .l],
        .cardio: [.s, .m],
        .stack: [.s, .m],
        .fatigue: [.s, .m],
        // ── ONE SIZE, AND IT IS THE BIG ONE (W7) ───────────────────────────
        // Three concentric arcs, a battery in the hole and a sentence under
        // it. A Small is 158 pt square: the arcs would be 40 pt across and the
        // sentence would be two truncated words. A Medium is the same height
        // with the width spent sideways, which buys the sentence a line and
        // costs the rings the room that makes them readable. The widget that
        // answers "how is the whole day going" is the one widget that has to
        // be able to hold four answers at once, so it holds one size.
        .daily: [.l],
    ]

    static let defaultSizePhone: [WidgetId: WidgetSize] = [
        .recovery: .l,
        .sleep: .m, .vitals: .m, .fuel: .m, .water: .s, .micros: .s, .deficit: .m,
        .train: .m, .bar: .s, .body: .m, .trajectory: .m, .muscle: .s, .volume: .s,
        .pr: .s, .consistency: .s, .steps: .s, .cardio: .s, .stack: .s,
        .fatigue: .s, .daily: .l,
    ]

    static let defaultSizeDesktop: [WidgetId: WidgetSize] = defaultSizePhone.merging([
        .recovery: .xl,
        .sleep: .w,
        .body: .w,
        .vitals: .l, .fuel: .l, .deficit: .l, .train: .l, .muscle: .l, .volume: .l,
        .micros: .m, .bar: .m, .consistency: .m, .steps: .m,
        .water: .m, .pr: .m, .cardio: .m, .stack: .m, .fatigue: .m, .trajectory: .m,
        // `.l` on a desktop too, and not `.xl`: `defaultLayout` takes this
        // number UNCLAMPED, so a default outside `widgetSizes` mints a slot
        // whose size no face can draw.
        .daily: .l,
    ]) { _, new in new }

    /// The size a widget lands at when it is added back from the tray.
    public static func defaultSize(for id: WidgetId, surface: DashboardSurface = .phone) -> WidgetSize {
        (surface == .desktop ? defaultSizeDesktop : defaultSizePhone)[id]!
    }

    // MARK: Size algebra

    /// The largest sizes a slot may take: what every widget in it can draw, in
    /// growing order. A phone never offers the wide sizes.
    public static func sizesFor(_ items: [WidgetId], surface: DashboardSurface = .phone) -> [WidgetSize] {
        let all = surface == .desktop ? allSizes : allSizes.filter { !wideSizes.contains($0) }
        return all.filter { size in items.allSatisfy { widgetSizes[$0]!.contains(size) } }
    }

    /// The nearest size a slot can actually draw, preferring not to grow.
    public static func clampSize(
        _ items: [WidgetId], _ want: WidgetSize, surface: DashboardSurface = .phone
    ) -> WidgetSize {
        let ok = sizesFor(items, surface: surface)
        if ok.isEmpty { return .s }
        if ok.contains(want) { return want }
        // A stable sort by rank distance; `ok` is already in growing order, so
        // a tie resolves to the smaller size — exactly as the JavaScript sort.
        return ok.sorted { abs($0.rank - want.rank) < abs($1.rank - want.rank) }[0]
    }

    // MARK: Slot ids

    /// Slot ids only have to be unique within one layout and stable across
    /// writes. The TypeScript mixes the clock with a counter; a UUID needs no
    /// mutable state and the golden vectors normalise minted ids either way.
    public static func newSlotId() -> String {
        "sl" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12)
    }

    public static func defaultLayout(_ surface: DashboardSurface = .phone) -> DashboardLayout {
        DashboardLayout(
            slots: widgetIds.map { StackSlot(id: "sl-\($0.rawValue)", size: defaultSize(for: $0, surface: surface), items: [$0]) },
            hidden: [],
            updatedAt: 0
        )
    }

    // MARK: The stored payload

    /// v3 added `hidden`; v4 split the arrangement by surface; v5 added
    /// `StackSlot.linked` (W7, A9).
    static let version = 5.0

    /// The versions whose payload carries `phone` / `desktop` SIDES.
    ///
    /// ── WHY THIS IS A SET AND NOT `== version` ──────────────────────────────
    /// `version` is not a label on the payload, it is the GATE `fromStored`
    /// uses to decide whether a stored object has sides at all — W6's record
    /// says so, and is why W6 left `v` at 4 rather than widen anything. v5 is
    /// additive over v4: one optional boolean per slot, absent when false. So
    /// the two versions are the SAME shape, and the gate names both. Raise
    /// `version` without adding the new number here and every stored v4 row
    /// reads as "no sides": `fromStored` hands back the default dashboard and
    /// `otherSideOf` drops the desktop arrangement on the next save.
    static let splitVersions: Set<Double> = [4, 5]

    /// A stored payload — a `dashboard_layouts.layout` row, or the app's own
    /// copy — as a layout, reconciled against the current catalogue. Takes the
    /// value `JSONSerialization` produces. Never throws and never returns a
    /// partial layout; every corrupt shape reads as the defaults.
    ///
    /// Mirrors `fromStored` in the TypeScript, including which JavaScript
    /// falsy values take which branch — a v4 whose side is `0` or `""` returns
    /// the defaults, and a side that is any other non-object is read as empty,
    /// which reconciles to the same thing.
    public static func fromStored(_ stored: Any, surface: DashboardSurface = .phone) -> DashboardLayout {
        let dict = stored as? [String: Any] ?? [:]
        let v = jsNumber(dict["v"])

        var side: [String: Any]? = nil
        if let v, splitVersions.contains(v) {
            let raw = dict[surface.rawValue]
            if raw == nil || raw is NSNull { return defaultLayout(surface) }
            // A present, non-object side reads as an empty one.
            side = raw as? [String: Any] ?? [:]
        }
        let from = side ?? dict

        let slots: [StackSlot]
        if side != nil || v == 2 || v == 3 {
            slots = parseSlots(from["slots"], surface: surface)
        } else if v == 1 {
            slots = fromV1(dict, surface: surface)
        } else {
            slots = []
        }

        let hidden = (from["hidden"] as? [Any])?.compactMap(widgetId) ?? []
        let updatedAt: Double = {
            if let n = jsNumber(from["updatedAt"]), n.isFinite { return n }
            return 0
        }()

        return reconcile(DashboardLayout(slots: slots, hidden: hidden, updatedAt: updatedAt), surface: surface)
    }

    static func parseSlots(_ raw: Any?, surface: DashboardSurface) -> [StackSlot] {
        guard let rows = raw as? [Any] else { return [] }
        var out: [StackSlot] = []
        for row in rows {
            // `typeof s !== 'object'` — an array IS an object in JavaScript,
            // but it has no `items` and so is skipped either way.
            guard let dict = row as? [String: Any] else { continue }
            let items = (dict["items"] as? [Any])?.compactMap(widgetId) ?? []
            if items.isEmpty { continue }
            let id: String = {
                if let s = dict["id"] as? String, !s.isEmpty { return s }
                return newSlotId()
            }()
            let want = size(dict["size"]) ?? defaultSize(for: items[0], surface: surface)
            // Absent, null, or anything that is not a JSON boolean reads as
            // false — the pre-v5 meaning, which is the meaning every stored
            // row has.
            let linked = (dict["linked"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } ?? false
            out.append(StackSlot(id: id, size: clampSize(items, want, surface: surface), items: items, linked: linked))
        }
        return out
    }

    /// `{ order, size, hidden }` → one slot per visible widget, sizes preserved.
    static func fromV1(_ stored: [String: Any], surface: DashboardSurface) -> [StackSlot] {
        let order = (stored["order"] as? [Any])?.compactMap(widgetId) ?? []
        let hidden = Set((stored["hidden"] as? [Any])?.compactMap(widgetId) ?? [])
        var sizes: [WidgetId: WidgetSize] = [:]
        if let map = stored["size"] as? [String: Any] {
            for (key, value) in map {
                if let id = WidgetId(rawValue: key), let s = size(value) { sizes[id] = s }
            }
        }
        return order
            .filter { !hidden.contains($0) }
            .map { id in
                StackSlot(
                    id: "sl-\(id.rawValue)",
                    size: clampSize([id], sizes[id] ?? defaultSize(for: id, surface: surface), surface: surface),
                    items: [id]
                )
            }
    }

    /// Unique slot ids, hidden narrowed by what is placed, and every catalogue
    /// widget that is in neither list appended at its default size.
    static func reconcile(_ layout: DashboardLayout, surface: DashboardSurface) -> DashboardLayout {
        var seen = Set<String>()
        var slots = layout.slots.map { s -> StackSlot in
            var id = s.id
            while seen.contains(id) { id = newSlotId() }
            seen.insert(id)
            var copy = s
            copy.id = id
            return copy
        }
        let placed = Set(slots.flatMap(\.items))
        let hidden = layout.hidden.filter { !placed.contains($0) }
        let known = placed.union(hidden)
        for id in widgetIds where !known.contains(id) {
            slots.append(StackSlot(id: "sl-\(id.rawValue)", size: defaultSize(for: id, surface: surface), items: [id]))
        }
        return DashboardLayout(slots: slots, hidden: hidden, updatedAt: layout.updatedAt)
    }

    // MARK: The wire form

    /// The v4 payload: the written surface from `layout`, the other surface
    /// carried through UNPARSED from whatever was stored. Returns what
    /// `JSONSerialization` can write.
    public static func serializeLayout(
        _ layout: DashboardLayout, surface: DashboardSurface, other: Any? = nil
    ) -> [String: Any] {
        let side: [String: Any] = [
            // `linked` is written only when it is TRUE. A key that is absent
            // and a key that is `false` mean the same thing to every reader
            // (`parseSlots` above, and any older build), so writing it for
            // every slot would rewrite every stored row to say what it
            // already said — which is the "default false leaves every stored
            // layout unchanged" rule, spelled in the writer.
            "slots": layout.slots.map { slot -> [String: Any] in
                var out: [String: Any] = ["id": slot.id, "size": slot.size.rawValue, "items": slot.items.map(\.rawValue)]
                if slot.linked { out["linked"] = true }
                return out
            },
            "hidden": layout.hidden.map(\.rawValue),
            "updatedAt": layout.updatedAt,
        ]
        var out: [String: Any] = ["v": version, surface.rawValue: side]
        let otherKey: DashboardSurface = surface == .desktop ? .phone : .desktop
        if let kept = otherSideOf(other, surface: surface) { out[otherKey.rawValue] = kept }
        // The Train tab's own sections ride in this row too (W6, `TrainLayout`).
        // Carried through UNPARSED, exactly like the other surface above and for
        // the identical reason: dragging a dashboard tile must not put the Train
        // tab's Cardio card back, and this writer has no opinion about it.
        if let train = (other as? [String: Any])?[trainKey], !(train is NSNull) { out[trainKey] = train }
        return out
    }

    /// The OTHER surface's stored arrangement. A pre-split payload has no sides,
    /// so the whole of it stands in.
    static func otherSideOf(_ stored: Any?, surface: DashboardSurface) -> Any? {
        guard let stored, !(stored is NSNull) else { return nil }
        // An array is an object to JavaScript: it has no `v` and no sides, so
        // the pre-split branch yields an empty object.
        if stored is [Any] { return [String: Any]() }
        guard let dict = stored as? [String: Any] else { return nil }
        let key: DashboardSurface = surface == .desktop ? .phone : .desktop
        if let v = jsNumber(dict["v"]), splitVersions.contains(v) {
            let raw = dict[key.rawValue]
            return raw is NSNull ? nil : raw
        }
        var kept: [String: Any] = [:]
        for k in ["slots", "hidden", "updatedAt"] {
            if let v = dict[k], !(v is NSNull) { kept[k] = v }
        }
        return kept
    }

    /// Stamp an edit. Every mutation goes through this, so `updatedAt` cannot lie.
    public static func touch(_ layout: DashboardLayout) -> DashboardLayout {
        var copy = layout
        copy.updatedAt = (Date().timeIntervalSince1970 * 1000).rounded(.down)
        return copy
    }

    // MARK: Heights

    public static let rowUnitPx = 52.0
    public static let gridGapPx = 8.0

    static func spanRows(_ size: WidgetSize) -> Double {
        switch size {
        case .s: return 2
        case .m: return 3
        case .l: return 5
        case .w: return 3
        case .xl: return 5
        }
    }

    /// Total tile height in px, gaps included.
    public static func tileHeightPx(_ size: WidgetSize) -> Double {
        let rows = spanRows(size)
        return rows * rowUnitPx + (rows - 1) * gridGapPx
    }

    /// The height a size stands for, which is not the size: `w` is a medium's
    /// height at four columns, `xl` a large's.
    public static func heightTier(_ size: WidgetSize) -> WidgetSize {
        switch size {
        case .xl: return .l
        case .w: return .m
        default: return size
        }
    }

    /// The tile minus the frame's padding (8 + 10), its 18px header and the 6px gap.
    public static func bodyHeightPx(_ size: WidgetSize) -> Double {
        tileHeightPx(size) - 18 - 18 - 6
    }

    // MARK: Queries

    /// Every widget currently placed, in grid order, duplicates included.
    public static func placedWidgets(_ layout: DashboardLayout) -> [WidgetId] {
        layout.slots.flatMap(\.items)
    }

    /// The tray's contents, in catalogue order.
    public static func hiddenWidgets(_ layout: DashboardLayout) -> [WidgetId] {
        let hidden = Set(layout.hidden)
        return widgetIds.filter { hidden.contains($0) }
    }

    public static func slot(_ layout: DashboardLayout, at slotId: String) -> StackSlot? {
        layout.slots.first { $0.id == slotId }
    }

    // MARK: The arrangement rules

    /// Take one face off the grid. The last face of a slot removes the slot; a
    /// widget goes to the tray only when its LAST face anywhere is gone.
    public static func removeFace(_ layout: DashboardLayout, slotId: String, index: Int) -> DashboardLayout {
        let dropped: WidgetId? = {
            guard let s = slot(layout, at: slotId), s.items.indices.contains(index) else { return nil }
            return s.items[index]
        }()
        var slots: [StackSlot] = []
        for s in layout.slots {
            if s.id != slotId { slots.append(s); continue }
            let items = s.items.enumerated().filter { $0.offset != index }.map(\.element)
            if items.isEmpty { continue }
            // The TypeScript clamps on the default surface here; mirrored.
            slots.append(StackSlot(id: s.id, size: clampSize(items, s.size), items: items, linked: s.linked))
        }
        let stillPlaced = Set(slots.flatMap(\.items))
        var hidden = layout.hidden
        if let dropped, !stillPlaced.contains(dropped), !hidden.contains(dropped) {
            hidden.append(dropped)
        }
        return touch(DashboardLayout(slots: slots, hidden: hidden, updatedAt: layout.updatedAt))
    }

    /// Put a widget on the grid, at the end, at its default size. Duplicates
    /// are allowed — this never asks whether the widget is already placed.
    public static func addWidget(
        _ layout: DashboardLayout, _ id: WidgetId, surface: DashboardSurface = .phone
    ) -> DashboardLayout {
        touch(DashboardLayout(
            slots: layout.slots + [StackSlot(id: newSlotId(), size: defaultSize(for: id, surface: surface), items: [id])],
            hidden: layout.hidden.filter { $0 != id },
            updatedAt: layout.updatedAt
        ))
    }

    /// Advance one step round the sizes this slot's widgets can all draw.
    public static func resizeSlot(
        _ layout: DashboardLayout, slotId: String, surface: DashboardSurface = .phone
    ) -> DashboardLayout {
        var copy = layout
        copy.slots = layout.slots.map { s in
            guard s.id == slotId else { return s }
            let ok = sizesFor(s.items, surface: surface)
            if ok.count < 2 { return s }
            // A size not in the ladder (a desktop `xl` read on a phone) is
            // index -1, and -1 + 1 lands on the first rung — as in JavaScript.
            let at = ok.firstIndex(of: s.size) ?? -1
            var next = s
            next.size = ok[(at + 1) % ok.count]
            return next
        }
        return touch(copy)
    }

    /// Move a slot to another slot's position, everything else closing up.
    public static func moveSlot(_ layout: DashboardLayout, fromId: String, toId: String) -> DashboardLayout {
        guard let from = layout.slots.firstIndex(where: { $0.id == fromId }),
              let to = layout.slots.firstIndex(where: { $0.id == toId }),
              from != to
        else { return layout }
        var slots = layout.slots
        let moved = slots.remove(at: from)
        slots.insert(moved, at: to)
        var copy = layout
        copy.slots = slots
        return touch(copy)
    }

    /// Same size only, never the same slot, never on a desktop.
    public static func canStack(_ a: StackSlot?, _ b: StackSlot?, surface: DashboardSurface = .phone) -> Bool {
        if surface == .desktop { return false }
        guard let a, let b, a.id != b.id else { return false }
        return a.size == b.size
    }

    /// Drop one slot onto another; the dragged slot's faces go UNDER the target's.
    public static func stackSlots(
        _ layout: DashboardLayout, fromId: String, ontoId: String, surface: DashboardSurface = .phone
    ) -> DashboardLayout {
        let from = slot(layout, at: fromId)
        let onto = slot(layout, at: ontoId)
        guard canStack(from, onto, surface: surface), let from, let onto else { return layout }
        let items = onto.items + from.items
        var copy = layout
        copy.slots = layout.slots
            .filter { $0.id != fromId }
            .map { s in
                guard s.id == ontoId else { return s }
                // The TARGET's flag survives, because the target is the slot
                // that stays (`TileMenu`'s header states the direction).
                return StackSlot(id: s.id, size: clampSize(items, s.size, surface: surface), items: items, linked: s.linked)
            }
        return touch(copy)
    }

    /// Lift one face out of a stack into its own slot, directly after it.
    public static func unstackFace(_ layout: DashboardLayout, slotId: String, index: Int) -> DashboardLayout {
        guard let s = slot(layout, at: slotId), s.items.count >= 2, s.items.indices.contains(index) else { return layout }
        let id = s.items[index]
        let rest = s.items.enumerated().filter { $0.offset != index }.map(\.element)
        let at = layout.slots.firstIndex { $0.id == slotId }!
        var slots = layout.slots
        slots[at] = StackSlot(id: s.id, size: clampSize(rest, s.size), items: rest, linked: s.linked)
        // The lifted face is its own tile now, and a tile is not a stack: it
        // has nothing to be connected TO.
        slots.insert(StackSlot(id: newSlotId(), size: clampSize([id], s.size), items: [id]), at: at + 1)
        var copy = layout
        copy.slots = slots
        return touch(copy)
    }

    /// Connect a stack, or disconnect it. A slot with one face cannot be
    /// connected — there is nothing for it to share a window WITH — so the flag
    /// is refused there rather than stored and ignored.
    public static func setLinked(_ layout: DashboardLayout, slotId: String, _ linked: Bool) -> DashboardLayout {
        guard let s = slot(layout, at: slotId), s.items.count > 1 || !linked, s.linked != linked else { return layout }
        var copy = layout
        copy.slots = layout.slots.map { slot in
            guard slot.id == slotId else { return slot }
            var next = slot
            next.linked = linked
            return next
        }
        return touch(copy)
    }

    /// Reorder the faces INSIDE one stack. Cannot change the slot's size.
    public static func reorderFace(_ layout: DashboardLayout, slotId: String, from: Int, to: Int) -> DashboardLayout {
        guard let s = slot(layout, at: slotId) else { return layout }
        let n = s.items.count
        if from == to || from < 0 || to < 0 || from >= n || to >= n { return layout }
        var items = s.items
        let moved = items.remove(at: from)
        items.insert(moved, at: to)
        var copy = layout
        copy.slots = layout.slots.map { slot in
            guard slot.id == slotId else { return slot }
            var next = slot
            next.items = items
            return next
        }
        return touch(copy)
    }

    // MARK: JSON helpers — JavaScript's typeof, for a JSONSerialization value

    /// `typeof v === 'number'`. A JSON boolean bridges to NSNumber too, and is
    /// not a number to JavaScript, so it is rejected here.
    static func jsNumber(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    static func widgetId(_ v: Any) -> WidgetId? {
        (v as? String).flatMap(WidgetId.init(rawValue:))
    }

    static func size(_ v: Any?) -> WidgetSize? {
        (v as? String).flatMap(WidgetSize.init(rawValue:))
    }
}
