import Foundation
import Testing
@testable import OnyxCore

/// The paste-back parser (W7, decision 23).
///
/// The vector is the spec. The cases below it are the two claims a vector
/// cannot make: that the schema the document ADVERTISES is the schema this
/// parser accepts, and that the worked example in §9 can never be applied as an
/// instruction.
@Suite("Targets block — the other half of the loop")
struct TargetsBlockTests {

    private struct ParseIn: Decodable { let text: String }

    private struct ParseOut: Decodable {
        let outcome: String
        let reason: String?
        let weekStart: String?
        let leverKeys: [String]?
        let kcal: Double?
        let proteinG: Double?
        let carbsG: Double?
        let fatG: Double?
        let stepsGoal: Double?
        let waterMl: Double?
        let sleepHours: Double?
        let note: String?
        let isEmpty: Bool?
    }

    @Test("the golden vector replays")
    func golden() throws {
        for c in try GoldenFixture<ParseIn, ParseOut>.load("targets-block").cases {
            let result = TargetsBlockParser.parse(c.input.text)
            switch c.expected.outcome {
            case "none":
                #expect(result == .none, "\(c.name): expected no block, got \(result)")
            case "malformed":
                guard case .malformed(let reason) = result else {
                    Issue.record("\(c.name): expected malformed, got \(result)")
                    continue
                }
                #expect(reason == c.expected.reason, "\(c.name): reason")
            case "parsed":
                guard case .parsed(let block) = result else {
                    Issue.record("\(c.name): expected a block, got \(result)")
                    continue
                }
                #expect(block.weekStart == c.expected.weekStart, "\(c.name): weekStart")
                #expect(block.levers?.map(\.key) ?? [] == c.expected.leverKeys ?? [], "\(c.name): levers")
                #expect(block.dailyTargets?.kcal == c.expected.kcal, "\(c.name): kcal")
                #expect(block.dailyTargets?.proteinG == c.expected.proteinG, "\(c.name): proteinG")
                #expect(block.dailyTargets?.carbsG == c.expected.carbsG, "\(c.name): carbsG")
                #expect(block.dailyTargets?.fatG == c.expected.fatG, "\(c.name): fatG")
                #expect(block.dailyTargets?.stepsGoal == c.expected.stepsGoal, "\(c.name): stepsGoal")
                #expect(block.dailyTargets?.waterMl == c.expected.waterMl, "\(c.name): waterMl")
                #expect(block.dailyTargets?.sleepHours == c.expected.sleepHours, "\(c.name): sleepHours")
                #expect(block.note == c.expected.note, "\(c.name): note")
                if let isEmpty = c.expected.isEmpty {
                    #expect(block.isEmpty == isEmpty, "\(c.name): isEmpty")
                }
            default:
                Issue.record("\(c.name): unknown outcome \(c.expected.outcome)")
            }
        }
    }

    // MARK: - The schema and the parser are one change

    /// §9 prints an `onyx-targets` block. The parser has to FIND it — that is
    /// what makes the two halves one change: rename the info string in either
    /// and this fails.
    @Test("the document's §9 advertises a block this parser locates")
    func schemaIsLocatable() {
        let document = WeeklyExport.pasteBackSchema.joined(separator: "\n")
        #expect(!TargetsBlockParser.fencedBodies(document).isEmpty,
                "§9's example is not a block this parser can see")
    }

    /// And it must never be an APPLICABLE one, nor a BROKEN one. A user who
    /// pastes the export into the report editor rather than the report hands
    /// the parser §9's own worked example; `YYYY-MM-DD` is the schema
    /// announcing itself, so the answer is "no targets here" and not a red
    /// banner saying the model's reply was unreadable.
    @Test("§9's worked example is read as no block at all")
    func schemaExampleCannotApply() {
        let document = WeeklyExport.pasteBackSchema.joined(separator: "\n")
        #expect(TargetsBlockParser.parse(document) == .none)
    }

    /// The whole document, not just §9. Every golden export, pasted back.
    @Test("a whole export pasted back proposes nothing and complains about nothing")
    func wholeExportPastedBack() throws {
        struct Expected: Decodable { let markdown: String? }
        let fixture = try GoldenFixture<WeeklyExportInput, Expected>.load("weekly-export")
        var checked = 0
        for c in fixture.cases {
            guard let markdown = c.expected.markdown else { continue }
            #expect(TargetsBlockParser.parse(markdown) == .none, "\(c.name): the export was not silent")
            checked += 1
        }
        #expect(checked > 0)
    }

    /// A date that does not exist is still a mistake, and still says so — the
    /// placeholder exemption must not have widened into "any unreadable date".
    @Test("a real bad date is still malformed")
    func aRealBadDateStillComplains() {
        let text = "```onyx-targets\n{ \"weekStart\": \"2026-02-30\" }\n```"
        #expect(TargetsBlockParser.parse(text)
                == .malformed("\"weekStart\" is not an ISO date (YYYY-MM-DD)"))
    }

    /// Every key the schema names is a key the type decodes. Spelled as
    /// literals because the point is to catch a RENAME, and a test that derives
    /// the names from the type would rename itself alongside it.
    @Test("every key §9 names decodes")
    func everyAdvertisedKeyDecodes() throws {
        let json = """
        {
          "weekStart": "2026-09-21",
          "levers": [{ "key": "lever-2", "value": 1900, "unit": "kcal" }],
          "dailyTargets": { "kcal": 2100, "proteinG": 170, "carbsG": 200, "fatG": 60,
                            "stepsGoal": 10000, "waterMl": 3000, "sleepHours": 8 },
          "note": "one short sentence"
        }
        """
        let block = try JSONDecoder().decode(TargetsBlock.self, from: Data(json.utf8))
        #expect(block.levers?.first?.value == 1900)
        #expect(block.levers?.first?.unit == "kcal")
        #expect(block.dailyTargets?.hasMacros == true)
        #expect(block.note == "one short sentence")
        // And the schema text names these and nothing else the parser reads.
        let schema = WeeklyExport.pasteBackSchema.joined(separator: "\n")
        for key in ["weekStart", "levers", "dailyTargets", "note", "kcal", "proteinG",
                    "carbsG", "fatG", "stepsGoal", "waterMl", "sleepHours", "key", "value", "unit"] {
            #expect(schema.contains("\"\(key)\""), "§9 does not name \(key)")
        }
    }

    /// A block inside a longer fence, and a longer fence closing a shorter one.
    /// Both are CommonMark, and both appear in real pastes where a model wraps
    /// the whole answer.
    @Test("fence lengths behave")
    func fenceLengths() {
        let longer = "````onyx-targets\n{ \"weekStart\": \"2026-09-21\" }\n````"
        #expect(TargetsBlockParser.parse(longer) == .parsed(TargetsBlock(weekStart: "2026-09-21")))
        // A shorter run inside a longer fence does not close it.
        let nested = "````onyx-targets\n```\n{ \"weekStart\": \"2026-09-21\" }\n```\n````"
        #expect(TargetsBlockParser.fencedBodies(nested).count == 1)
    }

    @Test("CRLF does not lose the block")
    func crlf() {
        let text = "Report\r\n\r\n```onyx-targets\r\n{ \"weekStart\": \"2026-09-21\" }\r\n```\r\n"
        #expect(TargetsBlockParser.parse(text) == .parsed(TargetsBlock(weekStart: "2026-09-21")))
    }
}
