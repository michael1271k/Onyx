// ── BOTH DEVICES ────────────────────────────────────────────────────────────
// NOT fenced `#if os(iOS)`, alone among the faces: this file is the phone's
// Lock Screen AND the watch's complications, and it is the same drawing on
// purpose. It imports WidgetKit, SwiftUI and OnyxCore only — no glass, no
// mesh, no `OnyxSize(WidgetFamily)` (the system families do not exist on
// watchOS), and two ink levels, for the reasons `WatchInk` gives at length: at
// 40 mm through gym light a third ink level is an absence.
//
// ── WHY THE INPUT IS `WatchTiles` AND NOT `OnyxSnapshot` ────────────────────
// The watch has no snapshot — its store holds sets and nothing else, and the
// phone sends it `WatchTiles` inside the application context. The phone HAS a
// snapshot, and `WatchTiles.init(_:)` cuts it down in one place. So the face
// takes the smaller type on both devices, and "one face, both devices" is a
// fact of the type signature rather than a promise in a comment.
//
// ── WHY THESE FACES ARE NOT SMALL WIDGETS SHRUNK ─────────────────────────────
// An accessory has no background and renders in `.accented` or `.vibrant` on
// most faces: the system flattens everything to one tint, so colour carries NO
// information here and any face that leans on it loses its meaning. What
// survives is shape (the gauge), one glyph and one number — which is why each
// id is a single fact and none of them is a ledger.

import SwiftUI
import WidgetKit
import OnyxCore

// MARK: - Which tiles have a wearable face

public extension WidgetId {
    /// The ids `WatchTiles` can answer, in gallery order: the ten whose whole
    /// reading is one figure the payload carries. Each is one `StaticConfiguration`
    /// in the watch bundle — ten is `WidgetBundleBuilder`'s ceiling, so a wave
    /// that adds an eleventh nests a second bundle, as `OnyxControls` does.
    static let wearable: [WidgetId] = [
        .recovery, .train, .fuel, .water, .steps, .sleep, .bedtime, .stress, .soreness, .weekRings,
    ]
    var isWearable: Bool { Self.wearable.contains(self) }
}

/// The tile namespace. Declared here, unfenced, because the watch needs the
/// name; the Home Screen half (`face`, `clamped`, `native`) is an extension in
/// `Dashboard/OnyxTile.swift` behind the iOS fence.
public enum OnyxTile {}

public extension OnyxTile {
    /// The accessory face for one id, at one accessory family. The watch
    /// bundle's one call; the phone's `LockView` delegates here.
    ///
    /// `family` is a parameter rather than read from the environment because
    /// the app's contact sheet cannot set `widgetFamily` (it is get-only
    /// outside WidgetKit), and a face that has to be photographed has to be
    /// told what it is.
    @MainActor
    static func accessory(_ id: WidgetId, family: WidgetFamily, tiles: WatchTiles?) -> some View {
        AccessoryFace(id: id, family: family, tiles: tiles)
    }
}

// MARK: - Type
//
// Text styles, never point sizes — the same rule `WatchType` states: a point
// size ignores the watch's own Text Size setting, and the phone's
// `OnyxWidgetType` table is iOS metrics behind an iOS fence.

enum AccessoryType {
    /// The one number inside a ring or a corner.
    static let hero = Font.system(.title3, design: .rounded, weight: .semibold)
    /// The word under a glyph in a ring.
    static let ring = Font.system(.caption2, design: .rounded, weight: .semibold)
    /// The rectangular headline.
    static let title = Font.system(.footnote, design: .rounded, weight: .semibold)
    /// The rectangular second line, the inline text.
    static let sub = Font.system(.caption2, design: .rounded)
}

// MARK: - The face

public struct AccessoryFace: View {
    let id: WidgetId
    let family: WidgetFamily
    let tiles: WatchTiles?
    @Environment(\.widgetRenderingMode) private var mode

    public init(id: WidgetId, family: WidgetFamily, tiles: WatchTiles?) {
        self.id = id
        self.family = family
        self.tiles = tiles
    }

    private var reading: AccessoryReading { AccessoryReading(id: id, tiles: tiles) }
    /// Colour only where the system lets it mean something.
    private var tint: Color? { mode == .fullColor ? reading.accent : nil }

    public var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            #if os(watchOS)
            case .accessoryCorner: corner
            #endif
            default: circular
            }
        }
        // `.clear`, not the widget background: an accessory sits on the
        // wallpaper or the watch face, and painting obsidian behind it draws a
        // black rectangle there.
        .containerBackground(.clear, for: .widget)
    }

    // MARK: Circular

    /// A gauge for anything with a goal; a glyph and a number for anything
    /// without. A ring at an arbitrary fraction would be decoration claiming
    /// to be a measurement.
    @ViewBuilder private var circular: some View {
        let r = reading
        if let progress = r.progress {
            Gauge(value: progress, in: 0...1) {
                Image(systemName: r.glyph)
            } currentValueLabel: {
                Text(r.hero).minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tint)
        } else {
            VStack(spacing: 1) {
                Image(systemName: r.glyph).font(.system(.callout, weight: .semibold))
                Text(r.hero).font(AccessoryType.ring).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }

    // MARK: Rectangular

    /// Two lines and a glyph — the one accessory family with room for a
    /// sentence. Week Rings swaps the glyph for the marks themselves.
    private var rectangular: some View {
        let r = reading
        return HStack(spacing: 6) {
            if id == .weekRings, let week = tiles?.week {
                WeekMarks(week: week, tint: tint)
            } else {
                Image(systemName: r.glyph).font(.system(.callout, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title).font(AccessoryType.title).lineLimit(1)
                Text(r.sub).font(AccessoryType.sub).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Inline

    /// One line beside the clock. Whatever the id is, said in four words.
    private var inline: some View {
        Label(reading.inline, systemImage: reading.glyph)
    }

    // MARK: Corner (watchOS)

    #if os(watchOS)
    /// The number in the corner; the label curves along the bezel — a gauge
    /// where there is a goal, the words where there is not.
    @ViewBuilder private var corner: some View {
        let r = reading
        if let progress = r.progress {
            Text(r.hero)
                .font(AccessoryType.hero)
                .minimumScaleFactor(0.6)
                .widgetLabel {
                    Gauge(value: progress, in: 0...1) { Text(r.title) }
                        .tint(tint)
                }
        } else {
            Image(systemName: r.glyph)
                .font(.system(.title3, weight: .semibold))
                .widgetLabel(r.inline)
        }
    }
    #endif
}

// MARK: - The week's marks
//
// Three rows of seven, oldest left — Train, Fuel, Sleep top to bottom, the
// order the phone's Week Rings tile keeps at Small where the colour is the
// only key. Here there is no colour either; the ROW is the key, and the
// second line names the counts.

struct WeekMarks: View {
    let week: [WatchTiles.WeekDay]
    let tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row(week.map(\.trained))
            row(week.map(\.fuelHit))
            row(week.map(\.sleepHit))
        }
        .accessibilityHidden(true)
    }

    private func row(_ hits: [Bool]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                Circle()
                    .fill(hit ? AnyShapeStyle(tint ?? .primary) : AnyShapeStyle(.secondary.opacity(0.35)))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

// MARK: - One id, one reading
//
// Every string the four families draw, decided once per id so the circular,
// rectangular, inline and corner faces cannot disagree about a number. Nil
// readings print "—", never a zero (`WatchTiles`' header).

struct AccessoryReading {
    let glyph: String
    /// The number in a ring or a corner — short, because a 40 pt ring holds
    /// four characters.
    let hero: String
    /// Gauge fill, or nil for a reading with no goal.
    let progress: Double?
    let title: String
    let sub: String
    let inline: String
    let accent: Color

    init(id: WidgetId, tiles t: WatchTiles?) {
        let dash = "—"
        switch id {
        case .recovery:
            let b = t?.battery
            glyph = "bolt.fill"
            hero = b.map { "\($0)" } ?? dash
            // The gauge sits at zero because it has to sit somewhere; the
            // NUMBER never lies about it.
            progress = b.map { Double($0) / 100 }
            title = "Battery \(b.map { "\($0)%" } ?? dash)"
            sub = t?.score.map { "Score \($0)" } ?? "No score yet"
            inline = "Battery \(b.map { "\($0)%" } ?? dash)"
            accent = Color.onyx.battery(b)

        case .train:
            let label = t?.todayLabel ?? ""
            let rest = t?.restDay == true
            let logged = t?.todayLogged == true
            glyph = rest ? "moon.zzz.fill" : logged ? "checkmark.circle.fill" : "dumbbell.fill"
            // The day label trimmed to something that fits a ring — "Legs &
            // Core B" becomes "Legs": a truncated word reads as a bug and a
            // first word reads as a category.
            hero = t == nil || label.isEmpty ? dash : rest ? "Rest" : String(label.split(separator: " ").first ?? "—")
            progress = nil
            title = t == nil || label.isEmpty ? dash : label
            sub = t == nil ? "Open Onyx on iPhone" : rest ? "rest day" : logged ? "done" : "due"
            inline = title
            accent = OnyxDomain.train.accent

        case .fuel:
            let left = t?.kcalRemaining
            glyph = "flame.fill"
            hero = left.map { "\($0)" } ?? dash
            progress = WatchTiles.progress(t?.kcal, t?.kcalGoal)
            title = left.map { "\($0) kcal left" } ?? "No intake yet"
            sub = t?.kcal.map { "\($0) of \(t?.kcalGoal.map { "\($0)" } ?? dash)" } ?? dash
            inline = title
            accent = OnyxDomain.fuel.accent

        case .water:
            let ml = t?.waterMl
            glyph = "drop.fill"
            // Litres to one place: "1.8" fits a ring where "1750" does not.
            hero = ml.map { String(format: "%.1f", Double($0) / 1000) } ?? dash
            progress = WatchTiles.progress(ml, t?.waterGoalMl)
            title = ml.map { "\($0) ml" } ?? "No water yet"
            sub = t?.waterGoalMl.map { "of \($0) ml" } ?? dash
            inline = ml.map { "\($0) ml water" } ?? "Water —"
            accent = OnyxDomain.fuel.accent

        case .steps:
            let n = t?.steps
            glyph = "figure.walk"
            // Thousands to one place, because five digits inside a ring is a
            // smudge.
            hero = n.map { $0 >= 1000 ? String(format: "%.1fk", Double($0) / 1000) : "\($0)" } ?? dash
            progress = WatchTiles.progress(n, t?.stepsGoal)
            title = n.map { "\($0) steps" } ?? "No steps yet"
            sub = t?.stepsGoal.map { "of \($0)" } ?? dash
            inline = title
            accent = OnyxDomain.body.accent

        case .sleep:
            let min = t?.sleepMin
            glyph = "moon.fill"
            hero = min.map { "\($0 / 60)h\($0 % 60 < 10 ? "0" : "")\($0 % 60)" } ?? dash
            // The ring is the SCORE, the number is the hours — the two things
            // a night is, and the ring never invents a score from hours.
            progress = t?.sleepScore.map { Double($0) / 100 }
            title = "Sleep \(OnyxSnapshot.formatSleep(min))"
            sub = t?.sleepScore.map { "score \($0)" } ?? "no score"
            inline = title
            accent = OnyxDomain.recover.accent

        case .bedtime:
            let last = t?.lastBedtime
            glyph = "bed.double.fill"
            hero = last ?? dash
            progress = nil
            title = "Bed \(last ?? dash)"
            sub = t?.medianBedtime.map { "usually \($0)" } ?? "no usual bedtime yet"
            inline = title
            accent = OnyxDomain.recover.accent

        case .stress:
            let x = t?.stressIndex
            glyph = "brain.head.profile"
            hero = x.map { "\(Int($0.rounded()))" } ?? dash
            progress = x.map { min(1, max(0, $0 / 100)) }
            title = "Stress \(x.map { "\(Int($0.rounded()))" } ?? dash)"
            sub = x.map { Stress.bandLabel(Stress.band($0)) ?? Stress.band($0).rawValue } ?? "nothing answered"
            inline = x.map { "Stress \(Int($0.rounded())) · \(Stress.bandLabel(Stress.band($0)) ?? "")" } ?? "Stress —"
            accent = OnyxDomain.recover.accent

        case .soreness:
            let n = t?.sorenessCount
            glyph = "bandage.fill"
            hero = n.map { "\($0)" } ?? dash
            progress = nil
            title = "Soreness"
            // Nil is "not asked", zero is "asked, nothing hurts" — the
            // distinction W4 paid for.
            sub = n.map { $0 == 0 ? "nothing sore" : "\($0) sore" } ?? "not logged today"
            inline = n.map { $0 == 0 ? "Nothing sore" : "\($0) sore" } ?? "Soreness —"
            accent = OnyxDomain.recover.accent

        case .weekRings:
            let week = t?.week
            let trained = week?.filter(\.trained).count
            let fuelled = week?.filter(\.fuelHit).count
            let slept = week?.filter(\.sleepHit).count
            glyph = "circle.grid.3x3"
            hero = trained.map { "\($0)/7" } ?? dash
            progress = trained.map { Double($0) / 7 }
            // Two short lines, not one long one: three counts with their
            // words is ~26 characters and the rectangular face beside the
            // marks holds about 14 before it truncates — "Week · 5 trained"
            // lost its last word on the phone's sheet, so the top row IS
            // the training count and the word "Week" goes.
            title = trained.map { "\($0)/7 trained" } ?? "Week"
            sub = week == nil ? dash : "\(fuelled ?? 0) fuelled · \(slept ?? 0) slept"
            inline = trained.map { "Week \($0)/7 trained" } ?? "Week —"
            accent = OnyxDomain.train.accent

        default:
            // Not wearable — nothing in the payload answers it. Draws the
            // title and a dash rather than trapping, so a mis-typed id in a
            // bundle is visible on the face and not a crash on the wrist.
            glyph = id.symbol
            hero = dash
            progress = nil
            title = id.title
            sub = "No watch face yet"
            inline = "\(id.title) —"
            accent = id.domain.accent
        }
    }
}
