import AppIntents
import Foundation
import OnyxCore
import OnyxData
import Supabase
import os

// ─────────────────────────────────────────────────────────────────────────────
// "Hey Siri, export my Onyx week" (W7, decision 22).
//
// The second of the three surfaces that ask `ExportService` for an envelope.
// It exists so getting a week to a model is ONE action from anywhere — a
// Shortcut on the Home Screen, a Back Tap, an automation that fires every
// Sunday evening — rather than four taps inside the app.
//
// ── WHY IT LIVES IN THE APP TARGET AND NOT IN `Shared/` ─────────────────────
// `Shared/` is compiled into the app AND the widget extension, and the two
// intents that live there are there because a widget DRAWS their buttons. This
// one is never drawn by an extension; it opens the store, reads a whole span
// and talks to Supabase, none of which belongs in a timeline provider's
// address space.
//
// ── AND WHY IT OPENS ITS OWN STORE ──────────────────────────────────────────
// The same door the widget provider uses — `AppDatabase.readOnly` over the
// shared folder, and `knownUserId()` for whose rows they are. An intent
// performed from Shortcuts may run in a freshly launched process with no
// `AppEnvironment` yet, and reaching for one that may not exist is how an
// intent becomes flaky. Read-only is honest: building a document only reads.
// ─────────────────────────────────────────────────────────────────────────────

/// `ExportRange`, as Shortcuts can show it.
///
/// A second declaration of the same four cases, and it has to be: `ExportRange`
/// lives in OnyxCore, which is Foundation-only and must stay so, and the App
/// Intents metadata extractor requires `caseDisplayRepresentations` to be a
/// LITERAL dictionary it can read out of the source. It cannot be derived from
/// `ExportRange.label` at compile time. `ExportRangeChoiceTests` pins the two
/// case sets to each other, which is the only thing that keeps them honest.
enum ExportRangeChoice: String, AppEnum, CaseIterable {
    case sinceLastExport
    case thisWeek
    case lastWeek
    case last7Days

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Export range")

    static let caseDisplayRepresentations: [ExportRangeChoice: DisplayRepresentation] = [
        .sinceLastExport: DisplayRepresentation(
            title: "Since last export",
            subtitle: "Everything since the last document this phone handed over"),
        .thisWeek: DisplayRepresentation(
            title: "This week so far",
            subtitle: "From the start of this week up to today"),
        .lastWeek: DisplayRepresentation(
            title: "Last complete week",
            subtitle: "The last week that finished"),
        .last7Days: DisplayRepresentation(
            title: "Last 7 days",
            subtitle: "Today and the six days before it"),
    ]

    var range: ExportRange { ExportRange(rawValue: rawValue) ?? .sinceLastExport }
}

/// Builds the export and hands back two files: the document and the envelope.
///
/// TWO outputs and not one. The markdown is what goes into a chat window; the
/// JSON is what goes into a program, and a Shortcut that pipes one into
/// `Get Contents of URL` should not have to parse a document written for a
/// model to read. Shortcuts lets the user pick which file they want.
struct ExportForAIIntent: AppIntent {

    static let title: LocalizedStringResource = "Export my week"
    static let description = IntentDescription(
        """
        Builds this week's Onyx export — the Markdown document and its JSON \
        envelope — ready to hand to an AI. Nothing is sent anywhere by this \
        action; it returns the files.
        """,
        categoryName: "Training",
        searchKeywords: ["export", "week", "report", "AI", "coach"]
    )

    /// Deliberately false. The point of a Shortcuts action is that the phone
    /// does not have to come to the foreground for it.
    static let openAppWhenRun = false
    static let isDiscoverable = true

    @Parameter(title: "Range", default: .sinceLastExport)
    var range: ExportRangeChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Export my Onyx week, \(\.$range)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let (database, userId) = try Self.store()
        let service = ExportService(database: database, userId: userId)
        let envelope = try await service.build(
            range: range.range,
            uploadingVia: Self.remote(userId: userId),
            onUploadFailure: { error in
                Logger(subsystem: "app.onyx.health", category: "export")
                    .error("intent upload failed: \(String(describing: error), privacy: .public)")
            })

        let json = try JSONEncoder().encode(envelope)
        return .result(value: [
            IntentFile(
                data: Data(envelope.markdown.utf8),
                filename: "\(envelope.fileStem).md",
                type: .plainText),
            IntentFile(
                data: json,
                filename: "\(envelope.fileStem).json",
                type: .json),
        ])
    }

    // MARK: - The two things this process has to find for itself

    static func store() throws -> (AppDatabase, String) {
        let database = try AppDatabase.readOnly(folderURL: AppDatabase.sharedFolder())
        guard let userId = try database.knownUserId() else { throw ExportIntentError.notSignedIn }
        return (database, userId)
    }

    /// The copy that reaches the `exports` table, when this process happens to
    /// have a session to send it with.
    ///
    /// Nil is an ordinary answer, not a failure: the Keychain is the app
    /// target's own and an intent performed in a background launch may have no
    /// restored session yet. The files are returned either way — the server
    /// copy is a convenience for the MCP server, and `ExportService.build`
    /// treats a nil remote as "do not send".
    static func remote(userId: String) -> (any MirrorPushRemote)? {
        guard let config = try? SupabaseConfig.fromBundle() else { return nil }
        return PostgRESTMirrorRemote(client: OnyxSupabase.makeClient(config: config), userId: userId)
    }
}

enum ExportIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notSignedIn

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            return "Open Onyx and sign in first — there is nothing on this phone to export yet."
        }
    }
}

// MARK: - The phrases

/// The app's one `AppShortcutsProvider`.
///
/// There can be exactly one per app, and this is it — so anything a later wave
/// wants to offer Siri is added to the array below rather than to a second
/// provider, which the system silently ignores.
///
/// Every phrase carries `\(.applicationName)`, which is required: the system
/// matches on the app's name and refuses to register a phrase without it.
struct OnyxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ExportForAIIntent(),
            phrases: [
                "Export my \(.applicationName) week",
                "Export this week from \(.applicationName)",
                "Get my week's export from \(.applicationName)",
                "\(.applicationName), export my week",
            ],
            shortTitle: "Export Week",
            systemImageName: "square.and.arrow.up"
        )
    }
}
