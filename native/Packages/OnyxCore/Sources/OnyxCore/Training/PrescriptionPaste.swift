import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// A PASTED BLOCK → PRESCRIPTIONS.
//
// The coach's weekly audit arrives as prose with tables in it — a "Lifting
// Actions" table one week, a "W10 plan" table the next — and the shapes are not
// stable, because a person writes them. So this parser is TOLERANT by design
// and LOUD about what it could not read: it maps the columns it recognises, it
// scans every cell it does not recognise for a figure it can still use, and it
// hands back the lines it gave up on so the paste screen can show them.
//
// ── IT NEVER WRITES WITHOUT BEING SHOWN ─────────────────────────────────────
// Nothing here reaches the database. `parse` returns a preview; the screen
// renders it, the athlete confirms it, and only then does a version land. A
// parser that guesses is fine. A parser that guesses SILENTLY is not, because
// the number it invents becomes the baseline every later `load Δ` is drawn
// against.
// ─────────────────────────────────────────────────────────────────────────────

public enum PrescriptionPaste {

    public struct Result: Equatable, Sendable {
        /// What was read, in the order it was written.
        public var rows: [Prescription]
        /// Lines that looked like they meant something and could not be read.
        /// Shown to the athlete verbatim — an unparsed instruction is a finding,
        /// not litter.
        public var skipped: [String]
        /// Per-row notes about a field the parser could not find: `"Lat
        /// Pulldown — no load"`. The row still lands; the gap is stated.
        public var warnings: [String]
    }

    // MARK: - Header vocabulary

    /// Header cell → the field it names. Matched on a LOWERCASED, punctuation-
    /// stripped cell, longest phrase first, so `rep range` cannot be claimed by
    /// `reps` and `rpe cap` cannot be claimed by `rpe`.
    enum Field: CaseIterable {
        case exercise, load, sets, reps, setsAndReps, rpe, structure, lead, notes

        var synonyms: [String] {
            switch self {
            case .exercise:    return ["exercise", "movement", "lift", "name"]
            case .load:        return ["load kg", "weight kg", "top set", "load", "weight", "kg"]
            case .sets:        return ["sets", "set"]
            case .reps:        return ["rep range", "rep_range", "target reps", "reps", "range"]
            case .setsAndReps: return ["sets x reps", "sets reps", "sets/reps", "prescription", "scheme"]
            case .rpe:         return ["rpe cap", "rpe_cap", "cap", "rpe"]
            case .structure:   return ["structure", "style", "shape"]
            case .lead:        return ["lead rule", "lead_rule", "lead", "laterality", "side"]
            case .notes:       return ["notes", "note", "action", "comment", "cue"]
            }
        }
    }

    /// `"Load (kg)"` → `"load kg"`. Everything that is not a letter, a digit or
    /// a space becomes a space, so a header may be punctuated however the coach
    /// likes.
    static func headerKey(_ raw: String) -> String {
        let flat = raw.lowercased().map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : " "
        }
        return String(flat).split(separator: " ").joined(separator: " ")
    }

    static func field(forHeader raw: String) -> Field? {
        let key = headerKey(raw)
        guard !key.isEmpty else { return nil }
        // `setsAndReps` first: "sets x reps" contains "sets", and the combined
        // column has to win or the reps half is thrown away.
        for f in [Field.setsAndReps, .exercise, .load, .reps, .sets, .rpe, .structure, .lead, .notes] {
            if f.synonyms.contains(where: { key == $0 || key.hasPrefix($0 + " ") || key.hasSuffix(" " + $0) }) { return f }
        }
        return nil
    }

    // MARK: - Entry

    /// Parse a pasted block. `effectiveFrom` is the day the athlete says the
    /// new prescription starts — the paste screen's date, never inferred from
    /// the text, because a table rarely carries one and a wrong date silently
    /// re-dates the whole history.
    public static func parse(_ text: String, effectiveFrom: String) -> Result {
        var rows: [Prescription] = []
        var skipped: [String] = []
        var warnings: [String] = []
        var columns: [Field?] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if isTableRow(line) {
                let cells = tableCells(line)
                if isRule(cells) { continue }
                if let mapped = headerMap(cells) { columns = mapped; continue }
                if let p = fromCells(cells, columns: columns, effectiveFrom: effectiveFrom, warnings: &warnings) {
                    rows.append(p)
                } else if !cells.joined().trimmingCharacters(in: .whitespaces).isEmpty {
                    skipped.append(line)
                }
                continue
            }
            // Not a table. A heading or a sentence with no figures in it is
            // not an instruction and is dropped in silence; anything else is
            // tried as a freeform prescription.
            if let p = fromFreeform(line, effectiveFrom: effectiveFrom, warnings: &warnings) {
                rows.append(p)
            } else if looksLikeAnInstruction(line) {
                skipped.append(line)
            }
        }
        return Result(rows: rows, skipped: skipped, warnings: warnings)
    }

    // MARK: - Tables

    static func isTableRow(_ line: String) -> Bool {
        line.filter { $0 == "|" }.count >= 2
    }

    static func tableCells(_ line: String) -> [String] {
        var body = Substring(line)
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|") { body = body.dropLast() }
        return body.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// `|---|:--:|` — the rule under a markdown header.
    static func isRule(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { "-:= ".contains($0) }
        }
    }

    /// A header row, or nil. A row is a header only when one of its cells names
    /// the EXERCISE column: without it there is nothing to key a prescription
    /// on, and a data row full of words would otherwise be read as headers.
    static func headerMap(_ cells: [String]) -> [Field?]? {
        let mapped = cells.map(field(forHeader:))
        guard mapped.contains(where: { $0 == .exercise }) else { return nil }
        return mapped
    }

    static func fromCells(
        _ cells: [String], columns: [Field?], effectiveFrom: String, warnings: inout [String]
    ) -> Prescription? {
        var byField: [Field: String] = [:]
        var loose: [String] = []
        for (i, cell) in cells.enumerated() {
            guard !cell.isEmpty else { continue }
            if i < columns.count, let f = columns[i] { byField[f] = cell } else { loose.append(cell) }
        }
        /* NO HEADER AT ALL — a bare table pasted without its heading row. The
           first cell is the movement and every other cell is scanned for
           figures, which is exactly the `loose` path below. */
        let name = byField[.exercise] ?? (columns.isEmpty ? cells.first(where: { !$0.isEmpty }) : nil)
        guard let name, !name.isEmpty, name.contains(where: \.isLetter) else { return nil }
        if columns.isEmpty { loose = Array(cells.dropFirst()) }

        var p = Prescription(exercise: ExerciseAliases.canonicalName(cleanName(name)), effectiveFrom: effectiveFrom)
        apply(byField[.load], to: &p, as: .load)
        apply(byField[.sets], to: &p, as: .sets)
        apply(byField[.reps], to: &p, as: .reps)
        apply(byField[.setsAndReps], to: &p, as: .setsAndReps)
        apply(byField[.rpe], to: &p, as: .rpe)
        apply(byField[.structure], to: &p, as: .structure)
        apply(byField[.lead], to: &p, as: .lead)
        if let n = byField[.notes], !n.isEmpty { p.notes = n }

        /* ── EVERY CELL IS STILL EVIDENCE ──────────────────────────────────
           The "Lifting Actions" table is two columns — a movement and a
           sentence — and the sentence is where the new load lives. That cell
           IS mapped, to `notes`, so scanning only the unclaimed cells found
           nothing at all. Every cell but the name is scanned, and only for
           what is still missing: a mapped column always wins over a figure
           found in prose, because `scavenge` never overwrites. */
        for cell in loose { scavenge(cell, into: &p) }
        /* Only the PROSE columns. A `Sets` cell holding `3` says three sets and
           nothing else; scanning it for a load read a bodyweight plank as three
           kilograms. A column that names its own meaning has already been
           read — what is left to scan is the writing. */
        for f in [Field.notes, .structure, .lead] {
            guard let cell = byField[f] else { continue }
            scavenge(cell, into: &p)
        }
        if p.notes == nil, let prose = loose.first(where: { $0.contains(where: \.isLetter) && $0.count > 3 }) {
            p.notes = prose
        }
        finish(&p, warnings: &warnings)
        return p
    }

    // MARK: - Freeform

    /// `Incline DB Press — 34 kg × 3 × 8–12 @8 (alternate)`
    static func fromFreeform(_ line: String, effectiveFrom: String, warnings: inout [String]) -> Prescription? {
        // The name is everything before the first separator the coach uses, or
        // before the first figure if there is none.
        var name = ""
        var tail = ""
        for sep in ["—", "–", " - ", ":", "→", "->"] {
            if let r = line.range(of: sep) {
                name = String(line[line.startIndex..<r.lowerBound])
                tail = String(line[r.upperBound...])
                break
            }
        }
        if name.isEmpty {
            guard let split = firstFigureIndex(line) else { return nil }
            name = String(line[line.startIndex..<split])
            tail = String(line[split...])
        }
        let cleaned = cleanName(name)
        guard cleaned.count >= 3, cleaned.contains(where: \.isLetter),
              tail.contains(where: \.isNumber) else { return nil }
        var p = Prescription(exercise: ExerciseAliases.canonicalName(cleaned), effectiveFrom: effectiveFrom)
        scavenge(tail, into: &p)
        finish(&p, warnings: &warnings)
        return p
    }

    /// Where the figures start — the first digit that is not part of a name
    /// ("Row 2" is a movement, "34 kg" is a load), which in practice is the
    /// first digit followed anywhere later by a unit or an operator.
    static func firstFigureIndex(_ line: String) -> String.Index? {
        var i = line.startIndex
        while i < line.endIndex {
            if line[i].isNumber { return i }
            i = line.index(after: i)
        }
        return nil
    }

    /// A line with no figures in it is prose, not an instruction, and a
    /// markdown heading is a heading however many digits the week number puts
    /// in it. Neither is reported as something the parser refused.
    static func looksLikeAnInstruction(_ line: String) -> Bool {
        guard !line.hasPrefix("#"), !line.hasPrefix(">") else { return false }
        return line.contains(where: \.isNumber) && line.contains(where: \.isLetter) && line.count > 6
    }

    // MARK: - Field scanning

    private enum Slot { case load, sets, reps, setsAndReps, rpe, structure, lead }

    private static func apply(_ raw: String?, to p: inout Prescription, as slot: Slot) {
        guard let raw, !raw.isEmpty else { return }
        switch slot {
        case .load:
            if let loads = loadList(raw) { setLoads(loads, on: &p) }
        case .sets:
            if let n = firstInteger(raw) { p.sets = n }
        case .reps:
            if let w = repWindowText(raw) { p.repRange = w }
        case .setsAndReps:
            // `3 × 8–12` — one column holding both, read by the one rule.
            let counts = setsAndReps(in: raw)
            if let n = counts.sets { p.sets = n }
            if let w = counts.reps { p.repRange = w }
        case .rpe:
            if let v = firstDouble(raw) { p.rpeCap = v }
        case .structure:
            if let s = structure(in: raw) { p.structure = s }
        case .lead:
            if let l = lead(in: raw) { p.leadRule = l }
        }
    }

    /// Read every field this text can still answer, never overwriting one that
    /// is already answered.
    static func scavenge(_ text: String, into p: inout Prescription) {
        if p.setLoads == nil && p.loadKg == nil, let loads = loadList(text) { setLoads(loads, on: &p) }
        if p.rpeCap == nil, let v = rpe(in: text) { p.rpeCap = v }
        /* ── THE LOAD COMES OUT BEFORE THE COUNTS GO IN ─────────────────────
           `34 kg × 3 × 8–12` and `3 × 8–12` mean the same three sets of the
           same window, and a rule that reads "the number before the ×" gets
           34 from the first and 3 from the second. Striking the `NN kg` token
           out first makes the two spellings identical, which is the only way
           one rule can read both. */
        let rest = withoutLoads(text)
        if p.sets == nil || p.repRange == nil {
            let counts = setsAndReps(in: rest)
            if p.sets == nil { p.sets = counts.sets }
            if p.repRange == nil { p.repRange = counts.reps }
        }
        if p.structure == .straight, let s = structure(in: text) { p.structure = s }
        if p.leadRule == .none, let l = lead(in: text) { p.leadRule = l }
    }

    /// The text with every `NN kg` figure struck out.
    static func withoutLoads(_ text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?\s*kg"#, options: .caseInsensitive)
        else { return text }
        let ns = text as NSString
        return re.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
    }

    /// `3 × 8–12` in any of its spellings, from text the loads have left.
    ///
    /// Split on the multiplication sign; the first piece ending in a WHOLE
    /// number names the sets and the next piece carries the window. Whole,
    /// because `42.5 / 37.5 × 2` is a load ladder and `37.5` must not be read
    /// as thirty-seven sets — or, worse, as five.
    static func setsAndReps(in text: String) -> (sets: Int?, reps: String?) {
        var pieces: [String] = []
        var current = ""
        for ch in text {
            if ch == "×" || ch == "x" || ch == "X" { pieces.append(current); current = "" }
            else { current.append(ch) }
        }
        pieces.append(current)
        guard pieces.count > 1 else { return (nil, repWindowText(text)) }
        for (i, piece) in pieces.enumerated() where i + 1 < pieces.count {
            guard let n = trailingWholeNumber(piece), (1...12).contains(n) else { continue }
            return (n, repWindowText(pieces[i + 1]))
        }
        return (nil, repWindowText(text))
    }

    /// The whole number a piece ENDS in — nil when the digits are the tail of a
    /// decimal, which is a load and not a count.
    static func trailingWholeNumber(_ piece: String) -> Int? {
        var digits = ""
        var index = piece.endIndex
        while index > piece.startIndex {
            let before = piece.index(before: index)
            let ch = piece[before]
            if ch == " " && digits.isEmpty { index = before; continue }
            if ch.isNumber { digits.insert(ch, at: digits.startIndex); index = before; continue }
            if ch == "." && !digits.isEmpty { return nil }
            break
        }
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func setLoads(_ loads: [Double], on p: inout Prescription) {
        if loads.count > 1 {
            p.setLoads = loads
            p.structure = .topsetBackoff
            p.loadKg = loads.first
        } else {
            p.loadKg = loads.first
        }
    }

    /// `"40"`, `"40 kg"`, `"40/32.5/32.5"`, `"40 then 32.5 × 2"` — the loads in
    /// order, top set first. Nil when the text states no load at all.
    ///
    /// `× 2` after a load REPEATS it: "32.5 × 2" in a load column is two
    /// back-off sets at 32.5, not a load of 32.5 and two reps. A rep count
    /// never appears in a load cell, and the repeat form is how a coach writes
    /// a back-off pair.
    static func loadList(_ text: String) -> [Double]? {
        let normalised = text
            .replacingOccurrences(of: "then", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "→", with: "/")
            .replacingOccurrences(of: "->", with: "/")
        var out: [Double] = []
        for chunk in normalised.split(separator: "/") {
            let piece = String(chunk)
            guard let value = firstDouble(piece), value > 0 else { continue }
            var repeats = 1
            if let r = piece.range(of: "×") ?? piece.range(of: "x", options: .caseInsensitive),
               let n = firstInteger(String(piece[r.upperBound...])), n > 1, n <= 12 {
                repeats = n
            }
            out.append(contentsOf: Array(repeating: value, count: repeats))
        }
        // A bodyweight prescription states no load and is not a parse failure.
        return out.isEmpty ? nil : out
    }

    static func rpe(in text: String) -> Double? {
        let lower = text.lowercased()
        for marker in ["rpe", "@"] {
            guard let r = lower.range(of: marker) else { continue }
            if let v = firstDouble(String(text[r.upperBound...])), (1...10).contains(v) { return v }
        }
        return nil
    }



    /// The window as WRITTEN, normalised to an en dash. A `kg` figure is not a
    /// window and a `s` figure is a hold, which passes through untouched.
    static func repWindowText(_ text: String) -> String? {
        let scalars = Array(text)
        var i = 0
        while i < scalars.count {
            guard scalars[i].isNumber else { i += 1; continue }
            var j = i
            while j < scalars.count, scalars[j].isNumber || scalars[j] == "." { j += 1 }
            let first = String(scalars[i..<j])
            // A unit disqualifies it as a rep window.
            let after = String(scalars[j...]).trimmingCharacters(in: .whitespaces).lowercased()
            if after.hasPrefix("kg") || after.hasPrefix("%") { i = j; continue }
            if after.hasPrefix("s") && !after.hasPrefix("sets") && !after.hasPrefix("set") {
                return first + "s"
            }
            var k = j
            while k < scalars.count, scalars[k] == " " { k += 1 }
            if k < scalars.count, "–—-".contains(scalars[k]) {
                var m = k + 1
                while m < scalars.count, scalars[m] == " " { m += 1 }
                var n = m
                while n < scalars.count, scalars[n].isNumber { n += 1 }
                if n > m { return first + "–" + String(scalars[m..<n]) }
            }
            return first
        }
        return nil
    }

    static func structure(in text: String) -> Prescription.Structure? {
        let lower = text.lowercased()
        if lower.contains("topset") || lower.contains("top set") || lower.contains("back-off")
            || lower.contains("backoff") || lower.contains("back off") { return .topsetBackoff }
        if lower.contains("straight") { return .straight }
        return nil
    }

    static func lead(in text: String) -> Prescription.LeadRule? {
        let lower = text.lowercased()
        if lower.contains("alternat") { return .alternate }
        if lower.contains("left") || lower.contains("l lead") || lower.contains("lead l") { return .left }
        if lower.contains("right") || lower.contains("r lead") || lower.contains("lead r") { return .right }
        // `NONE` is stated as often as it is left blank, and it is the default —
        // recognised so a cell saying so is not reported as unread.
        if lower.contains("none") || lower.contains("bilateral") { return Prescription.LeadRule.none }
        return nil
    }

    // MARK: - Numbers

    static func firstDouble(_ text: String) -> Double? {
        var digits = ""
        for ch in text {
            if ch.isNumber || (ch == "." && !digits.isEmpty) { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        return Double(digits)
    }

    static func firstInteger(_ text: String) -> Int? {
        firstDouble(text).map { Int($0) }
    }

    static func lastInteger(_ text: String) -> Int? {
        var best: Int?
        var digits = ""
        for ch in text {
            if ch.isNumber { digits.append(ch) }
            else if !digits.isEmpty { best = Int(digits); digits = "" }
        }
        if !digits.isEmpty { best = Int(digits) }
        return best
    }


    /// A movement name as a table writes it — bold markers, trailing colons and
    /// leading list bullets are decoration, not part of the lift.
    static func cleanName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        for junk in ["**", "__", "`", "*", "•", "-", "–", "—", ":"] {
            while s.hasPrefix(junk) { s = String(s.dropFirst(junk.count)).trimmingCharacters(in: .whitespaces) }
            while s.hasSuffix(junk) { s = String(s.dropLast(junk.count)).trimmingCharacters(in: .whitespaces) }
        }
        return s
    }

    static func finish(_ p: inout Prescription, warnings: inout [String]) {
        if let loads = p.setLoads, loads.count <= 1 { p.setLoads = nil; p.structure = .straight }
        if p.structure == .topsetBackoff, p.setLoads == nil, let load = p.loadKg {
            // Named a top set without listing the back-offs: the one load IS
            // the top set and the rest is unknown, which is a straight
            // prescription with a note on it rather than an invented ladder.
            p.setLoads = [load]
        }
        if p.loadKg == nil && p.setLoads == nil { warnings.append("\(p.exercise) — no load") }
        if p.repRange == nil { warnings.append("\(p.exercise) — no rep range") }
    }
}
