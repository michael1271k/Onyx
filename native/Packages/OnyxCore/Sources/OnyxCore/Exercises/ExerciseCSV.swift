import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// CSV → catalogue rows. The import half of D2.
//
// A person arriving from Hevy, Strong or a spreadsheet has a movement list
// already, and retyping sixty names into a phone is the reason they would not
// arrive. So: paste or pick a file, see what it understood, then commit.
//
// ── WHAT THIS PARSER IS AND IS NOT ──────────────────────────────────────────
// It is RFC 4180 for the parts that bite — quoted fields, commas and newlines
// inside quotes, doubled quotes as an escape, CRLF — and nothing more. No
// charset detection, no delimiter sniffing beyond comma/semicolon/tab, no
// streaming. A catalogue is tens of rows, not millions.
//
// It does NOT create rows. It returns what it read and what it could not, and
// the screen decides — because the expensive mistake here is a SPLIT (the same
// movement imported under a second name, its history starting again from zero),
// and the only defence against that is a human looking at the list before it
// lands. `ExerciseIndex`'s header is the long version of why.
//
// ── THE MUSCLE COLUMN IS THE WHOLE POINT ────────────────────────────────────
// Set credit is resolved from the movement's NAME through `MuscleMap`
// (`MuscleCredit.weightedSets`), and `MuscleMap` is a hand-tuned table of the
// movements this app already knew. An imported `Zercher Squat` is not in it, so
// without tags of its own that movement earns ZERO muscle credit for the life of
// the account and nothing ever says so.
//
// `MuscleMap.resolveMovers(_:stored:)` already takes a `stored` fallback for
// exactly this. So a row's muscles are parsed here into tokens the landmark
// folder accepts, and a row that ends up with NO muscles — no column, and a name
// `MuscleMap` does not know — is reported as `unclassified` so the screen can
// say so out loud rather than importing a movement that quietly counts for
// nothing.
// ─────────────────────────────────────────────────────────────────────────────

/// One movement, as a CSV row described it.
public struct ExerciseImportRow: Equatable, Sendable {
    public var name: String
    /// Landmark tokens, `LandmarkMuscle.token` spelling. First is primary.
    public var primaryMuscle: String?
    public var secondaryMuscles: [String]
    public var equipment: String?
    /// The row said nothing about muscles AND `MuscleMap` does not know the
    /// name — so this movement would earn no set credit. Imported anyway, on
    /// purpose: a logged set is still a logged set, and the screen warns.
    public var isUnclassified: Bool
    /// A catalogue row of this name already exists. Skipped, never merged.
    public var isDuplicate: Bool
    /// 1-based position among the file's NON-BLANK lines. Close enough to point
    /// a person at the row; not a byte offset.
    public var line: Int

    public init(
        name: String, primaryMuscle: String? = nil, secondaryMuscles: [String] = [],
        equipment: String? = nil, isUnclassified: Bool = false, isDuplicate: Bool = false,
        line: Int
    ) {
        self.name = name; self.primaryMuscle = primaryMuscle
        self.secondaryMuscles = secondaryMuscles; self.equipment = equipment
        self.isUnclassified = isUnclassified; self.isDuplicate = isDuplicate; self.line = line
    }

    /// Rows worth writing: everything that is not already in the catalogue.
    public var isImportable: Bool { !isDuplicate }
}

/// What one file amounted to.
public struct ExerciseImport: Equatable, Sendable {
    public var rows: [ExerciseImportRow]
    /// Lines that had no usable name, by line number. Blank lines are not
    /// errors and never appear here.
    public var skipped: [Int]
    /// The header this file turned out to have, for the screen to show back.
    public var columns: [String]
    /// The file had more rows than `maxRows` and the rest were not read.
    ///
    /// Reported rather than silent: a paste that comes back "500 movements" off
    /// a five-thousand-line file is almost certainly somebody's workout
    /// HISTORY, and importing five hundred junk exercises without a word is the
    /// failure this whole screen exists to prevent.
    public var wasTruncated: Bool

    public init(rows: [ExerciseImportRow], skipped: [Int], columns: [String], wasTruncated: Bool = false) {
        self.rows = rows; self.skipped = skipped; self.columns = columns
        self.wasTruncated = wasTruncated
    }

    public var importable: [ExerciseImportRow] { rows.filter(\.isImportable) }
    public var duplicates: Int { rows.filter(\.isDuplicate).count }
    public var unclassified: Int { rows.filter { $0.isImportable && $0.isUnclassified }.count }
    public var isEmpty: Bool { rows.isEmpty }
}

public enum ExerciseCSV {

    /// Rows above which an import is refused.
    ///
    /// Not a performance limit — a paste of the wrong file. A 5,000-line CSV is
    /// someone's workout history, not their movement list, and importing it
    /// would bury the catalogue under set rows misread as exercise names.
    public static let maxRows = 500

    // MARK: - Columns

    /// Header spellings, lowercased, that name each field. Checked by exact
    /// match first and then by containment, so `Primary Muscle Group` lands on
    /// the primary column without `muscle` alone claiming it.
    static let nameHeaders = ["exercise name", "exercise", "name", "movement", "title"]
    static let primaryHeaders = ["primary muscle", "primary muscle group", "muscle group", "primary", "muscle", "body part", "target"]
    static let secondaryHeaders = ["secondary muscle", "secondary muscles", "secondary muscle group", "secondary", "other muscles", "synergists"]
    static let equipmentHeaders = ["equipment", "equipment type", "gear", "category"]

    /// Delimiters worth trying, in order. A European export is semicolon-
    /// separated and would otherwise parse as one column per line.
    static let delimiters: [Character] = [",", ";", "\t"]

    // MARK: - The entry point

    /// Parse a CSV, deduplicated against the names already in the catalogue.
    ///
    /// - Parameter existingNames: every catalogue name. Compared case- and
    ///   whitespace-insensitively, the same `exactKey` rule `ExerciseIndex` uses
    ///   to resolve a name to a row — so "what this import calls a duplicate"
    ///   and "what the sync calls the same movement" cannot disagree.
    public static func parse(_ text: String, existingNames: [String] = []) -> ExerciseImport {
        let delimiter = bestDelimiter(text)
        let grid = rows(text, delimiter: delimiter)
        guard !grid.isEmpty else { return ExerciseImport(rows: [], skipped: [], columns: []) }

        let (header, body, firstLine) = split(grid)
        let index = ColumnIndex(header)
        let existing = Set(existingNames.map(key))

        var out: [ExerciseImportRow] = []
        var skipped: [Int] = []
        var seen = Set<String>()
        var truncated = false

        for (offset, fields) in body.enumerated() where !isBlank(fields) {
            let line = firstLine + offset
            guard out.count < maxRows else { truncated = true; break }

            let name = clean(index.value(fields, index.name))
            guard !name.isEmpty else { skipped.append(line); continue }

            // A file that names the same movement twice is deduplicated against
            // ITSELF as well as the catalogue; otherwise the second copy writes
            // a second row with the same name and the unique index rejects the
            // whole batch.
            let k = key(name)
            guard !seen.contains(k) else { skipped.append(line); continue }
            seen.insert(k)

            let primary = muscles(index.value(fields, index.primary)).first
            let secondary = muscles(index.value(fields, index.secondary))
                .filter { $0 != primary }
            let named = MuscleMap.movers(name) != nil

            out.append(ExerciseImportRow(
                name: name,
                primaryMuscle: primary,
                secondaryMuscles: secondary,
                equipment: clean(index.value(fields, index.equipment)).nilIfEmpty,
                isUnclassified: primary == nil && secondary.isEmpty && !named,
                isDuplicate: existing.contains(k),
                line: line
            ))
        }
        return ExerciseImport(rows: out, skipped: skipped, columns: header, wasTruncated: truncated)
    }

    // MARK: - Muscles

    /// `"Chest, Triceps"` → `["Chest", "Triceps"]` as landmark tokens.
    ///
    /// Anything the landmark folder does not recognise is DROPPED rather than
    /// stored raw. A stored `"Serratus"` would fold to nil at credit time and
    /// look, in the database, exactly like a muscle that had been recorded.
    static func muscles(_ field: String) -> [String] {
        field
            .split(whereSeparator: { ",;/|&".contains($0) })
            .compactMap { LandmarkMuscle.from(token: String($0).trimmingCharacters(in: .whitespaces)) }
            .reduce(into: [LandmarkMuscle]()) { acc, m in if !acc.contains(m) { acc.append(m) } }
            .map(\.token)
    }

    /// `ExerciseIndex.exactKey`, by the same rule and for the same reason.
    static func key(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - The grid

    /// The delimiter that yields the most columns on the first non-blank line.
    static func bestDelimiter(_ text: String) -> Character {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return delimiters.max { a, b in
            fields(line, delimiter: a).count < fields(line, delimiter: b).count
        } ?? ","
    }

    /// Header row and body, or a headerless file's rows.
    ///
    /// A file with no recognisable header is still imported: its first column is
    /// taken as the name and its first line is DATA, because "Bench Press" on
    /// line one of a bare list is a movement, not a heading.
    static func split(_ grid: [[String]]) -> (header: [String], body: [[String]], firstLine: Int) {
        let first = grid[0].map { clean($0).lowercased() }
        let looksLikeHeader = first.contains { field in
            nameHeaders.contains(field) || primaryHeaders.contains(field)
                || secondaryHeaders.contains(field) || equipmentHeaders.contains(field)
        }
        return looksLikeHeader
            ? (grid[0].map(clean), Array(grid.dropFirst()), 2)
            : ([], grid, 1)
    }

    static func isBlank(_ fields: [String]) -> Bool {
        fields.allSatisfy { clean($0).isEmpty }
    }

    static func clean(_ field: String) -> String {
        field.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split a whole document into rows of fields, honouring quotes.
    static func rows(_ text: String, delimiter: Character) -> [[String]] {
        var out: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !isBlank(row) { out.append(row) }
            row = []
        }

        while let character = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if character == "\"" {
                    // A doubled quote inside a quoted field is one literal quote.
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            // ── `isNewline`, NOT a literal "\n" ─────────────────────────────
            // Swift grapheme-clusters CRLF into ONE `Character`, so a `case
            // "\n"` never fires on a Windows export and the whole file parses
            // as a single unterminated row — which reads as "0 exercises
            // found" on a file that plainly has sixty in it. `isNewline` also
            // covers the Unicode line separators a spreadsheet can emit.
            switch character {
            case "\"" where field.isEmpty: quoted = true
            case delimiter:               endField()
            case _ where character.isNewline: endRow()
            default:                      field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return out
    }

    /// One line's fields. Used only to compare delimiters.
    static func fields(_ line: String, delimiter: Character) -> [String] {
        rows(line, delimiter: delimiter).first ?? []
    }

    // MARK: - Header lookup

    struct ColumnIndex {
        var name: Int?
        var primary: Int?
        var secondary: Int?
        var equipment: Int?

        init(_ header: [String]) {
            let lower = header.map { ExerciseCSV.clean($0).lowercased() }
            // Secondary is matched BEFORE primary: `secondary muscle` contains
            // `muscle`, and a containment pass that ran primary first would
            // claim it and leave the real primary column unread.
            secondary = Self.find(lower, ExerciseCSV.secondaryHeaders, excluding: [])
            primary = Self.find(lower, ExerciseCSV.primaryHeaders, excluding: [secondary])
            equipment = Self.find(lower, ExerciseCSV.equipmentHeaders, excluding: [secondary, primary])
            name = Self.find(lower, ExerciseCSV.nameHeaders, excluding: [secondary, primary, equipment])
                // No header, or none that names a column: the first field is
                // the name. Every bare list in the world is shaped that way.
                ?? (header.isEmpty ? 0 : nil)
        }

        static func find(_ header: [String], _ candidates: [String], excluding: [Int?]) -> Int? {
            let taken = Set(excluding.compactMap { $0 })
            if let exact = header.indices.first(where: {
                !taken.contains($0) && candidates.contains(header[$0])
            }) { return exact }
            return header.indices.first { index in
                !taken.contains(index) && candidates.contains { header[index].contains($0) }
            }
        }

        func value(_ fields: [String], _ index: Int?) -> String {
            guard let index, index < fields.count else { return "" }
            return fields[index]
        }
    }
}

private extension String {
    /// `public` since W7: `TargetsApply` wanted the same one line and wrote a
    /// second copy of it in OnyxData before `code-reviewer` found the first.
    public var nilIfEmpty: String? { isEmpty ? nil : self }
}
