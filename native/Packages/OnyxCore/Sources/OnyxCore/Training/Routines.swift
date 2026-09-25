import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// `routines` rows → `Program` values. The generic half of decision D1.
//
// A routine row is one program day: its key, label, weekday, colour and a
// jsonb payload holding the exercises. There is no child table — the mirror
// generator has none, and a second bespoke puller for fourteen rows was not
// worth owning — so the payload is decoded here, once, into the same
// `ProgramExercise` the logger has always drawn.
//
// MOVERS COME FROM THE ANATOMY, NOT THE PAYLOAD. `ProgramExercise.init` asks
// `MuscleMap` by name, exactly as the compiled deck did; a payload that carried
// its own primary/secondary lists would be a second copy of the anatomy that
// looks right until it is nudged. The payload names the movement and the
// prescription, and nothing else.
// ─────────────────────────────────────────────────────────────────────────────

/// One exercise inside `routines.payload.exercises`. Keys are the wire format
/// the seed wrote and W5's builder will write; add, never rename.
public struct RoutineExercise: Codable, Equatable, Sendable {
    public var name: String
    /// `exercises.id`, when the catalogue has resolved this movement.
    public var exerciseId: String?
    public var sets: Int
    public var cutSets: Int?
    public var reps: String
    public var restSec: Int?
    public var wk1Kg: Double?
    public var compound: Bool?
    public var note: String?

    public init(
        name: String, exerciseId: String? = nil, sets: Int, cutSets: Int? = nil, reps: String,
        restSec: Int? = nil, wk1Kg: Double? = nil, compound: Bool? = nil, note: String? = nil
    ) {
        self.name = name; self.exerciseId = exerciseId; self.sets = sets; self.cutSets = cutSets
        self.reps = reps; self.restSec = restSec; self.wk1Kg = wk1Kg; self.compound = compound; self.note = note
    }

    /// A movement just picked, with a starting prescription rather than blanks:
    /// three sets of 8–12 with two minutes' rest is what most people would have
    /// typed, and a row of empty fields is a row of decisions.
    ///
    /// One definition, two callers: the routine builder's "Add a movement" and
    /// the logger's mid-session add (W3). Two copies of "what a new movement
    /// opens with" is how the builder and the deck come to disagree about it.
    public static func starting(_ name: String) -> RoutineExercise {
        RoutineExercise(
            name: name, sets: 3, reps: "8–12", restSec: 120,
            compound: MuscleMap.resolveMovers(name).secondary.isEmpty == false
        )
    }

    public var programExercise: ProgramExercise {
        ProgramExercise(
            name, exerciseId: exerciseId, sets: sets, cutSets: cutSets, wk1Kg: wk1Kg, reps: reps,
            restSec: restSec, compound: compound ?? false, note: note
        )
    }
}

/// `routines.payload`. `version` is read and ignored at 1; a future shape
/// bumps it and decodes the old one explicitly.
public struct RoutinePayload: Codable, Equatable, Sendable {
    public var version: Int
    public var exercises: [RoutineExercise]

    public init(version: Int = 1, exercises: [RoutineExercise]) {
        self.version = version
        self.exercises = exercises
    }

    public static func decode(_ json: String) -> RoutinePayload? {
        try? JSONDecoder().decode(RoutinePayload.self, from: Data(json.utf8))
    }

    public func encoded() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? enc.encode(self)) ?? Data("{\"version\":1,\"exercises\":[]}".utf8), as: UTF8.self)
    }
}

/// One `routines` row, as the domain needs it. The store maps its mirror row
/// onto this; OnyxCore never sees GRDB.
public struct RoutineDay: Codable, Equatable, Sendable {
    public var programId: String
    public var dayKey: String
    public var label: String
    public var sub: String?
    /// 0 = Sunday … 6 = Saturday.
    public var weekday: Int
    /// 0xRRGGBB.
    public var accent: Int
    public var sort: Int
    public var payload: RoutinePayload
    /// `routines.notes` — the day's own note (Precision E1). nil until someone
    /// writes one; an emptied note is `""`, not nil, so the push can clear the
    /// server's copy without naming a column a pre-DDL server lacks.
    public var notes: String?

    public init(
        programId: String, dayKey: String, label: String, sub: String? = nil,
        weekday: Int, accent: Int, sort: Int, payload: RoutinePayload, notes: String? = nil
    ) {
        self.programId = programId; self.dayKey = dayKey; self.label = label; self.sub = sub
        self.weekday = weekday; self.accent = accent; self.sort = sort; self.payload = payload
        self.notes = notes
    }

    public var programDay: ProgramDay {
        ProgramDay(
            key: dayKey, label: label, sub: sub, accent: UInt32(truncatingIfNeeded: max(0, accent)),
            weekday: weekday, exercises: payload.exercises.map(\.programExercise)
        )
    }
}

public extension Program {
    /// Every program the rows describe, days in `sort` order, labelled from
    /// the plan catalogue where a `plans` row exists for the id.
    ///
    /// A program id that appears in `routines` but not in `plans` still comes
    /// back — labelled by its id — because a deck with no catalogue entry is
    /// still a deck the logger can open; the picker simply will not list it.
    static func from(routines: [RoutineDay], plans: [PlanInfo]) -> [Program] {
        let byProgram = Dictionary(grouping: routines, by: \.programId)
        let info = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Plan order first (the picker's), then any orphan deck by id.
        let ordered = plans.map(\.id).filter { byProgram[$0] != nil }
            + byProgram.keys.filter { info[$0] == nil }.sorted()
        return ordered.map { id in
            let days = (byProgram[id] ?? [])
                .sorted { ($0.sort, $0.weekday, $0.dayKey) < ($1.sort, $1.weekday, $1.dayKey) }
                .map(\.programDay)
            return Program(id: id, label: info[id]?.label ?? id, blurb: info[id]?.blurb ?? "", days: days)
        }
    }
}
