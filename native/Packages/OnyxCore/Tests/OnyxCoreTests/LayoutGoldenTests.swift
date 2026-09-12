import Foundation
import Testing
@testable import OnyxCore

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard layout — the web app's `lib/dashboard/layout.ts`, replayed from `npm run golden`
//
// Two things are non-deterministic on both sides and are normalised the same
// way before comparing: a freshly minted slot id becomes `new-1`, `new-2`… in
// order of appearance, and an `updatedAt` the operation stamped becomes -1.
// An operation that hands its input back untouched keeps the input's stamp,
// and that difference — touched or not — is part of what is being checked.
// ─────────────────────────────────────────────────────────────────────────────

private func normalize(known: Set<String>, before: Double, _ after: DashboardLayout) -> DashboardLayout {
    var minted: [String: String] = [:]
    let slots = after.slots.map { s -> StackSlot in
        if known.contains(s.id) { return s }
        if minted[s.id] == nil { minted[s.id] = "new-\(minted.count + 1)" }
        var copy = s
        copy.id = minted[s.id]!
        return copy
    }
    return DashboardLayout(slots: slots, hidden: after.hidden, updatedAt: after.updatedAt == before ? before : -1)
}

/// Every `id` string a stored payload names, however deep, plus the
/// deterministic `sl-<widget>` ids `reconcile` mints.
private func idsIn(_ stored: Any) -> Set<String> {
    var out = Set<String>()
    func walk(_ v: Any) {
        if let arr = v as? [Any] { arr.forEach(walk); return }
        if let dict = v as? [String: Any] {
            if let id = dict["id"] as? String, !id.isEmpty { out.insert(id) }
            dict.values.forEach(walk)
        }
    }
    walk(stored)
    for id in WidgetId.allCases { out.insert("sl-\(id.rawValue)") }
    return out
}

/// A fixture read through `JSONSerialization`, for the cases whose input is an
/// untyped stored payload rather than a decodable struct.
private func loadRaw(_ name: String) throws -> [[String: Any]] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw GoldenError.missing(name)
    }
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    return root["cases"] as! [[String: Any]]
}

private func decodeLayout(_ raw: Any) throws -> DashboardLayout {
    try JSONDecoder().decode(DashboardLayout.self, from: JSONSerialization.data(withJSONObject: raw))
}

@Suite("Dashboard layout — the slot algebra")
struct LayoutGoldenTests {
    struct Empty: Decodable {}
    struct Catalogue: Decodable {
        let ids: [String]
        let sizes: [String: [String]]
        let defaultPhone: [String: String]
        let defaultDesktop: [String: String]
    }

    @Test("the catalogue, its sizes and its defaults survived the translation")
    func catalogueMatches() throws {
        let e = try #require(try GoldenFixture<Empty, Catalogue>.load("layout-catalogue").cases.first).expected
        #expect(Dashboard.widgetIds.map(\.rawValue) == e.ids)
        for id in Dashboard.widgetIds {
            #expect(Dashboard.widgetSizes[id]!.map(\.rawValue) == e.sizes[id.rawValue], "sizes for \(id)")
            #expect(Dashboard.defaultSize(for: id, surface: .phone).rawValue == e.defaultPhone[id.rawValue], "phone default for \(id)")
            #expect(Dashboard.defaultSize(for: id, surface: .desktop).rawValue == e.defaultDesktop[id.rawValue], "desktop default for \(id)")
        }
    }

    struct SizesInput: Decodable { let items: [WidgetId]; let surface: DashboardSurface }

    @Test("sizesFor matches")
    func sizesForMatches() throws {
        let fixture = try GoldenFixture<SizesInput, [WidgetSize]>.load("layout-sizes-for")
        for c in fixture.cases {
            #expect(Dashboard.sizesFor(c.input.items, surface: c.input.surface) == c.expected, "sizesFor — \(c.name)")
        }
    }

    struct ClampInput: Decodable { let items: [WidgetId]; let want: WidgetSize; let surface: DashboardSurface }

    @Test("clampSize matches — down first, then the nearest")
    func clampSizeMatches() throws {
        let fixture = try GoldenFixture<ClampInput, WidgetSize>.load("layout-clamp-size")
        for c in fixture.cases {
            #expect(Dashboard.clampSize(c.input.items, c.input.want, surface: c.input.surface) == c.expected, "clampSize — \(c.name)")
        }
    }

    struct HeightInput: Decodable { let size: WidgetSize }
    struct HeightExpected: Decodable { let tile: Double; let tier: WidgetSize; let body: Double }

    @Test("the pixel heights match")
    func heightsMatch() throws {
        let fixture = try GoldenFixture<HeightInput, HeightExpected>.load("layout-heights")
        for c in fixture.cases {
            expectClose(Dashboard.tileHeightPx(c.input.size), c.expected.tile, "tileHeightPx — \(c.name)")
            #expect(Dashboard.heightTier(c.input.size) == c.expected.tier, "heightTier — \(c.name)")
            expectClose(Dashboard.bodyHeightPx(c.input.size), c.expected.body, "bodyHeightPx — \(c.name)")
        }
    }

    struct SurfaceInput: Decodable { let surface: DashboardSurface }

    @Test("the default layouts match")
    func defaultsMatch() throws {
        let fixture = try GoldenFixture<SurfaceInput, DashboardLayout>.load("layout-defaults")
        for c in fixture.cases {
            #expect(Dashboard.defaultLayout(c.input.surface) == c.expected, "defaultLayout — \(c.name)")
        }
    }

    @Test("the stored-payload reader matches on every version and every broken shape")
    func fromStoredMatches() throws {
        let cases = try loadRaw("layout-from-stored")
        #expect(cases.count > 40)
        for c in cases {
            let name = c["name"] as! String
            let input = c["input"] as! [String: Any]
            let stored = input["stored"]!
            let surface = DashboardSurface(rawValue: input["surface"] as! String)!
            let expected = try decodeLayout(c["expected"]!)
            let actual = normalize(known: idsIn(stored), before: 0, Dashboard.fromStored(stored, surface: surface))
            #expect(actual == expected, "fromStored — \(name)")
        }
    }

    struct Op: Decodable {
        let kind: String
        let slotId: String?
        let index: Int?
        let to: Int?
        let id: WidgetId?
        let surface: DashboardSurface?
        let fromId: String?
        let toId: String?
        let ontoId: String?
    }
    struct OpInput: Decodable { let layout: DashboardLayout; let op: Op }

    @Test("every arrangement operation matches")
    func opsMatch() throws {
        let fixture = try GoldenFixture<OpInput, DashboardLayout>.load("layout-ops")
        #expect(fixture.cases.count > 100)
        for c in fixture.cases {
            let l = c.input.layout
            let op = c.input.op
            let out: DashboardLayout
            switch op.kind {
            case "removeFace": out = Dashboard.removeFace(l, slotId: op.slotId!, index: op.index!)
            case "addWidget": out = Dashboard.addWidget(l, op.id!, surface: op.surface!)
            case "resizeSlot": out = Dashboard.resizeSlot(l, slotId: op.slotId!, surface: op.surface!)
            case "moveSlot": out = Dashboard.moveSlot(l, fromId: op.fromId!, toId: op.toId!)
            case "stackSlots": out = Dashboard.stackSlots(l, fromId: op.fromId!, ontoId: op.ontoId!, surface: op.surface!)
            case "unstackFace": out = Dashboard.unstackFace(l, slotId: op.slotId!, index: op.index!)
            case "reorderFace": out = Dashboard.reorderFace(l, slotId: op.slotId!, from: op.index!, to: op.to!)
            default:
                Issue.record("unknown op \(op.kind) — the exporter grew a case this test does not know")
                continue
            }
            let known = Set(l.slots.map(\.id))
            #expect(normalize(known: known, before: l.updatedAt, out) == c.expected, "\(op.kind) — \(c.name)")
        }
    }

    struct StackInput: Decodable { let a: StackSlot?; let b: StackSlot?; let surface: DashboardSurface }

    @Test("canStack matches")
    func canStackMatches() throws {
        let fixture = try GoldenFixture<StackInput, Bool>.load("layout-can-stack")
        for c in fixture.cases {
            #expect(Dashboard.canStack(c.input.a, c.input.b, surface: c.input.surface) == c.expected, "canStack — \(c.name)")
        }
    }

    struct QueryInput: Decodable { let layout: DashboardLayout }
    struct QueryExpected: Decodable { let placed: [WidgetId]; let hidden: [WidgetId] }

    @Test("placed and hidden match")
    func queriesMatch() throws {
        let fixture = try GoldenFixture<QueryInput, QueryExpected>.load("layout-queries")
        for c in fixture.cases {
            #expect(Dashboard.placedWidgets(c.input.layout) == c.expected.placed, "placedWidgets — \(c.name)")
            #expect(Dashboard.hiddenWidgets(c.input.layout) == c.expected.hidden, "hiddenWidgets — \(c.name)")
        }
    }

    @Test("the wire form matches, the other side carried through unparsed")
    func serializeMatches() throws {
        let cases = try loadRaw("layout-serialize")
        for c in cases {
            let name = c["name"] as! String
            let input = c["input"] as! [String: Any]
            let layout = try decodeLayout(input["layout"]!)
            let surface = DashboardSurface(rawValue: input["surface"] as! String)!
            let other = input["other"]
            let actual = Dashboard.serializeLayout(layout, surface: surface, other: other)
            let expected = c["expected"] as! [String: Any]
            #expect(NSDictionary(dictionary: actual).isEqual(to: expected), "serializeLayout — \(name)")
        }
    }
}
