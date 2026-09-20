import Foundation

// MARK: - The running session, as a complication can read it (W4)
//
// ── WHAT THIS IS, AND WHY IT IS NOT `WatchTiles` ────────────────────────────
// `WatchTiles` is the DAY: a dozen readings the phone cut out of its snapshot
// and pushed across, changing a handful of times an hour. This is the SET in
// front of you, written by the watch app itself several times a minute, and
// the two have nothing in common but the suite they are parked in. Folding the
// live fields into `WatchTiles` would mean every commit rewriting the day's
// numbers from a device that does not have them — the watch has no snapshot
// builder, and never will (`WatchTiles`' header says why).
//
// ── WHY IT IS THE WATCH THAT WRITES IT ──────────────────────────────────────
// The phone cannot. A session logged on the wrist with the phone in a locker
// is the case this whole client exists for, and the heart rate has exactly one
// source on this pair. So the watch app writes it on every commit and every
// rest pulse, and the widget extension — a second process on the same wrist,
// with no store and no WatchConnectivity — reads it back out of the App Group
// suite and draws it.
//
// ── MISSING IS NIL, NEVER ZERO ──────────────────────────────────────────────
// The same rule as every payload here. `bpm` is nil until the sensor settles,
// which is a reading that has not arrived and not a heart that has stopped.

/// The live session, small enough to write on every set.
///
/// `Codable` with SHORT keys, like `WatchTiles` and for the same reason: it is
/// decoded on every timeline of every complication that reads it.
public struct LiveWorkoutSnapshot: Codable, Sendable, Equatable {

    /// The movement in front of you. "Seated Cable Row (Wide Grip)".
    public let exercise: String
    /// Working sets ticked against the whole deck, and what it prescribes.
    ///
    /// Two integers rather than a composed string, for the reason
    /// `OnyxWorkoutAttributes.ContentState` gives about the same pair: a face
    /// draws a PROGRESS, and a progress needs the two numbers apart.
    public let setsDone: Int
    public let setsPlanned: Int
    /// The wrist's current reading. Nil until the sensor settles.
    public let bpm: Int?
    /// When the current rest ends, so a face can count it down itself with a
    /// `Text(_:style:)` timer. Nil means not resting — not a timer at zero.
    public let restEndsAt: Date?
    /// The split's key ("legs_a"), resolved to a colour on the far side —
    /// never a colour on the wire. `ContentState.dayKey` documents the drift
    /// that rule exists to prevent.
    public let dayKey: String?
    /// The movement's primary muscle as a `LandmarkMuscle.token`, or the
    /// literal `cardio`. Same wire rule as `dayKey`.
    public let primaryMuscle: String?
    /// The instant this was written. The staleness guard for the SESSION, and
    /// the only field a reader must consult before believing any of the others.
    public let updatedAt: Date
    /// When `bpm` was taken, which is NOT when this was written.
    ///
    /// ── A SESSION AGES IN MINUTES, A HEART RATE IN SECONDS ──────────────────
    /// `updatedAt` moves on every publish, and a publish happens on the rest
    /// beats — so a paused session republishes with a rate that may be twenty
    /// minutes old and an `updatedAt` of now. The corner of a watch face whose
    /// entire content is that number would draw it as a live reading.
    ///
    /// The phone has always aged its own copy at two minutes
    /// (`PhoneWatchBridge.liveBpm`). This is the same clock on the same
    /// sensor, so it is the same constant — see `bpmStaleAfter`, which both
    /// devices now read rather than each spelling 120 themselves.
    ///
    /// Nil on a snapshot written before this field existed, and on one whose
    /// sensor has never reported.
    public let bpmAt: Date?

    public init(
        exercise: String,
        setsDone: Int,
        setsPlanned: Int,
        bpm: Int? = nil,
        restEndsAt: Date? = nil,
        dayKey: String? = nil,
        primaryMuscle: String? = nil,
        updatedAt: Date = Date(),
        bpmAt: Date? = nil
    ) {
        self.exercise = exercise
        self.setsDone = setsDone
        self.setsPlanned = setsPlanned
        self.bpm = bpm
        self.restEndsAt = restEndsAt
        self.dayKey = dayKey
        self.primaryMuscle = primaryMuscle
        self.updatedAt = updatedAt
        self.bpmAt = bpmAt
    }

    enum CodingKeys: String, CodingKey {
        case exercise = "e", setsDone = "sd", setsPlanned = "sp"
        case bpm = "h", restEndsAt = "re", dayKey = "dk"
        case primaryMuscle = "pm", updatedAt = "u", bpmAt = "ha"
    }

    // MARK: Staleness

    /// How long a written snapshot keeps claiming a workout is running.
    ///
    /// ── WHY A WINDOW AND NOT THE EXPLICIT CLEAR ALONE ───────────────────────
    /// `clear()` on finish and on discard is the normal path and it is exact.
    /// What it cannot cover is the app going away without running: a jetsam
    /// mid-workout — which this app has a crash log for — would otherwise
    /// leave the Smart Stack surfacing a phantom session for as long as the
    /// watch stays paired.
    ///
    /// 45 minutes, not 5: the writer fires on every commit and every rest
    /// pulse, so the longest ordinary gap is one set plus one rest, but a
    /// workout interrupted by a phone call is a real workout and blanking it
    /// would be the worse error of the two.
    public static let staleAfter: TimeInterval = 45 * 60

    /// How long a wrist reading stays a reading.
    ///
    /// ── ONE SPELLING, BECAUSE BOTH DEVICES DRAW THE SAME SENSOR ─────────────
    /// Two minutes is longer than a working rest and shorter than a set plus a
    /// rest, so a number that stops arriving disappears within one set of the
    /// watch going quiet. The phone has aged its own copy at exactly this
    /// since W10 and stated the constant on `PhoneWatchBridge`; the watch had
    /// no equivalent until W4 put the rate on a face. Declared here, in the
    /// package both devices link, so the wrist and the Lock Screen cannot
    /// disagree about when a heart rate stopped being one.
    public static let bpmStaleAfter: TimeInterval = 120

    /// The rate if it is still a reading at `now`, otherwise nil.
    ///
    /// A snapshot written before `bpmAt` existed has no instant to age
    /// against and answers the rate it carries — degrading to the old
    /// behaviour rather than blanking a face that was right yesterday, which
    /// is the same choice `WatchModel` makes about nil tiles.
    public func freshBpm(at now: Date = Date()) -> Int? {
        guard let bpm else { return nil }
        guard let bpmAt else { return bpm }
        let age = now.timeIntervalSince(bpmAt)
        return age < Self.bpmStaleAfter && age > -Self.bpmStaleAfter ? bpm : nil
    }

    /// Does this say the same thing as `other`, ignoring WHEN it was said?
    ///
    /// ── WHY A PUBLISH NEEDS THIS ───────────────────────────────────────────
    /// `WatchModel` publishes from `seedCursor` (every set, every deck edit,
    /// every phone ingest) AND from the rest beats, so a single commit
    /// reaches the writer twice. Each publish costs a
    /// `reloadTimelines` and an `invalidateRelevance`, and reloads are
    /// budgeted on a watch — spending two where the card has not changed is
    /// how the live card becomes the one widget that stops updating.
    ///
    /// The timestamps are excluded because they are the two fields that move
    /// on every publish by construction; everything a face DRAWS is compared.
    public func sameReading(as other: LiveWorkoutSnapshot?) -> Bool {
        guard let other else { return false }
        return exercise == other.exercise
            && setsDone == other.setsDone
            && setsPlanned == other.setsPlanned
            && bpm == other.bpm
            && restEndsAt == other.restEndsAt
            && dayKey == other.dayKey
            && primaryMuscle == other.primaryMuscle
    }

    /// Is this still a session, at `now`?
    public func isLive(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(updatedAt) < Self.staleAfter
            // A clock that has run BACKWARDS past the window — a timezone
            // change, a manual date — is not evidence of a workout either.
            && now.timeIntervalSince(updatedAt) > -Self.staleAfter
    }

    // MARK: Where the watch keeps it

    /// The watch's own App Group, the one `WatchTiles` names. One suite, two
    /// keys: the day and the set, written by the same app and read by the same
    /// extension.
    public static var suiteName: String { WatchTiles.suiteName }
    public static let key = "onyx.watch.live"

    /// What the extension reads. Nil before a session has ever run on this
    /// wrist, after one is finished, and on a build with no App Group
    /// entitlement (Gate 0).
    ///
    /// A snapshot past `staleAfter` answers nil here rather than being handed
    /// back for the caller to check: every caller would have to make the same
    /// check, and the one that forgot would draw a phantom.
    public static func load(
        from defaults: UserDefaults = WatchTiles.defaults(), at now: Date = Date()
    ) -> LiveWorkoutSnapshot? {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(LiveWorkoutSnapshot.self, from: data),
              snapshot.isLive(at: now)
        else { return nil }
        return snapshot
    }

    /// What the watch app writes on every commit and every rest pulse.
    public func save(to defaults: UserDefaults = WatchTiles.defaults()) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// The session is over. Called on finish and on discard.
    public static func clear(from defaults: UserDefaults = WatchTiles.defaults()) {
        defaults.removeObject(forKey: key)
    }

    /// The widget's `kind:` string.
    ///
    /// ── WHY IT IS HERE AND NOT ON THE WIDGET ────────────────────────────────
    /// Two processes need it and they are in two targets: the extension
    /// DECLARES the kind, and the watch app has to name it to
    /// `reloadTimelines(ofKind:)` and `invalidateRelevance(ofKind:)`. The
    /// extension's types are not visible to its host, so the only place both
    /// can see is a package both link. Exactly the argument `suiteName` makes
    /// two properties up, and the failure it prevents is the same: a second
    /// literal, silently wrong after a rename, with nothing at all to show
    /// for it — a widget that draws the right thing and never refreshes.
    ///
    /// ⚠️ Load-bearing, like every `kind:` in this app: changing it takes
    /// every placed copy of the widget with it.
    ///
    /// Not a `static let` on the `Widget` type, either: `Widget` is
    /// `@MainActor`, so a static declared inside one is main-actor isolated
    /// and every nonisolated reference to it warns under strict concurrency —
    /// the trap `w1a-week-wrapped` recorded about a `View`'s statics.
    public static let widgetKind = "OnyxWatch.liveWorkout"
}
