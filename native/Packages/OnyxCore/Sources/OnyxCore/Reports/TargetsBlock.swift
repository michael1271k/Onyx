import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// PASTE-BACK, STRUCTURED (decision 23).
//
// The loop has been half-open since the reports screen was built: the app hands
// a model a week, the model hands back a document, and the document goes into a
// text column where nothing reads it. This is the other half — a fenced block
// the report may carry, naming the targets the week should run on.
//
// ── WHY A FENCED BLOCK AND NOT A PARSE OF THE PROSE ─────────────────────────
// Because the prose is not ours. A coaching report is written for a person,
// says "push protein to about 175" in the middle of a paragraph, and hedges.
// Reading numbers out of that is a guess with a write behind it. A fenced block
// with an info string is a thing the writer had to mean: it is not produced by
// accident, it is not produced by rounding a sentence, and when it is absent
// the answer is cleanly "no targets in this report" rather than a low-confidence
// number nobody typed.
//
// ── AND WHY THE EXPORT PRINTS THE SCHEMA ────────────────────────────────────
// `WeeklyExport`'s §9 prints this shape at the bottom of every document, so the
// model that is asked to audit the week is told, in the same breath, how to
// answer in a form the app can read. The schema and the parser are one change:
// move a key here and §9 is wrong.
// ─────────────────────────────────────────────────────────────────────────────

/// The block's contents.
///
/// Every field but `weekStart` is optional, and an absent field means "no
/// opinion" — never zero. A report that only wants protein moved sends only
/// protein.
public struct TargetsBlock: Codable, Equatable, Sendable {

    /// The rung a report is selecting, by `target_profiles.key`.
    ///
    /// `value` and `unit` are carried for the PREVIEW and never written: a rung
    /// is a stored row with a whole shape to it, and a paste that could mint one
    /// from two fields would let a report invent a profile the athlete never
    /// made. A report that wants different numbers states them in
    /// `dailyTargets`, which is the app's own "my own numbers" path.
    public struct Lever: Codable, Equatable, Sendable {
        public var key: String
        public var value: Double?
        public var unit: String?

        public init(key: String, value: Double? = nil, unit: String? = nil) {
            self.key = key
            self.value = value
            self.unit = unit
        }
    }

    /// The standing daily numbers.
    ///
    /// Named `dailyTargets` on the wire because that is what a reader calls
    /// them — the numbers a day is graded against. They are NOT the
    /// `daily_targets` TABLE, which holds one-off per-date overrides; these go
    /// to `user_goals` and the plan-phase override, the same pair the You tab
    /// writes.
    public struct DailyTargets: Codable, Equatable, Sendable {
        public var kcal: Double?
        public var proteinG: Double?
        public var carbsG: Double?
        public var fatG: Double?
        public var stepsGoal: Double?
        public var waterMl: Double?
        public var sleepHours: Double?

        public init(
            kcal: Double? = nil, proteinG: Double? = nil, carbsG: Double? = nil,
            fatG: Double? = nil, stepsGoal: Double? = nil,
            waterMl: Double? = nil, sleepHours: Double? = nil
        ) {
            self.kcal = kcal
            self.proteinG = proteinG
            self.carbsG = carbsG
            self.fatG = fatG
            self.stepsGoal = stepsGoal
            self.waterMl = waterMl
            self.sleepHours = sleepHours
        }

        /// The five the plan-phase override also holds. Water and sleep belong
        /// to the person rather than to the block, which is the same split
        /// `SettingsModel.saveGoals` / `saveRecovery` already make.
        public var hasMacros: Bool {
            kcal != nil || proteinG != nil || carbsG != nil || fatG != nil || stepsGoal != nil
        }

        public var isEmpty: Bool { !hasMacros && waterMl == nil && sleepHours == nil }
    }

    /// ISO date. The week these targets come into force FROM.
    public var weekStart: String
    public var levers: [Lever]?
    public var dailyTargets: DailyTargets?
    public var note: String?

    public init(
        weekStart: String, levers: [Lever]? = nil,
        dailyTargets: DailyTargets? = nil, note: String? = nil
    ) {
        self.weekStart = weekStart
        self.levers = levers
        self.dailyTargets = dailyTargets
        self.note = note
    }

    /// Nothing to apply — a block that parsed but asks for no change.
    public var isEmpty: Bool {
        (levers?.isEmpty ?? true) && (dailyTargets?.isEmpty ?? true)
    }
}

/// What a document turned out to hold.
///
/// Three outcomes and not two: "no block" and "a block I could not read" are
/// different facts about the same paste, and a screen that collapses them tells
/// a user who mistyped a brace that the model simply did not answer.
public enum TargetsBlockResult: Equatable, Sendable {
    /// No fence with the `onyx-targets` info string. The ordinary case.
    case none
    /// At least one fence, none of which parsed. The string is the reason for
    /// the LAST one — what a reader needs to fix it.
    case malformed(String)
    case parsed(TargetsBlock)
}

public enum TargetsBlockParser {

    /// The info string a block has to carry.
    public static let fenceInfo = "onyx-targets"

    /// Read the targets block out of a pasted report.
    ///
    /// ── THE LAST BLOCK THAT PARSES WINS ─────────────────────────────────────
    /// A paste can hold more than one. The export's own §9 prints the SCHEMA as
    /// a worked example, so a user who pastes the export rather than the report
    /// hands this function a block — and a conversation transcript may carry a
    /// draft the model then corrected. Taking the last one that parses is the
    /// rule that gets the final answer in both cases; taking the last one
    /// FULL STOP would let a trailing example overwrite a real instruction.
    ///
    /// ── AND THE DOCUMENT'S OWN EXAMPLE IS NOT A BROKEN REPORT ───────────────
    /// §9's example is a real fence whose `weekStart` is the literal
    /// `YYYY-MM-DD`, so pasting the EXPORT instead of the reply — the commonest
    /// mistake there is — used to come back `.malformed` and draw a red banner
    /// saying the model's answer was unreadable. It is `.none`: the placeholder
    /// is the schema announcing itself, not a date somebody got wrong.
    /// `2026-02-30` is still `.malformed`, because that one IS a mistake.
    public static func parse(_ text: String) -> TargetsBlockResult {
        let blocks = fencedBodies(text)
        guard !blocks.isEmpty else { return .none }
        var lastFailure: String?
        for body in blocks.reversed() {
            switch decode(body) {
            case .parsed(let block): return .parsed(block)
            case .malformed(let reason): lastFailure = lastFailure ?? reason
            case .none: continue
            }
        }
        return lastFailure.map { .malformed($0) } ?? TargetsBlockResult.none
    }

    /// The `weekStart` §9 prints. A block carrying it is the schema, not an
    /// instruction — see `parse`.
    static let schemaPlaceholder = "YYYY-MM-DD"

    // MARK: - The fence

    /// Every body under a fence whose info string is exactly `onyx-targets`.
    ///
    /// Hand-scanned rather than regexed: a fence is a line-oriented construct
    /// (a run of at least three backticks or tildes, closed by a run of the
    /// same character at least as long and carrying no info string), and the
    /// body between them is arbitrary text that may itself contain backticks.
    static func fencedBodies(_ text: String) -> [String] {
        var out: [String] = []
        var open: (marker: Character, length: Int, body: [Substring])?
        // CRLF first. A report pasted out of a browser arrives with `\r\n`,
        // and a stray `\r` on a closing fence is enough to make the fence stop
        // looking like one — which loses the whole block for an invisible byte.
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalised.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " }
            let marker = trimmed.first
            let run = (marker == "`" || marker == "~") ? trimmed.prefix { $0 == marker }.count : 0

            if var current = open {
                // A closing fence is the same character, at least as long, and
                // nothing else on the line.
                if marker == current.marker, run >= current.length,
                   trimmed.dropFirst(run).allSatisfy({ $0.isWhitespace })
                {
                    out.append(current.body.joined(separator: "\n"))
                    open = nil
                } else {
                    current.body.append(line)
                    open = current
                }
                continue
            }

            guard run >= 3, let marker else { continue }
            let info = trimmed.dropFirst(run).trimmingCharacters(in: .whitespacesAndNewlines)
            guard info.lowercased() == fenceInfo else { continue }
            open = (marker, run, [])
        }
        // An unterminated fence still carries its body: a paste truncated at
        // the end is the ordinary way a long report arrives, and refusing the
        // block for a missing ``` would be refusing the whole answer.
        if let current = open, !current.body.isEmpty {
            out.append(current.body.joined(separator: "\n"))
        }
        return out
    }

    // MARK: - The JSON

    static func decode(_ body: String) -> TargetsBlockResult {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty fence is nothing, not a mistake — and the two spellings of
        // an empty fence (closed and unterminated) have to agree, which they
        // did not: one reported "the block is empty" and the other was dropped.
        guard !trimmed.isEmpty else { return .none }
        guard let data = trimmed.data(using: .utf8) else { return .malformed("the block is not text") }
        let block: TargetsBlock
        do {
            block = try JSONDecoder().decode(TargetsBlock.self, from: data)
        } catch let error as DecodingError {
            return .malformed(reason(error))
        } catch {
            return .malformed("the block is not valid JSON")
        }
        return validate(block)
    }

    /// Everything the shape cannot state, stated here.
    ///
    /// A number that is negative or not finite is not a target, and a target
    /// written from one is a number the athlete never chose. Zero is allowed:
    /// `stepsGoal: 0` is a real instruction — do not grade steps this week.
    static func validate(_ block: TargetsBlock) -> TargetsBlockResult {
        // ── AND IT HAS TO BE A DAY THAT EXISTS ──────────────────────────────
        // `ISODate.dayNumber` range-checks the month 1–12 and the day 1–31 and
        // stops there, so `2026-02-30` and `2026-04-31` decode and then
        // normalise into the following month. That string is what would be
        // shown in the preview as the date the report asked for, and — before
        // `effectiveFrom` became today unconditionally — what would have been
        // written as `lever_periods.starts_on`, which Postgres refuses.
        // Round-tripping through the day number is the whole check: a date
        // that does not exist comes back as a different string.
        if block.weekStart == TargetsBlockParser.schemaPlaceholder { return .none }
        guard let day = ISODate.dayNumber(block.weekStart),
              ISODate.iso(dayNumber: day) == block.weekStart
        else {
            return .malformed("\"weekStart\" is not an ISO date (YYYY-MM-DD)")
        }
        let numbers: [(String, Double?)] = [
            ("kcal", block.dailyTargets?.kcal),
            ("proteinG", block.dailyTargets?.proteinG),
            ("carbsG", block.dailyTargets?.carbsG),
            ("fatG", block.dailyTargets?.fatG),
            ("stepsGoal", block.dailyTargets?.stepsGoal),
            ("waterMl", block.dailyTargets?.waterMl),
            ("sleepHours", block.dailyTargets?.sleepHours),
        ] + (block.levers ?? []).map { ("lever \"\($0.key)\"", $0.value) }
        // A ceiling as well as a floor. The block is model-authored and
        // untrusted, and the ONLY thing between it and `Int.init(Double)` — a
        // non-failable initialiser that TRAPS outside `Int`'s range — is this
        // line. A million is past any real daily target in any of these units
        // and short of anything that can trap.
        for (name, value) in numbers {
            guard let value else { continue }
            guard value.isFinite, value >= 0 else { return .malformed("\(name) is not a usable number") }
            guard value <= 1_000_000 else { return .malformed("\(name) is implausibly large") }
        }
        for lever in block.levers ?? [] where lever.key.trimmingCharacters(in: .whitespaces).isEmpty {
            return .malformed("a lever has no \"key\"")
        }
        return .parsed(block)
    }

    /// A decoding error a reader can act on — the KEY, not the type graph.
    static func reason(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, _):
            return "\"\(key.stringValue)\" is missing"
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            let at = path(context)
            return at.isEmpty ? "a value is the wrong type" : "\"\(at)\" is the wrong type"
        case .dataCorrupted(let context):
            let at = path(context)
            return at.isEmpty ? "the block is not valid JSON" : "\"\(at)\" could not be read"
        @unknown default:
            return "the block could not be read"
        }
    }
}
