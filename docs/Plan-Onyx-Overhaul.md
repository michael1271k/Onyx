# Onyx — UI/UX Overhaul + Watch Sync Blueprint

## Context
Onyx 8.0.0 just closed the App Store sprint. The founder reports: the watch offers "Start" after the phone finished the workout; the app opens on Train with a "Leave" button; the session summary scrolls forever with childish ±deltas; treadmill logs as "Walk"; widgets lost the sleep half-ring; scrolling opens tiles; stacks flip in unison; settings are too big; the 9-theme appearance system is dated. Goal: one coordinated overhaul — real phone↔watch lifecycle sync, a watch dashboard, an 8-colour "Stone" appearance system with fixed semantic inks, redesigned tiles/widgets, a bento session summary, a compact Settings, DSLD supplement import, a Session Replay share card, and a new icon — executed by 3 parallel Opus 5.5 lanes in git worktrees, merged B → C → A, then two sequential waves. Fable authors prompts and reviews; Opus builds and self-verifies with the shot scripts.

Status: **PLAN — founder answered Q1–Q20 and approved all concepts/features (decisions table below). Wave plan + Opus prompts at the end of this file.**
Role: Fable 5.1 = CPO/architect + prompt author. Opus 5.5 agents = builders.
Path classification: **architectural** (7 subsystems). Skills loaded: brainstorming, ui-ux-pro-max, apple-design, frontend-design, impeccable (context ran: no PRODUCT.md, incumbent visual system is authority), senior-architect. `ux-researcher-desginer` is not installed; `ui-ux-designer` agent covers it.

Sections 1–3, 5 are filled from the three codebase explorations (below). Section 4, 6, 7 and the questions/concepts/features are independent of the code and written first.

---

## 4. iHerb integration — verdict: DROP the account link, keep a cheaper substitute

**Facts (2026-09-23):**
- iHerb has **no public product API**. Its affiliate program is run through third-party affiliate platforms and offers commission links, not a data feed ([iHerb affiliates](https://www.iherb.com/info/affiliates), [terms](https://www.iherb.com/lp/affiliate-terms-and-conditions)). No OAuth "link your iHerb account" exists for third parties at all.
- Everything that returns iHerb product data is a scraper ([ScrapingBee](https://www.scrapingbee.com/scrapers/iherb-api/), [Apify iHerb actors](https://apify.com/lumen_limitless/iherb-product-api/api), [RapidAPI](https://rapidapi.com/daniel.hpassos/api/iherb-product-data-api), [Bright Data](https://brightdata.com/products/web-scraper/iherb)). Scraping a retailer inside an App Store app: (a) ToS exposure, (b) breaks whenever iHerb changes markup, (c) needs a server-side proxy + paid actor per query, (d) App Review can reject "content from a third party without permission" (guideline 5.2.2). Not shippable.
- **Substitute that IS feasible, free, and license-clean:** NIH **Dietary Supplement Label Database (DSLD)** API — base `https://dsld.od.nih.gov/dsld/v9/`, endpoints `search-filter`, `label/{id}`, `browse-products`, `browse-brands`, `ingredient-groups`; **no API key**, **CC0 license**, returns per-ingredient rows with quantity + unit + %DV per serving ([API guide](https://dsld.od.nih.gov/api-guide), [DSLD API](https://dsldapi.od.nih.gov/)). ~200k US labels, includes most brands iHerb sells (NOW, Thorne, Jarrow, Doctor's Best, Solgar…). No UPC endpoint; UPC is inside the label record only.
- **Barcode path:** Open Food Facts v2 `product/{barcode}.json`, no key, has an "Open Beauty/Products" sibling but supplement coverage is thin ([OFF API](https://openfoodfacts.github.io/openfoodfacts-server/api/)). Use OFF only as a barcode→name hop, then DSLD for the label.

**Proposal:** "Add from label database" in Supplements: search brand/product → pick → DSLD label → prefill name, serving, per-ingredient amounts into the existing supplement editor (`dose`, `doseAmount`, `doseUnit`, micros). Optional: camera barcode → OFF name → DSLD search. No account linking. iHerb stays only as an optional outbound "buy" link if the founder wants an affiliate URL (Q11).

---

## 6. App icon — verdict: replace

Current icon predates two palette systems and the Liquid Glass era; the overhaul defines an 8-colour appearance system, so the icon should be **palette-neutral** (black onyx + one light) or it will clash with 7 of 8 themes. Recommendation: a single carved onyx form with an inner light, no gradient wash, no text.

**Copy-paste prompt (Midjourney / Ideogram / GPT-image) — founder-approved direction: hyper-minimalist, high-density 3D, in the register of Things 3 / Dark Noise, a tool not a game:**
```
iOS app icon, 1:1, for "Onyx", a premium strength-and-recovery tool. Hyper-minimalist, high-density 3D render in the style of top-tier utility apps (Things 3, Dark Noise, Craft): one object, one material, one light. The object: a single slab of polished black onyx cut as a shallow rounded square (Apple squircle, corner radius ~22% of width), viewed exactly head-on, filling ~86% of a pure #000000 canvas, fully inside the frame. Surface: deep near-black (#0B0B0E) satin with faint mineral banding visible only under the highlight, no glossy mirror reflections, no environment map. One precise diagonal seam of light, 4% of the width, runs lower-left to upper-right through the stone like an inlaid vein: pearl white core (#EDEBF5) with a cool lavender edge (#A79FD6), softly luminous, not a neon glow, no bloom halo. Lighting: a single soft key light upper-left producing one thin 1-px bright bevel on the top and left edges and a gentle falloff to the lower-right; a very tight, dark contact shadow under the slab only. Absolutely no text, letters, numbers, logos, glyphs, dumbbells, hearts, gradients outside the object, particles, sparkles, or secondary objects. Colour palette limited to black, near-black, pearl, lavender. Render quality: physically based, 4K, crisp edges, product-photography restraint.
```
Negative prompt (if supported): `text, letters, logo, watermark, neon glow, bloom, lens flare, gradient background, multiple objects, cartoon, game icon, bevel-and-emboss, chrome, rainbow, sparkles, bokeh, hands`.
Generate 4–6 candidates; pick the one whose seam reads at 60 px (Home Screen small size). If none reads at 60 px, thicken the seam to 6 % and regenerate.

**Xcode steps once you have the PNG:**
1. Export a **1024×1024 PNG, no alpha** (flatten onto black; App Store rejects alpha).
2. In Xcode 26, File ▸ New ▸ File ▸ **Icon Composer** file → drop the 1024 PNG as the single layer, set Background = solid `#000000`, export `AppIcon.icon`. This gives Liquid Glass tint/clear/dark variants for iOS 26 automatically and still produces the flat icon for iOS 18–25.
3. Put `AppIcon.icon` in `native/Onyx/Resources/` beside the asset catalog; in `native/project.yml` under target `Onyx` ▸ `settings.base` set `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` (already) — Xcode picks the `.icon` over the `.appiconset` when both exist; delete the old `AppIcon.appiconset` PNGs to avoid drift.
4. Watch app: the same 1024 PNG goes into `native/OnyxWatch/Resources/Assets.xcassets/AppIcon.appiconset` (single-size "watchOS 1024"). Watch icons are always circular-masked by the system, so keep the stone's light seam within the inner 80 %.
5. `cd native && xcodegen generate`, build once, check Settings ▸ General ▸ iPhone Storage ▸ Onyx (icon renders), and the watch Home Screen.
6. Commit the `.icon` + watch appiconset; no code changes.

If you prefer not to adopt Icon Composer: keep `AppIcon.appiconset` with one `1024x1024` entry (`"platform": "ios", "size": "1024x1024"`) — Xcode 14+ generates all sizes.

---

## 7. Orchestration — Fable plans, Opus builds, 3 parallel worktrees

**Lane map (domains chosen so no two lanes edit the same files):**

| Lane | Domain | Owns (write) | Reads only |
|---|---|---|---|
| **A — Watch** | watch sync, watch dashboard, Crown RPE, post-workout banner, complications | `native/OnyxWatch/**`, `native/OnyxWatchWidgets/**`, `Features/Shell/PhoneWatchBridge*.swift`, `OnyxCore/Watch/**` (wire types) | OnyxUI theme, LoggerModel |
| **B — Faces** | 8-colour appearance, iOS dashboard tiles, widgets (sleep half-ring, vitals, water, food, workout), stack-scroll + tap sensitivity, Pulse sleep | `OnyxUI/**`, `native/OnyxWidgets/**`, `Features/Today/**`, `Features/Pulse/**`, `Features/Settings/Appearance*` | OnyxCore payload builders (additive only) |
| **C — Logger** | Train-tab launch bug, session summary compaction, HR red, treadmill→Walk, ±15 s export, edit-mode Add Exercise + Discard, Settings compaction, DSLD supplements | `Features/Train/**`, `Features/Settings/**` (except Appearance), `Features/History/**`, `OnyxData/Export/**`, `Features/Supplements/**` | OnyxUI tokens |

**Shared-file rules (merge-time only, never in a lane):** `package.json` version, `docs/CHANGELOG.md`, `graphify-out/`, `native/Onyx.xcodeproj` (regenerated by xcodegen — never hand-merged), the three layout goldens (`layout-catalogue.json`, `layout-defaults.json`, `layout-from-stored.json`) belong to Lane B alone.

**Worktree protocol (from memory: worktree guard rejects any `.git` string in a path; Edit hook can misfire on a dead worktree → run patches from scratchpad scripts; graphify hook rebuilds in cwd → always `cd` back to repo root; link `node_modules`):**
```
git worktree add ../onyx-lane-a -b wave/overhaul-a-watch main
git worktree add ../onyx-lane-b -b wave/overhaul-b-faces main
git worktree add ../onyx-lane-c -b wave/overhaul-c-logger main
ln -s $PROJECT/node_modules ../onyx-lane-{a,b,c}/node_modules
```
Each lane uses its own `-derivedDataPath "$HOME/Library/Caches/onyx-swift/lane-<x>"` and its own simulator pair (one simulator per lane — three concurrent test runs wedge the simulator; the iOS 27 sim has no WatchConnectivity, so Lane A uses the 26.5 iPhone 15 + Watch Ultra 2 pair from `docs/SIMULATORS.md`).

**Sequencing:** Wave 0 (Fable, solo, on main): token contract — the 8-colour `OnyxTheme` seed list, the static-colour table, the `LiveWorkoutSnapshot` field additions (provisional RPE, finished summary). Wave 0 is tiny, merges first, and is what makes A/B/C independent. Then A ∥ B ∥ C. Merge order **B → C → A** (B changes tokens every screen reads; C is app-only; A last because it rebases onto the final theme and snapshot). Each merge: `git rebase main`, `npm run check`, OnyxTests compared by **test NAME** against the 9-name baseline, version bump (MINOR per lane), changelog section, `graphify update .`.

**Opus prompt template (every wave gets one; full prompts written after Q&A):**
- Header: worktree path, branch, simulator UDIDs, derived-data path, version to take.
- Skills to load: `native`, `apple-design`, `ui-ux-pro-max`, `impeccable` (`polish` pass at end), `superpowers:verification-before-completion`; agents: `swift-expert` for concurrency, `ui-ux-designer` for the visual pass, `invariant-auditor` after any OnyxCore math edit.
- Exact task list with file paths and acceptance criteria.
- Self-verification loop: build → `scripts/native-shot.sh` / `watch-shot.sh` screens named in the prompt → the agent reads its own PNGs with the Read tool → a written checklist per shot (alignment, truncation, AX5, dark/light, 3 themes) → fix → **max two rounds** (impeccable rule) → `rm -rf native/__screenshots__/*` and the lane's derived-data shot cache → continue. No founder approval needed inside a wave.
- Exit: rebase, gates, memory note, PR-style summary in the wave record.

---

## OUTPUT 2 — 8 new design concepts (not in the brief)

1. **"Stone" material system.** One physical metaphor for the whole app: every card is a slab of onyx — near-black base, 1 px inner top highlight, no drop shadows, corner radius scaled by depth (28 pt sheets, 20 pt tiles, 12 pt chips, continuous curvature). Light themes use the same slab in pale stone. Replaces the glass/wash mix that currently differs per feature.
2. **Single hero rule enforced by layout, not convention.** Each tab gets one `.hero` numeral (Score on Pulse, tonnage on Train, sleep hours on Today); everything else caps at `.display`. Already a cross-wave law — make it a compile-time token (`OnyxType.hero` only usable inside `HeroSlot`).
3. **Progressive detail via long-press peek, not tap-to-sheet.** Tiles open on a *deliberate* tap; a long-press shows a 3-line peek popover with haptic; drag continues to scroll. Kills the accidental-open problem structurally (Q9).
4. **Watch "Glance ring" home.** The watch's first page is one ring (readiness) with four petals (sleep, water, food, vitals) around it — Crown rotates the highlighted petal, tap enters. Mirrors the phone tabs with zero text on the first paint.
5. **Session summary as a bento, not a scroll.** Header row (name · time · tonnage · HR), then a 2-column bento: HR strip (full width, no legend), exercise grid of compact 2-line chips (name, best set, PR trophy), a "Focus" pill row for muscle share, a single "Progression" button that opens the detail. Target: one screen on a 6.1" phone at default type.
6. **Delta ink, not arrows.** Replace +/- badges with the number itself tinted (up = theme accent, down = `textSecondary`), a hairline underline for PR. Deltas appear only on long-press or in the Progression sheet.
7. **Theme-aware charts with fixed semantic inks.** Water = fixed blue, HR = fixed red, sleep stages = fixed 4-stop lavender→indigo ramp, everything *the user chose* (accent, muscle groups, macros) comes from the theme. Documented as a two-column table in `OnyxTheme` so no future wave re-derives it.
8. **Complication continuity.** The watch complication, Smart Stack card, Lock-Screen widget and Dynamic Island all draw the same `LiveWorkoutSnapshot` through one `OnyxTile.workout` face at three sizes — one truth, one glyph set, one "Done" that never truncates because the face measures its own width.

## OUTPUT 3 — 3 brand-new features

1. **Rest-timer Crown RPE + auto-quality.** During rest on the watch, the Crown sets the last set's RPE live (colour bands) and the phone mirrors it instantly; on the phone, tapping the mirrored value confirms. Zero extra taps for the honest-RPE user.
2. **Session Replay card.** After a workout, a 10-second animated replay (HR trace drawing itself, sets dropping in as dots, PRs flashing) on both phone and watch — shareable as a square PNG/video. Uses existing summary data; no new storage.
3. **Label-database supplement import (DSLD).** Search or scan → prefilled supplement with per-ingredient micros, feeding the existing micronutrient totals (mass doses still excluded per W5 rule).

---

## FOUNDER DECISIONS (2026-09-23) — binding for every wave

| Q | Decision |
|---|---|
| 1 | **A** Phone owns; `session {id, phase, summary}` in `WatchContext`, pushed instantly |
| 2 | **C** `EffortPulse` per Crown detent (debounced) + colour band on the phone deck card; commit on tick |
| 3 | **C** Banner = name · tonnage · avg HR · PRs + 6-point HR sparkline |
| 4 | **C** Glance ring + four petals, then tab pages |
| 5 | **C** Complications cut to 5 + "Next dose" |
| 6 | **A** `DepthArc` restored on tiles + Pulse; fixed 4-stop sleep ramp |
| 7 | **A** Sparkline per vital, 7 d |
| 8 | **A** Pitcher fill, fixed water blue |
| 9 | **A** `Button` + `OnyxPressStyle`; in-app `Link`s disabled |
| 10 | **B** Keep auto-advance, every stack own phase, `linked` no longer shares the beat |
| 11 | **C** DSLD search (by product AND by company/brand) — barcode is **optional** (user may not have the bottle yet). Must be fast/reliable: cache + timeout + offline fallback to manual |
| 12 | **B** HR segments only, tap → callout with name + avg bpm |
| 13 | **A** SF Symbols map (~20) by movement pattern |
| 14 | **B** Tinted numerals, hairline under PR, no arrows |
| 15 | **A** Bento summary |
| 16 | **A** ±15 s visual only; drop `restActualSec` from JSON/AI export |
| 17 | **A** Slate · Lagoon · Sage · Iris / Clay · Ochre · Moss · Rosewood |
| 18 | **B** Fixed anatomical 16-muscle palette; theme tints chrome/accent only |
| 19 | **B-weighted**: macros, micros AND calories derive from the theme but with **dampened weights** (partial hue rotation, e.g. 35 % of the theme's hue shift, chroma clamp), so the trio stays recognisable across all 8. **Water = always blue, heart rate = always red** (new fixed tokens) |
| 20 | **A** System Form, compact rows, subheadline text |

**Approvals:** all 8 concepts and all 3 features approved, with three founder challenges: (C1) Stone slabs must carry a subtle iOS frosted glass (`.thinMaterial`-class) so content scrolling behind them frosts, not a solid slab; (C8) Dynamic Island compact state = exact duration + HR only, drawn with the Masthead design through ActivityKit; (F2) the Replay share export gets a deep premium gradient/glass backdrop sized for Instagram Stories (1080×1920). **Gym mode: delete entirely.** **Icon: replace** (revised prompt above).

## OUTPUT 1 — 20 multiple-choice questions

(Answers drive the plan. Reply like `1B 2A 3D …`, or add "Other: …".)

**Architecture / sync**
1. **Watch source of truth for "is a workout live?"** — A) Phone owns; watch subscribes via app-context + sendMessage, watch never starts a second session when phone is finished · B) Shared Supabase row polled by both · C) Watch owns during workout, hands back at finish · D) CRDT-style merge of both logs, last-writer-wins per set
2. **Live RPE channel** — A) `sendMessage` provisional RPE every Crown detent, commit on set tick · B) Only at rest-timer end · C) Also carry a "difficulty colour" the phone shows on the deck card in real time · D) Watch-only, sync at set commit
3. **Finished-session mini banner on the watch: which numbers?** — A) name · tonnage · avg HR · PR count · B) + duration + calories · C) A + a 6-point HR sparkline · D) Only "Done · 52 min" and a tap to the phone
4. **Watch dashboard navigation** — A) Vertical page-scroll of cards (Fitness-app style) · B) TabView pages mirroring phone tabs (Today/Pulse/Train) · C) Glance ring + petals (concept 4) · D) NavigationStack list → detail
5. **Watch complications set** — A) Keep 10, restyle · B) Cut to 5 (readiness, water, workout, sleep, HR) · C) Cut to 5 + add a "Next dose" complication · D) Cut to 3

**Widgets / dashboard**
6. **Sleep half-ring stage encoding** — A) 4 stages as ring segments, one ramp · B) Segments + tiny stage labels · C) Ring = total vs goal, inner bar = stages · D) Two half-rings (duration / quality)
7. **Vitals tile graph style** — A) Sparkline per vital, 7 d · B) Radar/petal chart of 5 vitals vs baseline · C) Braille-dot heat strip (14 d) · D) Rings per vital
8. **Water tile** — A) Pitcher fill (SF-symbol-like) · B) Vertical bar of glasses · C) Keep ring, add pitcher only in the Large widget · D) Wave-fill card background
9. **Tile tap sensitivity fix** — A) Button + `.buttonStyle(.plain)` with 10 pt hysteresis and press-down feedback · B) Long-press peek + tap open (concept 3) · C) Only a chevron/door region opens · D) Tap opens, but scroll cancels with velocity threshold
10. **Dashboard stack auto-advance** — A) Remove all auto-advance; user paging only · B) Keep, but staggered per tile · C) Advance only when idle > 8 s and never during scroll · D) Replace stacks with a single tile carrying a page dot user taps
11. **iHerb** — A) Drop entirely · B) DSLD search only · C) DSLD search + barcode · D) DSLD + iHerb outbound "buy" link

**Logger / summary**
12. **HR segment legend** — A) No legend; segments coloured, exercise glyph inside the segment · B) No legend, no glyph; tap segment shows name · C) Numbers stay but move to a footer strip · D) Legend replaced by exercise-name ticks under the axis
13. **Exercise glyphs** — A) SF Symbols only (curated ~20 map) · B) Custom monoline glyph set (generate with AI, then vectorise) · C) Muscle-group colour dot, no glyph · D) First letter in a circle
14. **Delta indicators** — A) Remove; deltas in Progression sheet · B) Tinted numerals (concept 6) · C) Small arrow after the value · D) Keep, desaturate
15. **Session summary layout** — A) Bento grid (concept 5) · B) Accordion: header always open, rest collapsed · C) Horizontal carousel of exercise cards · D) Table (ledger) style
16. **Rest ±15 s** — A) Visual only, never stored · B) Stored locally as `actual_rest_sec`, excluded from export (today's rule) · C) Remove ± buttons entirely · D) Keep stored, export shows planned only

**Theme / appearance**
17. **8-colour set** — A) Clay · Ochre · Moss · Sage · Lagoon · Slate · Iris · Rosewood (45° spread) · B) Same but swap Ochre → Sand (lower chroma) · C) Six chromatic + two neutrals (Graphite, Bone) · D) 8 with a light/dark pair each (16 swatches)
18. **Theme → muscle groups** — A) 16 muscle tints derived from the theme hue (current approach) · B) Fixed anatomical palette, theme only tints chrome · C) Theme hue for prime movers, greys for the rest · D) Muscle colour = domain ramp (train) only
19. **Theme → macros/micros** — A) Fixed: protein/carb/fat as three fixed inks, micros theme-tinted · B) All theme-derived (current) · C) Macros theme, micros grey · D) All fixed
20. **Settings density** — A) System `.insetGrouped` with `.compact` row height + subheadline text · B) Custom rows, 40 pt, 15 pt text · C) Grouped chips (2-up) for toggles · D) Keep layout, just tighter paddings

---

## 1. watchOS sync — what exists, why "Start" reappears, and the fix shape

**Current architecture (verified in source):**
- One transport class on both sides: `WatchLink` (`native/Packages/OnyxData/.../Watch/WatchLink.swift:30-36`). Three channels: `updateApplicationContext` = `WatchContext` (userId, today, schedule, theme, tiles, swapPool); `transferUserInfo` = FIFO queue of set events, `SessionPulse` (open/finished/discarded/joined + the session row), water; `sendMessage` = pencil claim, `RestPulse`, and a *second copy* of open/joined only. **A finish is never messaged** (`WatchLink.swift:259-265`), by design (a message would overtake queued sets).
- No shared database, no shared App Group between phone and watch. The watch has its own GRDB store; the watch App Group `group.app.onyx.health.watch` is only watch-app ↔ watch-widgets.
- Tiles (battery, readiness, sleep, water, steps, kcal, stress, soreness, week marks) travel **only inside `WatchContext.tiles`**, pushed on sign-in, midnight, theme change, and store commits through a **2 s debounce feeding a 30 s throttle** (`AppEnvironment.swift:1410-1417`, 1497-1504). Heart rate crosses only as `RestPulse.bpm`.
- **There is no lifecycle flag on the wire.** "Is a session live today / finished today?" is inferred by each device from its own rows + pulse events.

**Root cause of the reported bug (three stacked defects):**
1. `RootView` picks the screen from `model.sessionId != nil` only (`RootView.swift:63-69`); `StartView` draws "Start" whenever `model.day != nil` (:276-289) and ignores `tiles.todayLogged` and whether today's session closed. `beginSession`'s only guard is `sessionId == nil` (`WatchModel.swift:343-360`) → `openSession` finds no `ended_at IS NULL` row → **creates a second session** and messages the open, which yanks the phone to the Train tab (`AppEnvironment.swift:546`).
2. The phone's finish arrives only via `transferUserInfo`; on simulators never, on hardware whenever the queue drains. Until then the watch sits in `SetView`/`FinishView` for a closed session and the Smart Stack card lingers ≤ 45 min.
3. `rejoinLiveSession` runs on every context push (`WatchModel.swift:1375`): if the open arrived but the finish did not, the watch re-adopts the closed session and restarts its HK workout. A finish for a non-adopted/mismatched id falls to `default: break` (:1431, 1450).

**Proposed sync architecture (three layers, all additive to existing types):**
- **Layer 1 — `SessionLifecycle` in `WatchContext`.** Add `session: {id, phase: open|finished|discarded, startedAt, endedAt, summary?}` to `WatchContext` and push it **immediately and unthrottled** on open/finish/discard (bypass the 30 s throttle for lifecycle; keep throttle for tiles). App context is a "latest state" slot, exactly the semantics a lifecycle flag needs; the queued pulse stays for ordering, the context is the truth the watch reads at launch and after any missed pulse. `StartView` becomes a switch on `context.session.phase` + `todayLogged`: `.finished` → mini-banner (§2), `.open` and not adopted → "Join", nil → "Start".
- **Layer 2 — finish also as a message, guarded.** Keep the queued finish for ordering **and** send a `sendMessage` finish that carries the expected set-event count; the receiver applies it only after its queue has drained to that count (or after a 5 s grace), so the ordering rule that forbade messaged finishes is preserved. The reverse direction (watch finish → phone) already messages.
- **Layer 3 — `rejoinLiveSession` consults lifecycle first.** Never re-adopt a session whose context phase is `.finished`/`.discarded`; tombstone it locally (v36 tombstones exist).
- Tiles freshness: split `WatchContext` push into `lifecycle` (instant) and `tiles` (throttled) — or shorten the throttle to 10 s. Both are one-line policy changes in `AppEnvironment`.

**Live RPE via Crown — feasible, medium cost.** The watch already has a Crown-driven RPE ladder on the rest cover (`RestView.swift:161-179`) but it writes an **amend event per detent** (defect: scrubbing 5 rungs = 5 transfers). The phone never persists an RPE on an unticked set (`LoggerModel.commitEdit` returns early unless `isDone`, `LoggerModel.swift:1688-1691`). Design: a new `sendMessage` payload `EffortPulse {sessionId, exerciseId, setIndex, rpe, band}` fired on Crown detent with a 150 ms debounce; the phone shows it as **provisional ink** on the deck card (colour band Hard/Very hard/Failure over the existing 8-stop ladder: 5–7.5 = steady, 8–9 = hard, 9.5 = very hard, 10 = failure); commit happens on the existing set tick, which already carries `rpe`. Debounce the watch's amend to end-of-scrub. Nothing new in the DB; one new message type; `EffortPulse` lives in `OnyxData/Watch/WatchPayloads.swift`.

## 2. watchOS UI — what exists, what changes

**Exists:** `NavigationStack` root with routes deck/dashboard; idle root = `DashboardView`, a `TabView(.verticalPage)` of four pages (start, today, train, fuel), each page ≤ 3 `OnyxTile.accessory` faces + water button; live root = `SetView` (2-page paging ScrollView: set / quality); rest = `fullScreenCover`. Corners already `OnyxCorner.row = 10 pt continuous` everywhere; **no literal squares exist on the watch** — the "square" feel is the `accessory` faces being rectangular complication faces reused as cards, on pure black with flat 10 %/18 % white fills (`WatchInk.swift:31-73`). Theme: phone sends `OnyxTheme.current.spec`; watch saves it to its App Group and widgets read it — **already synced**, but most `WatchInk` tokens are `static let` (frozen at first read; only `day(_:)` is dynamic) → a theme pushed mid-run does not repaint.

**Proposed watch dashboard:** page 1 = **daily summary** (readiness ring hero + four petals sleep/water/food/vitals, Crown-highlightable); pages 2–4 mirror phone tabs (Today / Pulse / Train) using the same `accessory` faces but wrapped in a new `WatchSlab` card: 16 pt continuous corners, 1 px top highlight, theme-tinted ink, `WatchInk` tokens become computed (fix defect 10). Fuel page gains a food face (kcal + macro bar).

**Post-workout mini banner:** replaces `StartView` when `context.session.phase == .finished` for today: name · duration · tonnage · avg bpm · PR count, with a small HR sparkline (`Spark` shape already exists in `RestView.swift`) — data comes from the new `summary` field on the lifecycle (phone builds it from `SessionAnalysis`), so the watch needs no telemetry query. Long-press → "Start another" for two-a-days.

**Remove/redundant:** the DEBUG `widgetPreview` route from release; the separate `train` dashboard page when a session is finished (folds into the banner); the `MirrorView` "Log here" pencil dance can become a one-tap on the live card.

**Watch features to add (brainstorm):** Crown RPE (above); Smart Stack "next dose" complication; auto-return to Now page after 30 s idle; HR zone colour on the live card; a "Skip rest" double-tap.

## 3. iOS + watch widgets — what exists, what changes

**Sleep half-ring — it still exists.** The half-ring is `DepthArc` (`OnyxUI/.../OnyxPrimitives.swift:529-673`): `Circle().trim(0…0.5)` rotated 180°, sweep = duration vs goal, fill split by stage. It left the three sleep tile faces in commit `4e7a5323` (W6, 6.3.0; parent `e6a48f2b` shows `SleepArcFace:508`, `SleepDepthFace:545`, `SleepLargeFace:649` all using it) and was replaced by `DepthStrip`. It **still draws** in `SleepSheetBody` (`Today/DomainSheets.swift:215`) and `SleepEditSheet:234`. Restoring it in the tiles and in Pulse's `SleepHeroCell` (`Pulse/PulseSleep.swift:164-305`, currently a 44 pt `DepthBar`) is a face swap, not new drawing. Stage colours today: deep/core/REM = three stops of the Lunar `recover` ramp (~0.07 L apart, known-tight), awake = `textSecondary`. Proposal: a **fixed 4-stop sleep ramp** (deep indigo → core lavender → REM pearl → awake grey) independent of theme, so the ring reads the same in all 8 themes (Q6, Q19).

**Vitals.** `VitalsView(.panel)` / `VitalLeadFace` / `VitalsPanelFace` (`OnyxVitals.swift`). No sparklines per vital on the tile; the payload already carries the 14-day series used by Pulse. Proposal in Q7.

**Water.** `WaterGlassFace` / `WaterLedgerFace` (`OnyxLifestyle.swift:345/396`); widget has a `+250 ml` `AppIntent` button. **Water colour is theme-derived (`body.end`, `OnyxTokens.swift:260`)** — the "always blue" rule the brief states is *not* what ships; it needs a new fixed token (§5 palette). Pitcher: `OnyxFigures` has no vessel shape; a `Pitcher` shape (rounded trapezoid + spout, fill level clipped) is ~60 lines and reuses the glass face's level math.

**Food.** `FocusFace(.calories)` / `CalorieLedgerFace` (P/C/F rails) / `CalorieDayFace`. **The widget payload `Macros` has no micronutrients** (`Snapshot.swift:114-136`); `.micros` tile id exists but is faceless on phone and carries no data. Adding 2–3 key micros to Medium/Large means: builder adds a `keyMicros: [(name, pct)]` array (top-3 by |deviation from target|, from the existing nutrient totals) → `Snapshot` field → face. Golden fixtures grow (three layout goldens rule from memory).

**Workout post-session widget.** "Done" truncation candidates (all `lineLimit(1)` + `minimumScaleFactor`): `TodayHeader` caption "DONE" (`OnyxTraining.swift:421-424`), accessory sub "done" (`OnyxAccessory.swift:161-162, 292`), quadrant "done · x t" (`OnyxDaily.swift:228-245`), the "Legs & Core B ✓" row (`OnyxLifestyle.swift:315-324`). Proposal: one `SessionMasthead` face (name · duration · tonnage · avg bpm · PR trophies) shared by the widget Medium/Large, the Train/Pulse session banner (`SessionHeaderCard`) and the watch mini banner — measured with `ViewThatFits`, never `lineLimit(1)` on the title.

**Stack auto-advance (the "all widgets scroll at once").** `SmartStackView` flips on a **wall-clock 9 s beat** (`:126, 209-216`); `stagger(slotId)` = hash mod 7 s for unlinked stacks; **`linked` stacks drop the stagger and flip on the same tick by design** (`:188-200`, flag on `StackSlot`, `Layout.swift:79`). Options in Q10. Cheapest correct: remove the clock entirely; keep swipe paging + a dot indicator.

**Scroll-opens-tile.** Three mechanisms, all in code: (1) `TileFrame` opens on a bare `.onTapGesture` inside the vertical `ScrollView` (`TileFrame.swift:125`) — no `Button`, so no UIKit tap-cancel-on-scroll and no press state; contradicts the design system's own `OnyxPressStyle` rule. (2) `SmartStackView` attaches a `DragGesture(minimumDistance: 10)` via `.simultaneousGesture` and sets `paging`, which disables the page scroll (`:293-300` → `TodayTabView.swift:127`) — a vertical scroll started on a stacked tile pages the stack instead. (3) Widget faces contain live `Link`s (`OnyxLifestyle.swift:272/274/412`, `OnyxTraining.swift:203/550/856`, `OnyxPerformance.swift:327/392`, `OnyxDaily.swift:116`) that win over the parent tap and switch tabs via `onyx://`. Fix shape: `Button` + `OnyxPressStyle` (press-down highlight, cancel on move > 10 pt), stacks page **horizontally** (orthogonal to the page scroll) or by tap on the dot, and `Link`s disabled inside the app via an environment flag.

## 5. iOS app — theme half (logger/summary/settings half below)

**Appearance today:** 9 presets in a fixed 3×3 grid (`Settings/AppearanceView.swift:108-129`), each a `MeshGradient` swatch of the four domain accents; committed on leave; locked during a workout. `OnyxThemeSpec{primary, secondary, chroma, lift}` hue-rotates **everything** from the Ion default: train/fuel/body/recover ramps, 16 muscle hexes (chroma only), macros (protein = `fuel.end`, carbs = `fuel.start`, fat = `recover.start`), water = `body.end`. Phase offsets (cut/bulk/deload) shift chroma/lift. Fixed today: base black, hairline, text, `danger E5484D`, `good 4CAF87`, `record FFD35C`. **No heart-rate token** — the Live Activity heart uses `danger`.

**Proposed 8-colour system ("Stone" palette, 2 rows of 4, ≥ 40° apart, chroma 0.10–0.13 OKLCH — sophisticated, not neon):**

| Row | Name | Primary (accent) | Secondary (fuel) | Mood |
|---|---|---|---|---|
| 1 | Slate | `6479A8` (h 245) | `C09A63` | steel blue, unisex default |
| 1 | Lagoon | `4F8FA0` (h 200) | `C98A6B` | muted teal |
| 1 | Sage | `6E9A80` (h 150) | `C9A05C` | grey-green |
| 1 | Iris | `7D6BA6` (h 285) | `C4986E` | dusty violet |
| 2 | Clay | `B5705A` (h 20) | `6E9A9A` | terracotta |
| 2 | Ochre | `B39250` (h 60) | `6A83A8` | old gold |
| 2 | Moss | `7F8F4E` (h 100) | `A87A8F` | olive |
| 2 | Rosewood | `A66280` (h 335) | `7A9A8A` | mauve |

Rule set: **theme drives** accent, train ramp, muscle family tints, chip/selection ink, the mesh swatch. **Fixed semantic inks (never themed):** water `4A9BD6`, heart rate `E5484D` (reuse `danger` as `vital.heart`), sleep 4-stop ramp, `good`, `record` gold, protein/carb/fat — Q19 decides whether macros are fixed. Muscle groups: Q18. The existing ≥ 35° test (`presetPrimariesStayThirtyFiveDegreesApart`) keeps passing at 8 × 45° spacing; the contrast guard (L 0.60–0.78, C ≤ 0.20) needs re-sweeping because these hues sit at lower chroma than Ion. Old 9 presets are deleted; a stored legacy blob maps to the nearest hue at first launch (one-time migration in `OnyxTheme.load`).

## 5. iOS app — logger / summary / settings (root causes, verified)

**Train tab + "Leave" — it is Gym Mode, not the logger.** `Button("Leave")` is `WorkoutTabView.swift:244`, gym mode's exit. On launch `resolveGymMode(canSwitchTab: true)` (`RootView.swift:186, 254-277`) reads `liveWorkout` + `sessionDueToday` + a ±90 min start window; if `selectedTab` is empty and due, it **switches to Train regardless of the setting** (:270-275) and hides the tab bar. Three real defects: (1) `sessionDueToday` is a pure schedule check that **ignores whether today's session is already finished** (`ScheduleContext.swift:206-213`) → gym mode re-arms every foreground inside the window after a finished workout; (2) `gymModeDeclined` is in-memory only (`AppEnvironment.swift:265`) and `onyx.gymMode.enabled` defaults **true** → Leave is forgotten on every cold launch; (3) `sessionFinished` never lowers `gymMode` despite two comments claiming it does. Fix: due = `sessionDueToday && !todayLogged && !liveWorkoutClosedToday`; persist the decline for the day (`AppStorage` dated key); lower gym mode in `sessionFinished`; gate the tab switch on the setting. Brief's "eliminate": Q-free — I recommend keeping gym mode as an opt-in (default OFF) rather than deleting it, since it is a real feature the founder built; say "delete" if you want it gone.

**Session summary (`History/SessionDetail/SessionDetailView.swift`)** — a `List` of six rows: masthead (`SessionHeaderCard`), 3×2 stat grid + `IntensityBar`, Hevy, Progression chart card, Muscle focus (96 pt atlas + legend), then one ledger card per movement (title `.display`, brief + sparkline, column heads, `SetRow`s at min 36 pt with a **reserved delta line under every number**). That reserved `.micro` line + 24 pt results floor + 16/12 padding is the scroll cost. HR chart is a bottom panel from the Avg HR cell (`TelemetryCard.swift:424-542`), ink = `recover.accent` (**theme lavender**, not red — founder token/name disagreement recorded in memory), segments by opacity `[1, .75, .55]`, numbered x-ticks + a `FlowRow` legend in raw `.caption2`.
- **HR always red:** add `Color.onyx.vital.heart = E5484D` (alias of `danger`) and use it in `TelemetryCard`, the Avg HR cell, `LoggerHero:300`, `LiveStatsView:1032`, Live Activity heart. One token, five call sites.
- **Treadmill → Walk:** HealthKit reader maps `.walking → "walk"` and **never reads `HKMetadataKeyIndoorWorkout`** (`HealthKitReader.swift:316-323`); `CardioKind` has no treadmill (`CardioImport.swift:19-28`); the warm-up card copies the last `cardio_logs` row's label (`LoggerModel.lastBout:1083-1091`) so sets log under "Walk". Fix: add `treadmill` kind, map `.walking + indoor → treadmill`, label "Treadmill", keep `walk` for outdoor; migrate existing indoor rows by re-reading the HK metadata where available.
- **HR segments:** options A/B in Q12; glyph source Q13. Note segments are already colour-free (opacity steps), so "segments only, no legend, tap shows name" is a deletion.
- **Delta indicators:** `SetRow.deltaLine` (`SessionLedger.swift:858-893`) draws `arrowtriangle.up/down.fill` + signed number, coloured `good`/`danger` — the childish part is red/green triangles. Q14.
- **±15 s:** the extension is **never stored** (`adjustRest` mutates in-memory `restEndsAt`/`restDuration` only, `LoggerModel.swift:1855-1863`); `actual_rest_sec` is the wall-clock gap between commits; the export prints only the plan's `restTargetSec` and suppresses "actual rest" with a `ponytail:` note (`WeeklyExport.swift:1652-1666`). **The brief's premise is false in code** — the export already reflects planned rest only. What may be leaking is `restActualSec` (mean measured gap) in the JSON/AI export (`WeeklyExportBuilder.swift:1224-1228`). Q16 decides whether that field stays.
- **Compaction:** concept 5 bento; Q15.

**Edit logger.** "Add a movement" is `if !model.isEditing` (`LiveLoggerView.swift:711-715`) — deliberate exclusion; enabling it in edit mode needs `appendCard` to seed from the session's own split (the `programDay` rule in memory) and `cancelEdit` already documents removing a movement added during the sitting. **Discard doesn't dismiss** because `LoggerModel.cancelEdit` returns false when `revertSessionEdits` returns nil (no-op sitting), while the store's contract says nil = "still close the screen" (`SessionEditing.swift:861-863` vs `LoggerModel.swift:2069-2081`); no error banner, `editWatermarked` stays true. One-line fix (treat nil as success). Dismiss goes to `SessionDetailView` (the cover's presenter), **not Train** — returning to Train means popping the summary too (`WorkoutTabView` owns `summary` via `navigationDestination(item:)`); a `dismissToTrain` closure is the clean way.

**Settings.** Stock `Form` with `LabeledContent` rows, `ultraThinMaterial` row backgrounds, `OnyxSectionHeader` footnote headers — no custom row component, so density is Form-default (≈ 44 pt rows, 17 pt titles). Q20.

**Supplements.** `custom_supplements` has `micros` JSON but the add sheet has **no ingredient/micros fields**; micros come from a hardcoded 9-product table (`SupplementNutrients.swift`). DSLD import (§4) fills exactly this hole.

**Tooling facts for the Opus prompts:** `visual-check` skill no longer exists (deleted in the epic sprint) — self-verification = `scripts/native-shot.sh` / `watch-shot.sh` + Read the PNG. Shots go to `SHOT_OUT` (gitignored); worktrees need `SHOT_OUT=<scratchpad>` and their own `SHOT_DERIVED`. OnyxTests baseline = 9 failing names (compare names, not counts). `git push` needs `[skip ci]` or `ONYX_DEPLOY=1`.

---

## Explorer-found defects the brief did not name (free wins to fold in)
- Watch: RPE Crown writes an amend event per detent; `WatchInk` tokens frozen at first read; complications show yesterday after midnight (`.never` timeline).
- Dashboard: widget-face `Link`s live inside the app (tab-switch instead of sheet); widget faces use fixed point sizes in-app (ignore Dynamic Type); Sleep drawn two ways (strip on tile, arc in sheet); `SleepHeroCell` and `sleepSegments` order stages differently.
- Logger: gym mode never lowered by `sessionFinished`; delta colour rules differ between ledger and metric grid; telemetry legend uses raw `.caption2`.
- Memory drift: "water is always blue" and "HR red token" were never true in code.

---

# WAVE PLAN + OPUS 5.5 PROMPTS

## Wave map

| Wave | Runs | Branch / worktree | Version at merge | Scope |
|---|---|---|---|---|
| **W0 Contract** | solo, first, on `main` via short branch | `onyx/w0-contract` | 8.1.0 | 8 Stone presets + semantic-ink table + weighted nutrition derivation + fixed water/heart/sleep/muscle tokens; wire types (`SessionLifecycle`, `EffortPulse`, `SessionMasthead`); delete gym mode; ledger stubs so A/B/C compile against final names |
| **Lane A Watch** | ∥ with B, C | `onyx/wA-watch` in `../onyx-lane-a` | 8.4.0 (merges last) | A1 lifecycle sync + Start/Join/Banner; A2 Glance-ring dashboard + WatchSlab + 5 complications + Next dose; A3 Crown `EffortPulse` + debounced amend |
| **Lane B Faces** | ∥ | `onyx/wB-faces` in `../onyx-lane-b` | 8.2.0 (merges first) | B1 tile Button/press + stagger + in-app Links off; B2 sleep `DepthArc` + vitals sparklines + pitcher + food micros; B3 `SessionMasthead` face everywhere (widget, banners, Live Activity/Dynamic Island) + Stone material + Appearance 2×4 |
| **Lane C Logger** | ∥ | `onyx/wC-logger` in `../onyx-lane-c` | 8.3.0 | C1 bento summary + HR red + segments-only + tinted deltas + SF glyph map; C2 treadmill kind + edit-mode Add movement + Discard fix + dismiss-to-Train + drop `restActualSec`; C3 Settings compaction + DSLD import |
| **W5 Replay** | after A/B/C merged | `onyx/w5-replay` | 8.5.0 | Session Replay card (phone + watch) + IG-Stories share export |
| **W6 Close-out** | last | `onyx/w6-closeout` | 9.0.0 (MAJOR: theme migration + gym-mode removal are user-visible) | icon install, `impeccable polish` pass on the 6 hero screens, memory/docs, plan → `docs/Done/` |

Merge order **W0 → B → C → A → W5 → W6**. Each lane rebases onto `main` before its merge; the merger (Fable session or the lane's own Opus agent, founder's choice) runs the gate below.

## Gate (every merge, no exceptions)
```
npm run check
xcodebuild test -project native/Onyx.xcodeproj -scheme Onyx -destination 'platform=iOS Simulator,id=<lane sim>' -derivedDataPath "$HOME/Library/Caches/onyx-swift/lane-<x>" 2>&1 | grep -E "Test Case .* (failed|passed)" | sort > /tmp/lane-<x>-tests.txt
# compare failing NAMES against the 9-name baseline; any NEW name blocks the merge
graphify update .
```
Then: `package.json` version → `npm run version:sync` → `cd native && xcodegen generate` → `docs/CHANGELOG.md` section (template at file bottom) → `npm run version:check` → `git merge --no-ff` → memory note.

## Concurrency rules for the three lanes
- Own only your lane's paths (§7 table). A needed change outside them = **stop and write it as a request in your wave record**, never edit.
- OnyxCore/OnyxData additions are **additive** (new files or new fields with defaults). Never rename or reorder an existing `Codable` key — `Dashboard.version` stays 4, `OnyxSnapshot` keys are wire.
- Layout goldens (`layout-catalogue.json`, `layout-defaults.json`, `layout-from-stored.json`) are Lane B only.
- `native/Onyx.xcodeproj` is generated — never hand-edit, never resolve conflicts in it; rerun `xcodegen generate`.
- One simulator per lane. Lane A uses the 26.5 pair (`iPhone 15 (W4 lane A 26.5)` + `Watch Ultra 2 (W4 lane A 26.5)`), Lane B `iPhone 15` (B5C31206…), Lane C creates `iPhone 15 (lane C)`. Shots: `SHOT_OUT=<scratchpad>/shots SHOT_DERIVED="$HOME/Library/Caches/onyx-swift/lane-<x>-shots"`.
- `ln -s <main checkout>/node_modules <worktree>/node_modules`. Run patches from scratchpad scripts if the Edit hook refuses. Always `cd` back to the worktree root after any command (graphify hook rebuilds in cwd). Never write a path containing the string `.git`.

## Shared prompt preamble (paste at the top of every Opus prompt)
```
You are an Opus 5.5 build agent on Onyx (native iOS + watchOS, Swift 6 / SwiftUI, XcodeGen, packages OnyxCore/OnyxData/OnyxUI). Read `CLAUDE.md`, then load skills: `native` (runbook — read before touching native/ or scripts/src/), `apple-design`, `ui-ux-pro-max` (run its search for each new component: `--stack swiftui`), `impeccable` (run `impeccable context`; use `polish` at the end of each sub-wave), `superpowers:verification-before-completion`, `superpowers:test-driven-development` for every engine/model change. Agents: `swift-expert` for concurrency/Sendable, `ui-ux-designer` for a visual critique of each shot, `invariant-auditor` after any OnyxCore math edit, `code-reviewer` before the wave record.
Founder decisions are binding: read `docs/Plan-Onyx-Overhaul.md` § FOUNDER DECISIONS. You do not need founder approval inside this wave. Do not ask questions; record open calls in the wave record.
Self-verification loop (max TWO rounds per sub-wave): build → run the shot script for the screens named below at default size AND AX5 AND `SHOT_THEME` = Slate, Clay, Iris → open every PNG with the Read tool → write a checklist per shot (alignment, truncation, contrast ≥ 4.5:1, hero rule, spacing on the 4/8/12/16 grid, dark only) → fix all findings in one batch → re-shoot once → stop. Then `rm -rf $SHOT_OUT/*`. Watch shots: 49 mm and 40 mm via `scripts/watch-shot.sh`.
Gates before you finish: `npm run check`; OnyxTests failing NAMES ⊆ the 9-name baseline (record the list); `graphify update .`; wave record appended to the plan; memory note in `~/.claude/projects/-Users-michael-Documents-PyCharmProjects-Onyx/memory/` (what surprised you, what the next wave inherits). Do NOT bump the version or touch CHANGELOG — that happens at merge. Commit per sub-wave with conventional messages; do not push.
Worktree: <path>. Branch: <branch>. Simulator: <UDID(s)>. Derived data: `$HOME/Library/Caches/onyx-swift/lane-<x>`. Shots: `SHOT_OUT=<scratchpad>/shots`.
```

---

## PROMPT W0 — Contract (solo, blocks the lanes; ~1 day)

Worktree: main checkout, branch `onyx/w0-contract`. Version at merge 8.1.0.

**Tasks**
1. **Theme presets.** In `native/Packages/OnyxCore/Sources/OnyxCore/Design/OnyxTheme.swift` replace `presets` with exactly eight, in this grid order: row 1 Slate `6479A8`/`C09A63`, Lagoon `4F8FA0`/`C98A6B`, Sage `6E9A80`/`C9A05C`, Iris `7D6BA6`/`C4986E`; row 2 Clay `B5705A`/`6E9A9A`, Ochre `B39250`/`6A83A8`, Moss `7F8F4E`/`A87A8F`, Rosewood `A66280`/`7A9A8A`. Default = Slate. Chroma 0.85–0.95, lift 0. Keep `presetPrimariesStayThirtyFiveDegreesApart`; re-run the contrast sweep and adjust L within 0.60–0.78 until it passes — record final hexes in the wave record. Add `OnyxTheme.migrateLegacy(_:)`: a stored blob whose primary is not one of the eight maps to the nearest hue; called once from `load`.
2. **Semantic ink table** (concept 7). In `OnyxTokens.swift` add a documented `enum OnyxInk` split into `Themed` (accent, train ramp, chip/selection, mesh swatch) and `Fixed`: `water = 4A9BD6`, `heart = E5484D` (alias `danger`), `sleep` 4-stop ramp deep `4B4A8A` → core `7B76B8` → rem `B8B3E0` → awake `textSecondary`, `good`, `record`. Add `muscleFixed` = the current 16 `defaultMuscleHex` frozen (theme no longer rotates muscles, decision Q18); `muscle()`/`muscleFamily()` read it.
3. **Weighted nutrition derivation** (decision Q19). Macros (protein/carbs/fat), calories and micros derive from the theme with a **dampening weight**: hue shift × 0.35, chroma clamped to ≤ 0.12, lightness unchanged. Implement as `OnyxThemeSpec.weighted(_:weight:)` and use it for `protein/carbs/fat/calories/micro` colour accessors. Test: for all 8 presets, ΔE between any two presets' protein colour ≤ 12 (stays recognisable) and ≥ 3 (still shifts).
4. **Wire types** (additive, `OnyxData/Watch/WatchPayloads.swift` + `OnyxCore`): `SessionLifecycle {sessionId, phase: open|finished|discarded, startedAt, endedAt?, summary: SessionMasthead?}` as optional `WatchContext.session`; `EffortPulse {sessionId, exerciseId, setIndex, rpe: Double, band: EffortBand}` with `EffortBand {steady, hard, veryHard, failure}` mapped from the 8-stop ladder (5–7.5 steady, 8–9 hard, 9.5 veryHard, 10 failure); `SessionMasthead {name, durationSec, tonnageKg, avgBpm?, prCount, hrSpark: [Double] (6 pts), startedAt}` in `OnyxCore/Sessions/`. Add `WatchLink` cases for `.effort` (message-only) — no senders yet. Golden-JSON round-trip tests for all three (whole-second dates).
5. **Delete gym mode** (founder decision): remove `GymModeSetting`, `GymMode.swift`, `GymModeReader`, `resolveGymMode`, the `gymMode`/`gymModeDeclined` state, the "Leave" button (`WorkoutTabView.swift:233-256`), the tab-bar hide (`RootView.swift:128`), the Settings toggle, the `gym-mode` harness screen and its shot. Initial tab is always `.today`; the watch-opened hook (`AppEnvironment.swift:546`) may still switch to Train. Update `docs/` references.
6. Lane stubs: make sure `OnyxUI` exposes `OnyxInk` publicly and `SessionMasthead` is `Codable + Hashable + Sendable`.

**Verify:** `npm run check`; `swift:core`, `swift:data`, `swift:ui`; shots `appearance today train session` (all 3 themes) — Appearance will still show the old grid (Lane B redraws it), that is expected. Record in wave record which existing screenshots changed colour.

---

## PROMPT LANE A — Watch (A1 → A2 → A3, one agent)

Worktree `../onyx-lane-a`, branch `onyx/wA-watch`, sims = 26.5 pair (`2DC9C91C…` iPhone 15, `33ABD301…` Watch Ultra 2) — the iOS 27 sim has no WatchConnectivity. Owns: `native/OnyxWatch/**`, `native/OnyxWatchWidgets/**`, `native/Onyx/App/PhoneWatchBridge.swift`, `AppEnvironment.pushWatchContext/publishPhase` only, `OnyxCore/Watch/**`, `OnyxData/Watch/**`. Read first: `docs/SIMULATORS.md`, memory `appstore-w4-session-sync`, `expansion-w3-watch-logger`, `expansion-w4-watch-dashboard`, `wave-10-watch`.

**A1 — Lifecycle sync (decision Q1, Q3)**
- Phone: build `SessionLifecycle` in `PhoneWatchBridge` on open/finish/discard (hooks already exist at `LiveLoggerView.swift:321, 830, 849` and `PhoneWatchBridge.swift:399`); `summary` from `SessionAnalysis` at finish. Push it through `updateApplicationContext` **immediately, bypassing the 30 s throttle** — split `pushWatchContext` into `pushLifecycle()` (instant) and the existing throttled tiles push. Keep the queued `SessionPulse.finished` for ordering AND add a `sendMessage` finish carrying `expectedEventCount`; the watch applies it only once its queue has drained to that count or after 5 s.
- Watch: `RootView`/`StartView` switch on `context.session?.phase` + `tiles.todayLogged`: `.finished` today → **`SessionBannerView`** (name · tonnage · avg HR · PR count + 6-pt `Spark`), long-press → "Start another"; `.open` not adopted → "Join"; nil → "Start". `beginSession` refuses when phase is `.finished` for the same day unless "Start another". `rejoinLiveSession` never re-adopts a session whose lifecycle is finished/discarded (tombstone locally, v36). Handle the `default: break` at `WatchModel.swift:1450` — log and tombstone unknown finished ids.
- Tests: `WatchConvergenceTests` cases: phone finish with a lagging queue; context arriving with `.finished` after a missed pulse; two-a-day. Golden: banner fixture.
- Shots: watch `start finish dashboard` + new `banner` screen (add to `watch-shot.sh`), 49 + 40 mm; phone `watch-sync`.

**A2 — Dashboard (decisions Q4, Q5) + WatchSlab**
- New `WatchSlab` card: 16 pt continuous corners, 1 px top highlight (white 0.12), `.thinMaterial`-class frost over pure black, theme-tinted ink; **`WatchInk` tokens become computed** (fix frozen `static let`s) so a pushed theme repaints live.
- Page 1 **Glance**: readiness ring hero (uses `tiles.readiness`) with four petals (sleep, water, food, vitals) on a 200 pt circle; Crown rotates the highlighted petal (`.digitalCrownRotation` with detents + haptic click), tap opens the domain page. Pages 2–4 = Today / Pulse / Train mirrors using `OnyxTile.accessory` faces inside `WatchSlab`; Fuel page gets a food face (kcal + macro bar) and keeps the water button. When `session.phase == .finished` the Train page is the banner.
- Complications: cut `WatchComplications` to readiness, water, workout, sleep, heartRate and add `nextDose` (reads the next unlogged dose from `WatchTiles` — add `nextDose: {name, at}` to `WatchTiles`, phone fills it from `customSlotsForDate`). Keep kind strings for the five survivors; document removed kinds in the changelog request. Fix the after-midnight stale face: timeline entry at next midnight instead of `.never`.
- Layout test: measure with `axe describe-ui`, not guesses (memory: 64 pt nav bar). 40 mm must not clip the ring.
- Shots: watch `dashboard train fuel widget` + new `glance` screen, 49 + 40 mm, three themes.

**A3 — Crown RPE (decision Q2)**
- Watch rest cover: Crown detent → `EffortPulse` via `sendMessage`, 150 ms debounce, band colour on the ladder; the **amend event fires once at end-of-scrub** (fix the per-detent amend at `RestView.swift:176-179`).
- Phone: `PhoneWatchBridge` receives `.effort` → `LoggerModel.provisionalEffort[setId]`; `ExerciseCardView` draws the provisional RPE as tinted ink + band capsule on the deck card (steady = theme accent, hard = Ochre-class warm, veryHard = Clay-class, failure = `OnyxInk.heart`); the existing tick commits `rpe` and clears the provisional. Never persist an unticked RPE (memory rule).
- Tests: debounce coalesces 5 detents into 1 amend; provisional never reaches `set_events`; band mapping golden.
- Shots: watch `rest`, phone `logger` with a provisional set (add a harness flag), three themes.

Wave record + memory. Do not merge; Fable merges A last (8.4.0) after rebasing on B and C.

---

## PROMPT LANE B — Faces (B1 → B2 → B3, one agent)

Worktree `../onyx-lane-b`, branch `onyx/wB-faces`, sim `iPhone 15` (B5C31206…). Owns: `native/Packages/OnyxUI/**`, `native/OnyxWidgets/**`, `native/Shared/WorkoutActivity*`, `native/Onyx/Features/Today/**`, `native/Onyx/Features/Pulse/**`, `native/Onyx/Features/Settings/AppearanceView.swift`, `OnyxCore/Widget/Snapshot.swift` + `WidgetSnapshotBuilder` (additive), the three layout goldens. Read first: memory `widgets-sprint-w4-tiles`, `widgets-sprint-w9-pulse-squares`, `next-gen-w7-dashboard-face`, `live-ux-w5-theme-water`, `themes-sprint-w2-palette`, `sleep-v2-w3`.

**B1 — Touch truth (decisions Q9, Q10)**
- `TileFrame`: replace `.onTapGesture` with `Button` + `OnyxPressStyle` (press-down scale 0.96 + highlight, UIKit cancels on scroll). Add `@Environment(\.onyxInApp)`; every widget-face `Link` (`OnyxLifestyle.swift:272/274/412`, `OnyxTraining.swift:203/550/856`, `OnyxPerformance.swift:327/392`, `OnyxDaily.swift:116`) renders as plain content when in-app. `SmartStackView`: paging becomes **horizontal** swipe (orthogonal to page scroll; drop the `scrollDisabled(paging != nil)` coupling) + tappable dots; auto-advance stays but **every stack gets its own phase** — `linked` no longer removes the stagger (spread staggers over the full 9 s, not 7). Never advance within 3 s of a touch anywhere on the grid.
- Tests: `TodayModelTests` stagger uniqueness for linked slots; a UI test that a 30 pt vertical drag over a tile does not open a sheet.
- Shots: `today today-stack-linked today-sheet today-edit` at default + AX5.

**B2 — Sleep, vitals, water, food (decisions Q6, Q7, Q8)**
- Sleep: restore `DepthArc` in `SleepArcFace`/`SleepDepthFace`/`SleepLargeFace` (reference the pre-6.3.0 layout at commit `e6a48f2b`) and in Pulse `SleepHeroCell`; colours from `OnyxInk.Fixed.sleep`; unify the stage-order rule (`sleepSegments` vs `SleepHeroCell`) in one OnyxCore helper.
- Vitals: `VitalSparkFace` — one 7-day sparkline per vital (HRV, RHR, SpO₂, temp, respiration) with today's dot, theme ink; Small shows 2, Medium 3, Large 5. Uses the 14-day series already in the snapshot (slice 7).
- Water: new `Pitcher` shape in `OnyxFigures` (rounded trapezoid + spout, level clip), fixed `OnyxInk.Fixed.water`, +250 ml intent button stays; `WaterGlassFace`/`WaterLedgerFace` adopt it.
- Food: builder adds `keyMicros: [KeyMicro {name, pct}]` (top-3 by |deviation from target| from the existing nutrient totals) to `OnyxSnapshot.Macros`; Medium shows 2, Large 3 as compact rails under P/C/F. Regenerate the three goldens per the memory procedure (prove `sl-daily` tail + byte-identical reformat first).
- Widget faces adopt `@ScaledMetric` where they render in-app (fix fixed-point sizes).
- Shots: `today today-mega today-sheet today-sheet-vitals widgets pulse-squares sleep-edit fuel` + Home Screen widget gallery via `widgets`; three themes; AX5.

**B3 — Masthead + Stone + Appearance (decisions Q17, concept 1, 7, 8, challenge C1/C8)**
- `SessionMasthead` face (`OnyxUI/Tiles/OnyxMasthead.swift`): name · duration · tonnage · avg bpm (`OnyxInk.heart`) · PR trophies, `ViewThatFits` three tiers, **never `lineLimit(1)` on the name**. Used by: widget Medium/Large post-workout, `SessionHeaderCard` (Train + Pulse banners), `WorkoutActivityCard` (Live Activity expanded), watch banner (Lane A reads the same model). **Dynamic Island compact** = duration (leading) + heart glyph + bpm (trailing) only; minimal = heart + bpm; expanded = the masthead. Kill every "Done" truncation site listed in §3.
- Stone material: `OnyxGlass` tile/sheet levels become the slab — near-black base, `.thinMaterial` frost so scrolling content blurs behind, 1 px top highlight, no drop shadow, radii 28/20/12 by depth. Apply through the existing `.onyxGlass` modifier so no call site changes.
- `AppearanceView`: fixed **2×4** grid of the eight presets; swatch = slab with the theme's accent seam (not a 4-colour mesh); name under swatch; live preview strip (tile, chip, macro rail) above the grid; still locked while a session is live; still commits on leave.
- Shots: `appearance appearance-locked today train session logger widgets` three themes + AX5; Live Activity via `logger-timer`.

Wave record + memory. Fable merges B first (8.2.0).

---

## PROMPT LANE C — Logger / Summary / Settings / Supplements (C1 → C2 → C3, one agent)

Worktree `../onyx-lane-c`, branch `onyx/wC-logger`, sim: create `iPhone 15 (lane C)` from the iPhone 15 device type on the 26.5 runtime. Owns: `native/Onyx/Features/{Logger,Workout,History,Settings (not Appearance),Supplements}/**`, `native/Onyx/Features/Pulse/StackView.swift` + `PulseModel.addSupplement` only, `OnyxData/{History,Health,Day}/**`, `OnyxCore/{Cardio,Reports,Supplements,Exercises}/**`. Read first: memory `appstore-w3-logger`, `session-table-3-3-0`, `hotfix-live-state-3-10-0`, `export-v6-wave`, `appstore-w5-supplements`, `ui-polish-sprint-3-2-0`.

**C1 — Session summary (decisions Q12–Q15, concepts 5, 6)**
- `SessionDetailView` becomes a bento: row 1 `SessionMasthead` (Lane B's face — until B merges, use the `SessionMasthead` model with a local placeholder view named `MastheadPlaceholder`, swap at rebase); row 2 HR strip full width, **inline** (not a panel), segments by opacity only, no numbers/legend, tap segment → callout (name · avg bpm · duration) ; row 3 2-column grid of `ExerciseChip` (name + SF glyph, best set, PR trophy, tap → the ledger card in a sheet); row 4 `FocusPills` (top-4 muscles as capsules); row 5 one `Progression` button → the chart in a sheet. Target ≤ 1.1 screens at default type on 393 pt; measure and record.
- HR red: use `OnyxInk.heart` in `TelemetryCard`, the Avg HR cell, `LoggerHero:300`, `LiveStatsView:1032`.
- Deltas: `SetRow.deltaLine` → tinted numeral (up = theme accent, down = `textSecondary`), hairline under PR rows, no triangles; delete the reserved empty delta line (row min height 30). Metric grid uses the same rule.
- Glyphs: `ExerciseGlyph.symbol(for:)` in `OnyxCore/Exercises/` — ~20 SF Symbols by movement pattern (`figure.strengthtraining.traditional`, `dumbbell`, `figure.rower`, `figure.walk.treadmill` …) keyed off `Flags`/`MuscleMap` pattern; golden test that every catalogue exercise resolves.
- Shots: `session session-ledger session-records session-cardio telemetry-detail set-row set-row-records` + AX5 + three themes.

**C2 — Truth fixes (decisions Q16 + brief bugs)**
- Treadmill: add `treadmill` to `CardioKind` (label "Treadmill", icon reuse); `HealthKitReader` maps `.walking` + `HKMetadataKeyIndoorWorkout == true` → `treadmill`; manual cardio sheet offers it; one-time backfill re-reads HK metadata for existing `walk` rows from the last 90 days where the HK UUID is stored. `MuscleMap` already has both entries.
- Edit mode: enable "Add a movement" when `isEditing` (seed from the session's split via the `programDay` rule; `cancelEdit` already documents removal). Fix `LoggerModel.cancelEdit` to treat a nil revert as success (store contract `SessionEditing.swift:861`); clear `editWatermarked`. Add `dismissToTrain` closure: `SessionDetailView` pops itself after the cover dismisses when the edit was opened from the post-workout push (`WorkoutTabView.summary = nil`). Tests in `SessionEditModeTests`: discard on a no-op sitting dismisses; add-movement in edit persists and reverts.
- Rest: ± stays visual; remove `restActualSec` from `ExportTypes`/`WeeklyExportBuilder` JSON + AI export; `restTargetSec` only; regenerate the golden markdown via the `ONYX_REGOLD` path; delete the suppressed "actual rest" branch and its `ponytail:` note.
- Shots: `train-cardio logger session set-row-cardio`; export golden diff reviewed and pasted in the wave record.

**C3 — Settings + DSLD (decisions Q11, Q20)**
- Settings: keep `Form`; `listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))`, titles `.subheadline`, detail `.footnote`, `listSectionSpacing(16)`, section headers 11 pt tracked; toggles `.controlSize(.small)` where allowed; About/account rows collapse into one section. Measure: whole Settings ≤ 1.6 screens at default type (record before/after).
- DSLD import: `DSLDClient` (`OnyxData/Supplements/`), `URLSession`, base `https://dsld.od.nih.gov/dsld/v9/`, endpoints `search-filter` (by product name), `browse-brands` + `brand-products` (by company — founder asked for a company search), `label/{id}`. 4 s timeout, 3 retries with backoff, in-memory + on-disk 7-day cache, results paginated 20. UI: "Add from label database" in `StackView` → search field with a Product / Brand segmented control → result rows (brand · name · serving) → detail → **prefill** `SupplementEditSheet` (name, form, dose amount/unit, `micros` JSON from ingredient rows mapped through the existing nutrient keys; unknown ingredients kept as `otherIngredients: [String]` on the item for the export). Barcode: optional camera button (VisionKit `DataScannerViewController`) → Open Food Facts `product/{barcode}.json` name → DSLD search; hidden when camera unavailable. Offline/failed → the manual sheet with a one-line notice. Tests: decoder goldens for one real `label/{id}` JSON (commit a fixture), timeout path, micro mapping.
- Shots: `you stack stack-add` + new `stack-import` harness screen (fixture-backed, no network in shots), AX5.

Wave record + memory. Fable merges C second (8.3.0).

---

## PROMPT W5 — Session Replay (after A/B/C; decision F2 + challenge)

Branch `onyx/w5-replay`, version 8.5.0. Owns everything (sequential).
- `SessionReplayModel` (OnyxCore): from `SessionAnalysis` build a 10 s timeline: HR trace draws itself (0–6 s), sets drop in as dots on the trace at their timestamps (2–8 s), PR rows flash gold (8–9 s), masthead settles (9–10 s). Pure data → keyframes; tests on timing invariants.
- Phone `ReplayCard` on `SessionDetailView` (row 0, above the masthead, plays once on appear, tap replays, respects Reduce Motion by jumping to the final frame). Watch `ReplayView` reached from the banner (3 s condensed).
- Share: `ImageRenderer` (PNG 1080×1080) and a 1080×1920 **Stories** variant with a deep premium backdrop — a two-stop radial of the theme accent over near-black with the Stone slab frost, data at 72 % width, safe zones top 250 / bottom 340 px; video via `AVAssetWriter` at 30 fps, 10 s, same frames. `ShareLink` with both. No new storage.
- Shots: `session` (replay final frame), the Stories PNG opened with Read, three themes.

## PROMPT W6 — Close-out

Branch `onyx/w6-closeout`, version **9.0.0**.
- Icon: founder supplies `resources/icon.png` (1024, no alpha). Update `scripts/generate-icons.mjs` to also emit an Icon Composer `AppIcon.icon` (Xcode 26) beside the appiconset; watch appiconset from the same PNG; `xcodegen generate`; verify on both simulators' Home Screens.
- `impeccable polish` on: Today, Pulse, Train, Session summary, Settings/Appearance, watch Glance. One batched fix round.
- Memory consolidation (`anthropic-skills:consolidate-memory`): retire "water always blue / HR token" drift, gym-mode notes, old preset list. Move this plan to `docs/Done/Plan-Onyx-Overhaul-Done.md`; CHANGELOG 9.0.0 names the theme migration and gym-mode removal as the MAJOR reasons; `docs/APP_STORE.md` screenshot list re-shot with `store-shots.sh`.

---

## Verification (end-to-end, after W6)
1. Fresh install on the 26.5 pair: sign in → Today opens (no Train, no Leave) → start a workout on the phone → watch shows Join → join → Crown RPE on the watch tints the phone card live → finish on the phone → within 2 s the watch shows the banner; Start does not reappear; tapping the banner long-press starts a second session cleanly.
2. Today: 30 pt vertical drag over every tile never opens a sheet; a tap does with a visible press; linked stacks flip at different moments.
3. Appearance: pick each of the 8; water stays `4A9BD6`, HR `E5484D`, sleep ring identical stages; macros shift subtly (ΔE 3–12).
4. Session summary ≤ 1.1 screens; HR strip inline, no legend; treadmill session names "Treadmill"; edit → Discard on an untouched sitting closes and returns to Train.
5. Weekly export JSON has no `restActualSec`; markdown golden unchanged except that field.
6. Supplements: search "Thorne" as brand → pick a product → sheet prefilled with per-ingredient micros; airplane mode → manual sheet with notice.
7. Gates: `npm run check` green on `main`; OnyxTests failing names ⊆ baseline 9; `npm run version:check` at 9.0.0; `graphify update .` committed.

---

## Wave record — W0

Branch `onyx/w0-contract` (Opus 5.5, worktree `.claude/worktrees/agent-a9e6c75dd16d19e7e`), four commits on `4c2d5d2b`: `93acc087` theme/ink/nutrition, `8b8b578f` wire types, `f1be8139` gym-mode deletion, `4f57b2f1` shot-review fix. Version NOT bumped (merger takes 8.1.0).

**Path correction.** `OnyxTheme` and its presets live in **OnyxUI** (`DesignSystem/OnyxTheme.swift`), not OnyxCore; only `OnyxThemeSpec`/`OKLCH` are Core. Tasks 1–3 share two files, so they landed as one commit.

### Final preset hexes (chroma 0.90, lift 0, every one its own `normalised()`)
| | Primary | Secondary | OKLCH L / C / h (primary) | on black |
|---|---|---|---|---|
| Slate (default) | `6A7FAF` (draft `6479A8`) | `C09A63` | 0.60 / 0.078 / 265.9 | 5.27 |
| Lagoon | `4F8FA0` | `C98A6B` | 0.614 / 0.070 / 217.0 | 5.77 |
| Sage | `6E9A80` | `C9A05C` | 0.647 / 0.062 / 158.2 | 6.60 |
| Iris | `8A73AE` (draft `7D6BA6`) | `C4986E` | 0.60 / 0.091 / 301.6 | 5.14 |
| Clay | `B5705A` | `6E9A9A` | 0.614 / 0.094 / 38.4 | 5.43 |
| Ochre | `B39250` | `6A83A8` | 0.676 / 0.094 / 83.3 | 7.14 |
| Moss | `7F8F4E` | `A87A8F` | 0.622 / 0.091 / 120.5 | 5.94 |
| Rosewood | `AC6886` (draft `A66280`) | `7A9A8A` | 0.60 / 0.095 / 352.4 | 5.08 |

**What the guard forced.** Slate (L 0.579), Rosewood (0.581) and Iris (0.569) sat under the L 0.60 floor → lifted to 0.60, hue and chroma kept. The drafted Iris (h 297.5) sat **32.0°** from Slate and broke `presetPrimariesStayThirtyFiveDegreesApart` — no lightness change fixes a hue gap, so Iris moved **+4° to h 301.6** (35.7° from Slate, 50.8° from Rosewood). Every secondary was already in the box. The hue-circle contrast sweep passes unchanged, and a new per-preset assertion checks every domain start/end ≥ 4.5:1 for the eight as shipped.

**Default vs origin.** `OnyxThemeSpec.default` is Slate; a new `OnyxThemeSpec.origin` keeps the Ion/Solar pair the 24 domain hexes were measured against, and `OnyxTheme.derive` rotates against `origin`. `migrateLegacy` (called by `apply(json:)` for drawing and written back once by `load`) maps: Ion→Slate, Ember→Clay, Solstice→Ochre, Meridian→Lagoon, Aurora→Sage, Vesper→Iris, Glacier→Lagoon, Verdigris→Moss, Nocturne→Rosewood.

### Weighted nutrition (Q19) — and the ΔE the brief asked for
Implemented as `OKLCHConvert.toward` — the step is taken along the **Oklab chord** from the default ink to its fully-turned self (weight 0.35, C ≤ 0.12, L kept), not as `0.35 × Δh` of hue rotation. Measured: plain angle scaling has a seam at ±180° from Slate (Ochre +175° → +61°, Moss −145° → −51°, 40° apart on the wheel but 112° after scaling) and gave protein **ΔE 2.5–19.2** — past the ≤ 12 bound. The chord is linear in weight and seamless. All inks move by the **primary's** shift (the secondaries bunch: row 1's four are golds within 30°, so a secondary-keyed carbs ink could not move). Pairwise Oklab ΔE×100 across the eight, as shipped:

| ink | default hex | closest pair | widest pair |
|---|---|---|---|
| protein | `DA7E7A` | 2.4 (Slate/Iris) | 8.1 (Iris/Moss) |
| carbs = calories | `C09A63` | 1.9 (Sage/Moss) | 6.1 (Iris/Moss) |
| fat | `A0A3D4` | 1.6 (Slate/Iris) | 5.0 (Sage/Rosewood) |
| micro (new) | `D98BB3` | 2.2 (Ochre/Moss) | 7.5 (Lagoon/Clay) |

**The brief's "≥ 3 for every pair" is arithmetically unreachable** under its own constraints: with weight 0.35, C ≤ 0.12 and primaries ≥ 35° apart, the closest pair is at most 0.35 × 2·0.12·sin(17.5°) = 2.5 for ANY dampened derivation, and fat/carbs sit at C 0.07–0.085. The test asserts ≤ 12 (recognisable) and ≥ 1.5 (no two presets collapse), with the reason in a comment. Raising the floor to 3 needs weight ≈ 0.7 or chroma ≥ 0.14 on every macro — a founder call.

### Semantic ink table
`OnyxInk.Themed` {`accent`, `train`, `selection`, `mesh`} and `OnyxInk.Fixed` {`water 4A9BD6`, `heart E5484D`, `sleepDeep 4B4A8A`, `sleepCore 7B76B8`, `sleepREM B8B3E0`, `sleepAwake`=textSecondary, `sleep` ramp, `good`, `record`, `muscle(_:)`}, doc-commented as a two-column table in `OnyxTokens.swift`. `Color.onyx.water` → Fixed.water; `OnyxSleepStage` → the fixed ramp; `muscle()`/`muscleFamily()` → the fixed `defaultMuscleHex` (the theme's per-muscle dictionary is gone). `Color.onyx.micro` is new; `calories` now equals `carbs`.

### Wire types (additive)
OnyxCore: `SessionMasthead` (init enforces a 6-point `hrSpark` or empty; `spark(_:)` buckets ≥ 6 samples into means, < 6 by nearest sample) and `EffortBand(rpe:)`. OnyxData: `SessionLifecycle` as optional `WatchContext.session` (own `Phase` — no `joined`), `EffortPulse` (band defaults from rpe), `WatchLink.Inbound.effort`, `Kind.effort = "effort"`, `send(effort:)` (message-only, no caller), decode branch, and `break` handlers in `PhoneWatchBridge` and `WatchModel`. Golden JSON tests in `WatchPayloadTests` (whole-second dates) + an old-context-without-`session` test.

### Gym mode — deleted
Files removed: `native/Onyx/Features/Shell/GymModeSetting.swift`, `native/Packages/OnyxCore/Sources/OnyxCore/Training/GymMode.swift`, `native/Packages/OnyxCore/Tests/OnyxCoreTests/GymModeTests.swift`, `native/Packages/OnyxData/Sources/OnyxData/Training/GymModeReader.swift`. Code removed: `RootView.resolveGymMode` + its `.task`/scene-phase calls + tab-bar hide + `.animation`, `AppEnvironment.gymMode`/`gymModeDeclined` (and their resets at sign-out/midnight), `WorkoutTabView` Leave button + `hadSession` lowering, Settings → Logging toggle, `PreviewHarness` `gym-mode` case + environment, the `gym-mode` entry in `scripts/native-shot.sh`, and `AppDatabase.liveWorkoutInProgress` (its only production caller was the launch door; two test references dropped). `TodayModel.minuteOfDay` inlined the two-line clock read it borrowed from `GymMode`. Docs: one line in `docs/COMPACTION_AUDIT.md`. **Behaviour change:** a cold launch with a workout still open now lands on Today, not Train (that was pre-gym-mode behaviour folded into the same door); the watch-opened hook still follows the wrist onto Train.

### Gates
- `npm run check` — green (version, types, body, atlas, mirror, doms, report, `swift:ui` 45/45, `check:watch` BUILD SUCCEEDED).
- `npm run swift:core` 734/734 (after GymModeTests deletion); `npm run swift:data` 772/772 (one run hit the known `SeamBenchmarkTests` nutrition flake; clean on re-run).
- iOS app (generic) and watch app builds green.
- OnyxTests on iPhone 15 `B5C31206…`: 203 tests, 21 issues, **exactly the 9 baseline names** — History weeks ×2, Live Stats fixture ×2 (really `SessionSummaryHotfixTests`), Session summary hotfix ×3, Workout week ×2. OnyxDataTests on the sim: the Gate-0 Keychain blob test + the seam-benchmark flake. **No new names.**
- `invariant-auditor` on the colour-math commit: clean.
- `graphify update .` run (outputs left uncommitted for the merger, per the shared-file rule).

### Screenshots reviewed (default size, Slate / Clay / Iris): appearance, today, today-sheet (sleep), train, session, fuel
- Water bar: `4A9BD6` blue in all three. Sleep sheet half-ring and legend: identical deep→core→REM→awake in all three.
- Muscle chips on the session masthead: identical in Clay and Iris (fixed palette).
- What changed colour vs 8.0.0: every accent (Slate is bluer and quieter than Ion); protein/carbs/fat/micro now drift only slightly per theme; water no longer follows `body.end`; sleep stages no longer follow the Lunar ramp.
- Round 1 finding, fixed (`4f57b2f1`): under Clay the kcal bar, the seven-day kcal series and `MacroEditSheet`'s kcal field were TEAL — they read `OnyxDomain.fuel` (the theme's secondary at full rotation) while the macros moved 35%. Now `Color.onyx.calories`. The Appearance footer claimed a theme moves "all sixteen muscles" — rewritten. Round 2 re-shot fuel + appearance in Clay: clean.
- Appearance still draws the old 3-column grid with 8 swatches and "Even" under every name — expected, Lane B redraws it.

### Open calls for the lanes
1. **ΔE floor** (above): ≥ 3 is unreachable at weight 0.35 / C ≤ 0.12; founder decides whether to raise weight or macro chroma.
2. **Nutrition inks ignore the phase offset** (cut/bulk/deload no longer mute them) — they read the default theme's hexes, not the reacted ramps. Lane B: say if a deload should mute them.
3. **Micro ink `D98BB3` is a new hex** (muted orchid). Lane B/C: `NutrientsView` still uses good/danger/fuel — adopt `Color.onyx.micro` for the nutrient's own ink.
4. **Other `OnyxDomain.fuel` call sites** that mean "calories" may remain outside Nutrition (widgets' calorie faces, `FocusFace(.calories)`, `NutritionTabView:381` estimated-day ink). Lane B owns the faces.
5. `sleepDeep` is 2.6:1 on black — a fill only, never a text ink (Lane B's `DepthArc` legend must use text tokens).
6. `WatchLink.receive(.effort)` has no unit test — `receive` is internal and no OnyxTests target has `@testable import OnyxData`; the payload decode is covered by the golden. Lane A adds one with the sender.
7. `WatchContext.session` has no sender yet (Lane A). The watch still saves `next.theme ?? .default` — `.default` is now Slate.
8. `AppearanceView` prose still describes nine presets / a 3×3 grid in comments — Lane B's rewrite.
9. Commit trailer: this wave's commits carry the session's `Claude Opus 5.5` co-author line (the builder's model), not the `Fable 5.1` line the brief named.

---

## Wave record — Lane B

Branch `onyx/wB-faces` (Opus 5.5, worktree `.claude/worktrees/agent-a8181a9aa97a3fb7a`) on `c55173ff` (8.1.0). Commits: `e7b9dadc` B1, `780a0127` B2, `66b71013` B3 masthead/island/Stone, `4c49e027` B3 Appearance, `dfc29469` review fixes, `ae81ea3a` island contact sheet, plus this record. Version NOT bumped (merger takes 8.2.0); CHANGELOG untouched.

**Path corrections.** `TileFrame` is in `Features/Today/`, not `OnyxUI/Dashboard/`. `WidgetSnapshotBuilder` is in **OnyxData/Widget**, not OnyxCore — the selection rule went in `OnyxCore/Widget/KeyMicro.swift` (owned) and the builder took one additive call + `microTotals` (no lane owns OnyxData/Widget; recorded here because the brief tasks the builder).

### B1 — Touch truth (Q9, Q10)
- `TileFrame`: `Button` + `OnyxPressStyle(scale: 0.97, highlight: true)` (new `highlight` option = +6 % brightness while pressed). The ScrollView's pan now cancels the tap. `.contextMenu` and the edit badges unchanged.
- `\.onyxInApp` (`@Entry`, default false) + `FaceLink`: all eight widget-face `Link` sites render plain content in the app. Set once at `TodayTabView`'s root so its sheets inherit it (the only in-app host of widget faces; Pulse draws none).
- `SmartStackView` pages **sideways** (`|dx| ≥ 10 && |dx| > 1.5·|dy|`) with tappable page dots in the bottom gutter; the `paging` latch and `scrollDisabled` are gone. `SmartStackView.phases(_:)` spreads the rotating stacks **evenly over the full 9 s** in layout order — distinct by construction; `linked` no longer touches the beat. `GridTouch` (TodayModel, `@MainActor`): no stack advances within **3 s** of any grid touch (scroll phase, tile tap, stack swipe/dots); a stack swipe's touch-up never opens that stack's sheet (per-slot guard).
- The **Connected** toggle in Edit Stack is removed — its only effect was the shared beat Q10 abolished. `StackSlot.linked` stays on the wire; `Dashboard.version` stays 4.
- Tests (`TodayModelTests`): `phasesSpread`, `linkedStacksHaveDistinctBeats`, `gridTouch`, `takesTheDrag` rewritten for the horizontal axis (a 30 pt vertical drag is never the stack's). W7's `linkedStacksShareTheBeat` deleted (superseded by Q10).
- **UI-level check** (no XCUITest target exists): on the booted sim, a 30 pt vertical drag over the Recovery tile scrolled and presented nothing; a tap on the same point opened the Recovery sheet — two screenshots reviewed.

### B2 — Sleep, vitals, water, food (Q6, Q7, Q8; W0 open calls 3, 4, 5)
- **Sleep:** `DepthArc` restored in `SleepArcFace`/`SleepDepthFace`/`SleepLargeFace` (the `e6a48f2b` layouts) and in Pulse `SleepHeroCell` (arc 96×56 beside the Dynamic Type duration; `DepthArc(showsLabel:)` keeps its bowl empty there). `DepthStrip`, `StageKey`, `SleepStripAxis`, `DepthBar` deleted (no callers). One stage rule: `OnyxCore.SleepStage.segments` (depth order; nil absent, zero kept) used by tiles, Pulse and `SleepEditSheet` — the three spellings disagreed (deep-core-REM vs deep-REM-core). Legends use text tokens; `sleepDeep` is fill only.
- **Vitals:** `VitalSparkFace` is the Vitals (`.panel`) tile: 2 / 3 / 5 readings by size in `VitalSpec.ranked` order, each a 7-night sparkline laid on the calendar with today's dot, themed ink, value + unit. `Sparkline(gapped: [Double?])` lifts the pen over a missed night; the `[Double]` init forwards.
- **Water:** `PitcherFigure` (rounded trapezoid, spout, handle, level clip, 2 pt meniscus) in fixed `Color.onyx.water` on all three water faces; `+250 ml` button unchanged. `GlassArc` view deleted; its arithmetic kept as `Glasses`.
- **Food:** `OnyxSnapshot.Macros.keyMicros: [KeyMicro]?` (Optional on the wire — synthesized Codable only tolerates a missing key for an Optional; faces read non-optional `micros`). `KeyMicro.top` excludes the Macros group, stack-delivered nutrients (the widget sums food only) and unmeasured ones; deviation = shortfall on a floor, overage on a ceiling. Fuel Medium shows 2, Fuel Large and Macros Large 3, as compact rails in `Color.onyx.micro`. Layout goldens NOT regenerated (no WidgetId changed).
- **Inks (open calls 3, 4):** `Color.onyx.calories` on the Fuel Small/Medium/Large and Macros Large headline registers, the Daily fuel quadrant, the Deficit Ledger, the fuel accessory, and `NutritionTabView`'s estimated-day dot; the water accessory reads `Color.onyx.water` (it was `fuel.accent`); `NutrientsView` short-of-floor ink is `Color.onyx.micro`.
- **Dynamic Type in-app:** every `.font(OnyxWidgetType.x(size))` in `Tiles/` (220 sites) became `.onyxWidgetFont { … size * $0 }`, scaled by `\.onyxFaceScale` — 1 on the Home Screen, `@ScaledMetric(relativeTo: .body)` clamped to **1.0…1.2** in `TodayTabView` (a tile is a fixed shape).
- Tests: `OverhaulFacesTests` (stage order, key-micro selection incl. surplus-on-a-floor, old-payload decode + round trip), `W6FigureTests` (pitcher level, gapped runs, vitals calendar week), `WidgetSnapshotBuilderTests.microTotals`.

### B3 — Masthead, Stone, Appearance (Q17; concepts 1, 7, 8; C1, C8; W0 open call 8)
- **`OnyxMasthead`** (`OnyxUI/Tiles/OnyxMasthead.swift`, public, cross-platform): name (accent bar, `lineLimit(2)`, never truncated) · clock · tonnage · heart (`OnyxInk.Fixed.heart`) · PR trophies (`record`). `ViewThatFits`: one row → 2×2 → 2×2 caption tier that shrinks. `init(_ SessionMasthead, accent:)` for Lanes A/C; `Clock` = `.elapsed / .running / .frozen`.
- Consumers: Today widget Small/Medium/Large finished state (`todayMasthead`, capped at xLarge) — the `DONE` caption, `TodayStats` and the Small's "68′ · 5.8 t" line are gone; the Daily quadrant's name wraps to 2 lines with "✓ 5.8 t"; the Fuel ledger's "Label ✓" became a check glyph + label.
- **Live Activity:** Lock Screen card opens with the masthead (live clock, running tonnage, current bpm, PRs). **Dynamic Island** compact leading = `WorkoutClock` (elapsed, monospaced), compact trailing = `WorkoutCompactTrailing` (heart + bpm in heart red, "—" with no watch), minimal = heart + bpm, expanded = `WorkoutIslandExpanded` (masthead + rest band only while resting) in the bottom region. `minimalGlyph` deleted. The rest countdown no longer shows in the compact island, by design (C8).
- **Stone:** `.onyxGlass` = `.thinMaterial` + `Color.onyx.slab` (#0B0B0E) at `slabTint` 0.78, a 1 px lit top edge fading to 0.04, **no drop shadows** at any level; `OnyxCorner` row/tile/sheet = **12 / 20 / 28**; Reduce Transparency draws the slab solid. No call site changed.
- **Appearance:** fixed 2×4 in preset order; swatch = slab with the accent as a diagonal seam of light, selected = accent ring + check; name under the swatch (capped at xxLarge); live preview of the DRAFT (tile, chip, protein rail, pitcher) in a clear Form row; still locked in a session, still commits on leave; stale nine-preset/3×3 comments and footer rewritten.

### Shots reviewed (round 1 → one batch of fixes → round 2, per sub-wave)
- **B1** (today, today-stack-linked, today-sheet, today-edit; Slate/Clay/Iris; default + AX5): dots horizontal in the bottom gutter. Found "RECOVE / RY" wrapping on the Recovery Medium → `Caption` is `lineLimit(1)` + 0.7 scale everywhere. Round 2 clean.
- **B2** (today-mega, today-sheet, today-sheet-vitals, day-hero, sleep-edit, fuel, nutrients + 30 widget pages): **half of the first run was solid black frames** (load 30–50 with three lanes building) → `SHOT_WAIT` added to `native-shot.sh`; re-shot at 14–16 s with no black frames. Found: the corner mark sat on "7 nights" and "avg 2.7 L" (→ `faceInset`), the vitals Large drew 0.5 % SpO₂ noise as full-height waves (→ capped at 36 pt), the Macros Large had an empty band (→ key micros), the spout read as a stick (→ reshaped).
- **B3** (appearance, appearance-locked, today, today-sheet-vitals, fuel, train, session, logger, logger-timer; 3 themes; + widgets incl. activity/island): Stone slabs read as near-black with a lit edge on every tab. The preview strip was a card inside a Form card (→ clear row), AX5 names sat on eight baselines and truncated "Rose…" (→ capped), and the island contact sheet still drew the pre-B3 arrangement (→ it calls the shipped views). Round 2 (Iris) clean.
- Contrast: text over the slab uses the same tokens over ≥ 78 % #0B0B0E, so `textSecondary` stays > 4.5:1. `sleepDeep` is never text.
- PNGs deleted after each round.

### Gates
- App + widget extension build (iPhone 15 sim) green after every commit.
- `swift:core` 737/737; `swift:data` 773/773 (the known `SeamBenchmarkTests` flake failed once earlier and passed on re-run).
- **OnyxTests** on `B5C31206…`: 205 tests (203 + 3 new − 1 deleted). Failing names are exactly the 9-name baseline: `HistoryWeeksTests.weekZero`, `.capsulesFoldByWeek`; `LiveStatsFixtureTests.fixtureFeedsTheArrows`; `SessionSummaryHotfixTests.incredibleDurationYieldsNoDelta`, `.credibleDurationStillCompares`, `.treadmillIsNamed`, `.noPreviousSetsInTheLedger`; `WorkoutWeekTests.finishFeedsTheTab`, `.progressionNeedsTwoSessions`. OnyxDataTests on the sim also failed the same Keychain blob and seam-benchmark pair W0 recorded. **No new names.**
- `code-reviewer` on the whole diff: 0 high, 2 medium (key-micro surplus on a floor; the masthead's last tier could not shrink), 5 low. All are fixed in `dfc29469` except "rest countdown left the compact island", which is the C8 decision.
- `npm run check`: **green** — version, types, body, atlas, mirror (up to date), doms, report, `swift:ui` 48/48 (incl. the new figure tests), `check:watch` BUILD SUCCEEDED.
- `graphify update .` run; `graphify-out/` left uncommitted.

### Requests for other lanes
1. **Lane C — `SessionHeaderCard`:** drop in `OnyxMasthead(masthead, accent: Color.onyx.day(dayKey))`, or the memberwise init with `.elapsed(seconds:)`. It wraps the name and shrinks the figures itself — do not add `lineLimit(1)`.
2. **Lane A — watch banner:** `OnyxMasthead` is cross-platform (no `OnyxWidgetType`); feed it `SessionLifecycle.summary`. `OnyxCorner.row` is now 12, and watch rows inherit it. `OnyxAccessory`'s rectangular "done" sub is still a word; Lane A owns the complication redesign.
3. **Lanes A/C — Stone:** anything that draws its own `.shadow` under an `.onyxGlass` card to fake depth should drop it; the slab has none.
4. **Merger:** `native-shot.sh` gained `SHOT_SKIP_BUILD` and `SHOT_WAIT`. The Stone radii (tile 16 → 20) change the corners in every screenshot, as expected.

### Open calls
1. **Nutrition inks do NOT react to cut/bulk/deload (W0 open call 2).** They stay as W0 shipped them: the trio must stay recognisable, and the phase already moves every themed accent. To change it, read `spec` instead of the default hexes in `OnyxTheme.init`.
2. The Today widget's finished **Medium** has an empty band under the masthead (it used to hold six stats). Options: session RPE + calories as a caption row, or the 6-point HR spark once the snapshot carries it (`OnyxSnapshot.Today` has no HR series; it would be an additive field for W5).
3. The Live Activity masthead drops "9/22 sets", which was in `WorkoutTotals`. The set line below still says "Set 3 of 4". It could return as a fifth figure.
4. `onyxFaceScale` is capped at 1.2×. Larger in-app type needs taller tiles, which is a layout-golden change.
5. The Stone slab tint (0.78) is a judgement between "frosted" (C1) and "onyx". It is one constant, `Color.onyx.slabTint`.
6. The project `.claude/CLAUDE.md` end-of-wave protocol (merge, purge caches) was NOT run: the lane brief forbids merging, and the caches are shared with lanes A/C.


## Wave record — Lane C

Branch `onyx/wC-logger` (Opus 5.5, worktree `.claude/worktrees/agent-a8fa8e3e04f4a9ec5`), on `c55173ff` (8.1.0). Simulator `iPhone 15 (lane C)` `83BF87B5-5D04-481D-A5EE-54850FC32578` (iOS 26.5). Commits: `922b353f` C1, `c72cd8ba` C2, `2f127cf4` C3, `7fe00780` review + shot fixes, `c1a41bde` mini-player shadow (Stone slab), `df80d21d` merge of `main` at 8.2.0 (Lane B, clean), `98b15f24` `OnyxMasthead` adopted. Version NOT bumped, CHANGELOG untouched (merger takes 8.3.0).

### C1 — Session summary (Q12–Q15)
- `SessionDetailView` is a bento: row 1 is `OnyxMasthead(SessionMasthead(page:label:), accent: Color.onyx.day(dayKey))` in a Stone slab on the day wash (built first as a local `MastheadPlaceholder`, swapped after the 8.2.0 merge; the Train tab's done card takes the same face through `SessionHeaderCard(masthead:)`); `HeartStrip` full-width inline (opacity steps of the fixed heart red, no numbers/legend/axes, tap a stretch → `movement · avg bpm · duration` in the strip's header line); a 2-column `Grid` of `ExerciseChip` (pattern glyph · name · best set · trophy; tap → that movement's ledger card in a sheet, which hosts its own record/trail sheets); `FocusPills` (top-4, fixed muscle palette; tap → atlas); one `ProgressionButton` → `SplitVolumeChart` + the full metric grid in a sheet.
- HR red: `TelemetryCard` ink, the Avg HR cell, `LoggerHero` heart chip, `LiveStatsView` effort cell, the ledger/Train cardio heart capsules. Telemetry legend and AX5 numbers use `onyxType`.
- Deltas (Q14): `SetRow.deltaInk(_:upIsGood:)` — better = `OnyxInk.Themed.accent`, worse = `textSecondary`, no change = the reading's own ink; no triangles, no red/green; the reserved delta line deleted (row floor 30, was 36); gold hairline under record rows. Metric grid, ledger verdict capsule, tonnage capsule and `PrRecordSheet` margin follow the same rule.
- `ExerciseGlyph` (OnyxCore/Exercises): 19 patterns → 18 SF Symbols, name rules first, `MuscleMap` primary mover second; documented fallback `figure`. Golden: every movement in `plan-templates.json` + the bout names resolves to its hand-written pattern; `OnyxTests` checks every symbol exists.
- Found in review: `atCeiling` printed `4/2 @ 12–20` on a unilateral card (sides over sets) — now counts a pair once, only when both sides reached the ceiling.
- **Measured (content height, 393 × 852 iPhone 15, visible 705 pt, default type):** before **2,465 pt = 3.50 screens**; after **511 pt = 0.73** (no HR series) / **623 pt = 0.88** (with the HR strip, `session-hr`). AX5: 2,151 pt (single-column chips; expected).

### C2 — Truth fixes (Q16 + brief bugs)
- Treadmill: `CardioImport.treadmill` ("Treadmill", `figure.walk.treadmill`, offered in the manual sheet). `HealthKitReader.cardioKind(_:indoor:)`: `.walking` + `HKMetadataKeyIndoorWorkout == true` → treadmill; outdoor/unstamped stays walk. `CardioImport.sameActivity` lets a treadmill bout match the walk row an older build filed, and `ingestCardio` relabels an IMPORTED walk (a hand-typed walk keeps the athlete's word). One-time backfill door `onyx.backfill.treadmill.v1`: closes at once if no keyed imported walk exists; otherwise runs the 90-day pass RELABEL-ONLY (never re-imports a deleted bout) and closes only once Health returned a workout for the quarter. `LoggerModel.lastBout` now names an indoor bout "Treadmill".
- **OnyxTests baseline name `a treadmill logged on this phone is titled Treadmill, not its slug` still fails** — it is not this bug: that test is about an unreconciled `onyx-treadmill` slug on a session row (`SessionSummaryHotfixTests`), unrelated to `CardioKind`. Left in the baseline.
- Edit mode: "Add a movement" shows on the edit deck (seeded via the `programDay` rule; `lastWorkingSet` still skipped on an edit deck). `cancelEdit` treats a nil `revertSessionEdits` as success (store contract) and clears `editWatermarked`; Discard removes movements the SITTING added (tracked by canonical key from `addExercise` only — a session's own off-plan movement restored by `attach(editing:)` stays). `SessionDetailView.dismissToTrain` — set only by `WorkoutTabView`'s post-finish push — pops the summary when the edit cover closes; History unchanged.
- Rest (Q16): `restActualSec` removed from `ExportExercise`, `WeeklyExportBuilder` and therefore the AI export (the envelope serialises the same input). `restPlanSec` kept (still carried by the builder; no reader removed). Suppressed "actual rest" branch + `ponytail:` note deleted.
- **Export golden diff** (regenerated via `ONYX_REGOLD`, then `restActualSec` stripped from the inputs; every non-markdown expectation byte-identical — structurally verified, and by `invariant-auditor`). Markdown: one line, in all 8 cases:
  ```
  - absence    a field with nothing behind it is OMITTED, never zeroed · — is a recorded blank in a table · none is an empty list · actual rest is withheld until the timer stores the extension it measured
  + absence    a field with nothing behind it is OMITTED, never zeroed · — is a recorded blank in a table · none is an empty list · rest is the plan's target; the timer's ±15 s nudges are not recorded
  ```
  Inputs: `"restActualSec" : 162` and `: 141` removed from the rich case(s) (10 deletions, 8 insertions total in the fixture).

### C3 — Settings + DSLD (Q11, Q20)
- Settings: `Form` kept; `.settingsRows()` = insets 6/16/6/16, `.settingsDensity()` = subheadline, `listSectionSpacing(16)`, 36 pt row floor, `.controlSize(.small)`; headers 11 pt semibold tracked; detail lines `.footnote`. Plan+Targets, Logging+Reminders, Display+History and About+account each merged into one section; a row whose VALUE answers it drops its detail line into the VoiceOver hint. **Measured: 1,689 pt (2.40 screens) → 1,114 pt (1.58 screens).** Note: `OnyxSectionHeader` is shared, so every Settings sub-screen (and `AppearanceView`, Lane B's) gets the 11 pt header.
- DSLD: `DSLD` (OnyxCore, pure: decoders, label → `Prefill`, unit conversion, brand dedupe) + `DSLDClient` (OnyxData actor). **The plan's base `https://dsld.od.nih.gov/dsld/v9/` answers every request with a Cloudflare "Just a moment…" challenge; the client uses `https://api.ods.od.nih.gov/dsld/v9/` (same v9 API, verified live 2026-09-24).** Product search = `search-filter?q=`; brand search = `browse-brands?method=by_keyword` (one hit per LABEL, deduplicated); a brand's products = `search-filter?q=*&brand=` (`brand-products` returns whole labels, 5× the bytes); `label/{id}`. 4 s timeout, 3 retries (0.3/0.6/1.2 s) on timeout/connection/5xx only, JSON-only 7-day memory+disk cache with stale-copy fallback offline, 20 per page, 300 ms debounce + `.task(id:)` cancellation. UI: Stack `+` menu → "Add from label database" → Product/Brand control + search → rows (product · brand · serving/form, off-market flagged) → label (ingredient · amount · %DV, dot = counts toward micros) → **Add** opens `SupplementEditSheet` prefilled (name, form, dose, per-unit micros; footer says how many count and how many are kept by name). Micros are per ONE unit of a count dose (`doseUnits` multiplies back), a mass serving stays ×1. Unmapped ingredients → `otherIngredients` on the item (`CustomSupplement.other_ingredients`, GRDB `v38.otherIngredients` — v37 was already `wristCoverage`, mirrored nullable). Barcode: VisionKit `DataScannerViewController` → Open Food Facts name → product search; **hidden until Info.plist carries `NSCameraUsageDescription`** (request below). Offline/failed → one-line notice + "Add by hand" (the manual sheet with the typed name).
- Fixtures committed: `dsld-label-323076.json` (Thorne Basic Nutrients 2/Day, real response, unredacted CC0), `dsld-search.json`, `dsld-brands.json`.

### Supabase DDL for the founder (paste BEFORE installing a build that imports a label — PostgREST rejects a row carrying an unknown column and it would sit in the outbox)
```sql
alter table public.custom_supplements
  add column if not exists other_ingredients jsonb;
```
(RLS is already on the table; the column is nullable and never written by hand-added items.)

### Shots reviewed (SHOT_OUT in the scratchpad; deleted after review)
- Round 1 C1 (`session session-ledger session-records session-cardio session-pairs set-row set-row-records`, Slate/Clay/Iris, default + AX5) + `ui-ux-designer` critique. Fixed: unequal chip heights (LazyVGrid → Grid), name truncation (lineLimit 2 removed), fixed 24 pt glyph track over the name at AX5 (scaled track), duplicate title in the ledger sheet, AX5 ledger sheet opens `.large`, masthead "kg" and stamp contrast (tertiary → secondary), date repeated from the nav title (start time only, labelled), green record margin in `PrRecordSheet`, `4/2` ceiling count. Round 2 re-shot: clean.
- C2 (`train-cardio logger logger-lifts session set-row-cardio logger-edit you`): "Add a movement" visible on the edit deck; heart capsules on the cardio card were the theme cardio ink → fixed heart red; the HR strip never appeared (a `.task` on a view drawing nothing never runs → the page loads the series). Added `session-hr` (seeded telemetry CACHE row, no HealthKit/signing) — strip verified.
- C3 (`stack-import stack-import-label stack stack-add you`, default + AX5): Product/Brand control 60 pt under the field → pinned under it (`searchScopes` hides until focus — rejected); label rows denser, %DV track holds `25000%`, AX5 "Vit-ami-n A" → stacked row. Re-shot: clean.
- After the 8.2.0 merge: re-shot `session session-hr session-cardio train-done` in Slate/Clay/Iris + AX5 with the `OnyxMasthead` face and the Stone slab — clean (the harness's `train-done` draws `SessionFallbackCard`, the header read has not landed in the fixture, so the faced done card is covered by the build, not a shot). PNGs deleted.
- Critique items NOT taken (open calls): cardio-only session has no hero numeral (distance as hero is a Lane B masthead-face decision); accent used for both the split name wash and "better" deltas; muscle/theme hue proximity checks.

### Gates
All on the MERGED tree (after `df80d21d`, main at 8.2.0):
- `swift:core` 749/749; `swift:data` 789/789 (earlier runs hit the known `SeamBenchmarkTests` nutrition flake once; clean on re-run).
- `npm run check` — exit 0 (version, types, body, atlas, mirror, doms, report, `swift:ui` 48/48, `check:watch` BUILD SUCCEEDED).
- OnyxTests on `83BF87B5…`: 213 tests, 21 issues, **exactly the 10 baseline names, no new name, none gone**: History weeks ×2 (`A capsule counts its week…`, `Week 0 is the week the block opened on`), `SessionSummaryHotfixTests` ×4 (`a credible previous session…`, `a previous session's impossible clock…`, `a treadmill logged on this phone is titled Treadmill, not its slug`, `the ledger rows are this session's sets…`), Workout week ×2 (`finishing a session leaves the tab on .done…`, `ready to progress fires only after…`), Keychain `stores, retrieves and removes a session blob`, `the seeded previous session reaches TopLifts.previousBests`. Baseline taken on unmodified `c55173ff` on this simulator before any edit.
- `code-reviewer` on the whole diff: 1 critical / 3 high / 5 medium / 3 low — all fixed in `7fe00780` except the two noted below. `invariant-auditor` (Cardio, Reports, Supplements, Exercises): clean.
- `graphify update .` run; `graphify-out/` left uncommitted.

### Requests for other lanes / the merger
1. **`NSCameraUsageDescription`** in `native/Onyx/Support/Info.plist` (or `project.yml` `info.properties`), e.g. "Scan a supplement's barcode to find its label." Until it lands the scan button stays hidden (no crash).
2. **Lane B / Pulse:** `PulseWorkout.swift` still calls `SessionHeaderCard(header:totals:)`; pass `masthead:` there too to put Pulse's workout card on the shared face (one argument; Pulse is not this lane's file). `SessionMasthead(page:label:)` leaves `hrSpark` empty — the page loads its series async for the strip.
3. Out-of-list files this lane touched because the brief required them: `OnyxData/Database/AppDatabase.swift` (`v38.otherIngredients`), `OnyxData/Mirror/MirrorModels.swift` + `native/schema/supabase.json` (the mirrored column, via `npm run mirror`), `OnyxData/Day/SupplementEditing.swift`/`DayEditing.swift` (write path, `hasImportedWalks`), `OnyxCore/Supplements/SupplementStack.swift` (additive `otherIngredients`), `Features/Pulse/StackView.swift` (whole sheet, allowed), `Features/Logger/PrRecordSheet.swift` (margin ink).

### Open calls
1. `otherIngredients` is stored and synced but not yet printed by the weekly export (it would restate the export golden); W6 or the next export wave.
2. Micros are stored per unit of the label's own serving unit; if the athlete switches a count dose to a mass unit in the sheet before saving, the payload is not rescaled.
3. OnyxTests baseline is **10 names on this simulator, not the 9 the W0 record lists** — the extra is `the seeded previous session reaches TopLifts.previousBests` (`PreviewCatalogueTests`, date-anchored); both lists were taken on unmodified `main`.
4. The ledger's measured-rest gutter (`actual_rest_sec`) still draws: it is not export (Q16 is about the export) — a row with a measured rest is one micro line taller than the 30 pt floor.

---

## Wave record — Lane A

Branch `onyx/wA-watch` (Opus 5.5, worktree `.claude/worktrees/agent-abbf8d3b953424894`), on `c55173ff`, merged `main` twice (8.2.0 `eaa1294f`, 8.3.0 `ab339bc2` — no conflicts). Commits: `c86fa694` A1, `47c1c8c0` A2, `ddc6859a` A3, `1ffcc584` review fixes, `4e5f9c52` banner on `OnyxMasthead`, `613be365` band inks from tokens, `73142741` measured Glance test. Version NOT bumped (merger takes 8.4.0). Two API-limit interruptions mid-A2; nothing was lost (every sub-wave committed before its shot round from then on).

**Path note.** The prompt listed only `WatchTiles`/`LiveWorkoutSnapshot` in OnyxCore; §7's lane table grants `OnyxCore/Watch/**`, and `WatchGlance` (geometry) went into `OnyxCore/Watch/WatchPanel.swift` on that basis. Outside the list, two one-line harness hooks: `PreviewHarness.swift` routes `logger-effort`, `LoggerPreviews.swift` gained that case (the brief's "add a harness flag").

### A1 — Lifecycle sync
- **Phone.** `PhoneWatchBridge` records a `SessionLifecycle` from every pulse it sends (open/finish/discard from `LiveLoggerView`'s existing hooks) and every wrist pulse it applies (`.opened`/`.closed`/`.discarded`), persists it per user (`onyx.watch.lifecycle`, so a relaunch cannot regress the slot), and puts it on EVERY context push. `AppEnvironment.pushLifecycle()` re-sends the last built context with the new lifecycle — the last tiles ride along, no debounce, no throttle; only a launch that has not pushed yet builds a full context. A finished lifecycle's masthead is rebuilt on each push off the closed row (`SessionMasthead(session:name:samples:)`: stored `total_volume_kg`, `pr_count`, `avg_bpm`, telemetry-cache samples → 6-pt spark), so the spark appears once `sessionFinished`'s prefetch lands. An OPEN word is checked against the row (closed → reported finished). Midnight/sign-in pushes carry it for free; a finished word is dropped once it is not today's.
- **Messaged finish.** A phone finish carries `expectedEventCount` = the phone's OWN events for the session and is also `sendMessage`d; the receiver counts events it did NOT write (`receivedEventCount`) and applies it when that reaches the count or after `SessionPulse.finishGrace` (5 s). The same count rides `SessionLifecycle.expectedEventCount`, and the context path waits too (review HIGH: it did not).
- **Watch.** `WatchFrontDoor.resolve` (pure, OnyxData): open & today → **Join**; finished today → **banner**; discard/nothing → Start; `todayLogged` with no word (old phone) → banner without masthead. `WatchModel.frontDoor` lays two local facts over Join (tombstoned here → Start; closed here → banner with this store's masthead). `SessionBannerView` = "Done" + Lane B's `OnyxMasthead(summary)` + the 6-point `Spark` in `OnyxInk.Fixed.heart`; long-press (0.6 s) → confirmation → `beginSession(another: true)`. `beginSession` refuses on a banner unless `another`, routes to `joinSession` on a Join. `joinSession` builds the row from the lifecycle (`date`/`dayKey`, new optional fields) through the ordinary `receiveSession`, adopting by id if the split differs. `applyLifecycle` runs before every rejoin (launch + context): finished → close the row (or insert it born-CLOSED if never seen — review HIGH: a tombstone here orphaned every queued set on the FK), discarded → discard + tombstone; the adopted workout is ended/cancelled only if the store actually changed (review MED: double `end`). `rejoinLiveSession` also refuses a live row the word calls finished/discarded. The old `default: break` retires the id and clears the Smart Stack card when nothing is live. A phone pulse is also written into the cached context (`noteWord`, never backwards) because a running sim app only gets a new context at relaunch.
- **Wire.** `SessionPulse.expectedEventCount`, `SessionLifecycle.date/dayKey/expectedEventCount` — optional, last, defaults. `WatchWire.swift`: the link's decode moved OUT of the `WatchConnectivity` fence (`WatchLink.Inbound` = typealias of `WatchInbound`), so `swift test` covers it — W0 open call 6 closed (`wireDecodesEffort`).
- Tests (OnyxDataTests): `WatchConvergenceTests` + "a messaged finish waits for the queue behind it…", "a context that says finished retires a session whose pulse never arrived" (incl. the late set landing in the born-closed row, discard tombstones), "two-a-day: … Start another opens a second session…"; `WatchPayloadTests` + wire decode, finish count compat, front-door table, masthead-from-row.

### A2 — Glance, WatchSlab, complications
- **Dashboard order:** Glance · Today · Pulse · Train (Start/Join/banner) · Fuel. `GlanceView`: readiness ring (theme accent, 8 pt stroke, `tiles.score`) + four corner petals (sleep `sleepREM`, water `Fixed.water`, food `calories`, heart `Fixed.heart`) with their own progress arcs; `.digitalCrownRotation` −1…3 by 1, detents + haptics, highlight scales the petal and swaps the centre reading; tap a petal or the centre → that page (sleep→Today, water/food→Fuel, heart/readiness→Pulse). Swipe pages from the Glance (its Crown is the highlight).
- **`WatchSlab`**: 16 pt continuous, `.thinMaterial` frost + 8 % page-ink wash over black, a one-device-pixel top highlight (white 0.12 → clear by mid-height), no shadow. Today/Pulse faces sit in it; Fuel gets `FoodSlab` (kcal, left/over, energy-share bar P·C·F at 4/4/9 kcal/g in the W0 weighted inks) over the water face (fixed blue) and the +1 glass button. Accessory captions draw `textSecondary` in full-colour mode (the hierarchical `.secondary` resolved to the slab tint, ~2.5:1).
- `WatchInk` tokens are computed; the app root re-ids on `WatchModel.themeKey` so a pushed theme repaints the whole wrist. The DEBUG `widgetPreview` route stays `#if DEBUG` (already compiled out of release).
- **Complications (6):** kept kinds `OnyxWatch.recovery` (Readiness), `.train` (Workout), `.water`, `.sleep`; new `OnyxWatch.heartRate` (`LastHeartRate`, saved on the live card's de-duped beat, fixed red, relative age) and `OnyxWatch.nextDose` (`WatchTiles.nextDose`, filled by the phone from `customSlotsForDate` → `stackForDate`, next timed slot after now). **Removed kinds for the changelog:** `OnyxWatch.fuel`, `OnyxWatch.steps`, `OnyxWatch.bedtime`, `OnyxWatch.stress`, `OnyxWatch.soreness`, `OnyxWatch.weekRings` (their faces still draw on the dashboard and the phone Lock Screen). Workout's "done" is now the masthead line ("8.4 t · 131 bpm · 2 PR") from `WatchTiles.finished`, folded in by the watch from the lifecycle (Lane B request 3).
- **Stale face:** tile timelines carry a midnight entry drawn through `WatchTiles.current(on:)` (nil once yesterday's → "—") and `.after(midnight)`; the watch app reloads all timelines at its own 00:00.
- `WatchTiles` + `carbsG` "cg", `fatG` "fg", `nextDose` "nd", `finished` "fs" — optional, last; Lane A fields cost < 80 B (test).
- **Measured (axe describe-ui):** Glance square **148 pt at 49 mm** (petals 40 pt at y 64…212, ring frame 101, centre label 68 × 19), **130 pt at 40 mm** (petals 35 pt at y 48…178, ring 88, centre label box 58 pt, "81" 39 pt). The first layout test fed `height − nav bar` (187/149.5) and passed on that guess — replaced by the measured squares. Clearance ring↔petal ≈ 6.1 / 5.4 pt.

### A3 — Crown RPE
- Watch: each detent → `EffortScrub` (OnyxData): `EffortPulse` message 150 ms after the Crown rests, ONE amend after 1 s still, `flush()` on the cover's disappear (and it cancels a pending pulse). The target set is pinned at the first detent (review MED). The amend runs only on the pencil holder — while the phone holds it the phone commits. The ladder pill fills with the band ink (0.32) + a 1 pt band stroke. `EffortPulse.setId` (optional, last).
- `EffortBand.ink` (OnyxUI/Accessory, both devices): steady = theme accent; hard = record gold → heart red at 0.25; very hard = the same at 0.6 (clay); failure = `Fixed.heart`. Mixed from fixed tokens because `TokenDisciplineTests` forbids raw hexes outside the token files (a first draft with two hexes failed it).
- Phone: bridge keeps the last pulse; `LiveLoggerView` hands it to `LoggerModel.receiveEffort` → `provisionalEffort[storeId]` (never persisted; 10-minute lifetime; a pulse naming a set this deck lacks is dropped, the resting-movement fallback is only for a pulse with no set id). `ExerciseCardView` draws it as a dashed band-ink capsule with the watch glyph in place of the effort word; tap = commit; the next tick commits every provisional on ticked sets; Finish commits too; an unticked set never commits.
- Tests: `EffortScrubTests` (5 detents → 1 pulse + 1 amend; pulses follow, amend once; flush once; W0 pulse decodes), OnyxTests `CrownEffortTests` (no `set_events` until the tick, then exactly +2; unticked/stale/foreign never commit).

### What the simulator proved, and what it could not
Observed on the 26.5 pair (ad-hoc signed, phone `watch-sync` harness): after `appInstalled` settled (~1–2 min), a relaunched watch received the context and drew **Join** ("Live on iPhone · 0:04") for a phone-opened session; tapping Start on the phone messaged the open and the RUNNING watch logged `pulse open … from the phone` → `HKWorkoutSession started` → `adopted …; HKWorkoutSession running: true` within ~1 s. Later harness Start taps did not re-present the logger (the preview store already held the live row), so the **phone finish → messaged finish → 5 s grace → banner** round trip was not photographed; its ordering, grace and banner logic are proven in `WatchConvergenceTests`/`WatchPayloadTests`, the banner itself by the `banner` shot. **Hardware only:** `transferUserInfo` delivery (queued finish/sets actually arriving behind the message), a context reaching a RUNNING app, `EffortPulse` round-trip to the phone deck, the HK workout end at the phone's instant, complications populated (Gate 0 strips the App Group on this team), Smart Stack/complication midnight reload.

### Shots reviewed (Read, every PNG; own checklist per shot)
Watch 49 + 40 mm: `start banner join finish dashboard` (A1), `glance dashboard pulse train fuel widget` + `glance pulse fuel restband banner` × Slate/Clay/Iris (A2/A3), `banner fuel` after the masthead swap; phone `logger-effort` + `watch-sync` (Slate, Clay; default + AX5 — the Iris phone pass did not produce files and was not re-run). Fixes, one batch per round: Join's stat row slid under the capsule (→ the live line replaces the stat row); `dashboard.png` photographed the finish card — a non-autostart shot after `finish` re-adopted the earlier shot's session (→ every non-autostart shot discards first); slab captions and the food caption in tinted `.secondary` (~2.5:1 → grey text token); water slab in Fuel honey (→ fixed water blue); seed lacked carbs/fat (→ seeded). Round 2 clean. Known and left: the 40 mm rest ladder truncates the longest rung gloss ("Max Effort · 0 left, form he…", pre-existing `minimumScaleFactor` floor). The `ui-ux-designer` agent was NOT run (two API-limit restarts); the critique is my own checklist above.

### Code review (`code-reviewer` agent, before this record)
2 HIGH / 5 MED / 3 LOW — all fixed in `1ffcc584` except LOW `frontDoor` reading the store on each render (three indexed reads on the idle root; left, noted). Items: context finish skipped the count wait; finish tombstones orphaned queued sets; double workout end; Crown amend on the wrong set; phone re-aimed a pulse; `record` could move backwards; whole-log counts could cancel out; Finish lost the last provisional; flush left a pulse pending.

### Gates (on the tree merged with 8.3.0)
- `npm run check` — green (version 8.3.0, types, body, atlas, mirror, doms, report, `swift:ui` 48/48, `check:watch` BUILD SUCCEEDED).
- `swift:core` 752/752; `swift:data` 800/800 (one run under shot load hit the known `SeamBenchmarkTests` nutrition flake; clean on re-run).
- OnyxTests on the 26.5 iPhone `2DC9C91C…`: 215 tests, 21 issues, failing names **exactly Lane C's 10-name baseline**: `A capsule counts its week…`, `Week 0 is the week the block opened on`, `a credible previous session still gets its delta`, `a previous session's impossible clock…`, `a treadmill logged on this phone is titled Treadmill, not its slug`, `the ledger rows are this session's sets…`, `finishing a session leaves the tab on .done…`, `ready to progress fires only after…`, `the seeded previous session reaches TopLifts.previousBests`, plus OnyxDataTests' Keychain `stores, retrieves and removes a session blob`. `Crown effort` passed. **No new names.**
- `graphify update .` run; `graphify-out/` left uncommitted for the merger.

### Requests for other lanes / W6
1. **`SessionHeaderCard`** (Lane C) could draw the spark under `OnyxMasthead` the way the watch banner does — `SessionMasthead.hrSpark` is already on the value.
2. **Tokens (W6):** lift the two mixed effort inks into `OnyxInk.Fixed` by name (`effortHard`, `effortVeryHard`) and point `EffortBandInk` at them.
3. **Changelog (merger):** six watch complication kinds removed (list above); two added.
4. The phone's own `Color.onyx.effort` (secondary / Solar / danger) and the new band inks now both describe RPE on the deck — one should adopt the other in W6's polish pass.

### Open calls
1. **`HKHealthStore.startWatchApp`** — still not built. With Join + the messaged open, a RUNNING or recently-woken watch follows within a second; launching a closed watch app from the phone's Start would close the last gap (founder call; needs a workout configuration and fails silently without HK authorization).
2. A **watch** finish still reaches the phone only by the queue (not messaged) — deliberately: the phone is the server's road, and closing its row before the wrist's queued sets land would push wrong totals. With the count mechanism in place it could be messaged the same way; not done.
3. Glance petals are 35 pt at 40 mm — under the 38–44 pt usual target; the centre and the Crown reach the same pages. Founder call if it should shrink the ring instead.
4. Split-pair sub-lines (`compactEffort`) do not draw the provisional capsule — only full-width effort columns do.
5. The Train page is page four now (Glance first, per Q4); the watch opens on the Glance, not on Start.


---

## Wave record — W5

Branch `onyx/w5-replay` (Opus 5.5, worktree `.claude/worktrees/agent-afb553bb013bc64fe`) on `ca48689b` (8.4.0). Commits: `6180f516` W5.1 replay, `88b5df40` shot + share-frame review fixes, `340e9163` W5.2 startWatchApp, `52b2dcd8` W5.3 leftovers, `01a66848` code-review fixes. Version NOT bumped, CHANGELOG untouched (merger takes 8.5.0).

### W5.1 — Session Replay
- **`SessionReplay`** (`OnyxCore/Sessions/SessionReplay.swift`, pure): `timeline(_ Input, duration:)` → `Timeline` { mode (`.trace` with ≥ 2 HR points, else `.tonnage`), ≤ 60 resampled trace points, per-movement bar segments, one `Dot` per set, monotonic `keyframes` }; `frame(at:)` → `Frame` { trackProgress, bar growth, per-dot drop, recordGlow, recordsLit, settle, currentMovement }; `final`; `masthead(at:)` (the video's count-up). Phases as fractions: track 0–0.6, dots 0.2–0.8, records 0.8–0.9, settle 0.9–1.0 → 0–6 / 2–8 / 8–9 / 9–10 s at 10 s, the same keyframes at 3 s on the watch. A dot at `x` drops at `0.2D + x(0.6D − drop)` and the track reaches `x` at `0.6D·x`, so a dot never lands ahead of the drawn track. Untimed sets interpolate between clocked neighbours (all untimed → evenly spaced). Tonnage segments = ½ work share + ½ set share, floor 4 % (pure tonnage knotted a bodyweight movement's sets at the end in round 1). **Records are AXES** (`SetMark.records`), the unit the masthead's `prCount` counts. 13 tests (`SessionReplayTests`): monotonic keyframes at 10 and 3 s, every set one dot inside 2–8 s, dots never ahead of the track (both modes), record count = masthead, phase boundaries, final frame, 3 s = 0.3 × 10 s, interpolation, tonnage bars, empty session, count-up.
- **`ReplayCanvas` / `ReplayCaption`** (`OnyxUI/Sessions/ReplayCanvas.swift`, cross-platform): one `Canvas` pass — smoothed trace in `OnyxInk.Fixed.heart` with a fading area wash and a pen nib while drawing; the tonnage bar in each movement's FIXED muscle ink (`Timeline.ink`, cardio ink for an unmapped movement); dots in the theme accent cut out of the line with a ring of the ground colour; record dots `record` gold with a one-shot ping and a quiet halo. Caption = the last-landed movement in its muscle ink, then "N movements · M sets".
- **Phone `ReplayCard`** — row 0 of `SessionDetailView`, a Stone slab: caption + 88 pt canvas (48 pt in tonnage mode). `TimelineView(.animation(paused:))`; plays once when the page's HR read AND the set-clock read have answered (so it never swaps bar → trace mid-play), tap replays, Reduce Motion never plays (final frame). Set clocks = first `append` `createdAt` per `exerciseId|setIndex` (`SessionReplay.Input.clocks`). No storage; nothing written.
- **Share** (`ReplayShare.swift`): `ShareLink(items:)` of three `ReplayShareItem`s — ONE `Transferable` type with two `FileRepresentation`s split by `exportingCondition`, so each file is rendered only when the share sheet asks for it: square PNG 1080², Stories PNG 1080 × 1920 (final frame), MP4 1080 × 1920 H.264 30 fps, **exactly 300 frames / 10.0 s** ending on the final frame (`endSession` at 10 s), rendered frame-by-frame through `ImageRenderer` on the main actor with `Task.yield()` per frame, cancellable, partial file removed on any failed exit. Measured on the iPhone 15 sim: **2.7–4.0 s** for the whole video. `ReplayShareFrame`: card + wordmark one block centred in the Stories safe band (top 250 / bottom 340 px), card at 72 % width, date line (the session's LOGICAL day), `OnyxMasthead` (counting up in the video), 170 pt chart, caption; backdrop = near-black slab + two-stop accent radial + a faint second glow + vignette; wordmark = `OnyxMark` + `OnyxWordmark` at 0.7.
  - **Deviation — scale 3, not scale 1.** The frame is laid out at 360 × 640 pt and rendered at scale 3 → the same 1080 × 1920 pixels. At 1080 pt the app's Dynamic-Type faces (`OnyxMasthead`) would be 1.4 % of the frame; a phone-sized layout at 3× is what a person sees on their own screen.
  - **`ImageRenderer` draws no material** (`.thinMaterial` renders nothing off-screen — `WeeklyWrapContent` says the same), so the Stone frost is painted: slab at 0.78 + 4 % white + top sheen + a lit gradient border. At 0.62 the backdrop's radial showed through as a bullseye (designer round).
- **Watch `ReplayView`** — banner tap (and a VoiceOver action) → sheet; caption (only when the wrist holds the session's sets), 48 pt canvas, `OnyxMasthead` settling at 2.7–3 s. Built by `WatchModel.replayTimeline(_:)` from the phone's masthead (its 6 spark points placed at their sixths' centres) + whatever sets this store holds for `context.session`. Records are NOT re-detected on the wrist (the PR engine replays the phone's ledger); the trophy count stays on the masthead. DEBUG screen `replay` in `watch-shot.sh`.
- Harness: phone `session-share` (HR fixture) and `session-share-bars` (no HR) write all three files through the real exporter and log `ONYXREPLAY` paths.

### W5.2 — startWatchApp
- Phone: `PhoneWatchBridge.send(session:)` on an `.open` pulse → `launchWatchApp()`: `WatchLink.reach` (paired, installed, reachable — iOS only) → `WatchLaunch.shouldStartWatchApp` (OnyxData, outside the WC fence) → `HKHealthStore.startWatchApp(with: strength / indoor)`; fire-and-forget, every skip/outcome logged (`app.onyx.phone` / `watch`), Start never waits.
- Watch: `WatchAppDelegate` (`WKApplicationDelegate`) now OWNS the app's `WatchModel` (review MED: a background launch may never run the root view's `.task`), and `handle(_ HKWorkoutConfiguration)` → `WatchModel.handleWorkoutLaunch()`: `start()` (idempotent) → no-op if a session is already adopted → else `applyLifecycle()` + `rejoinLiveSession()` — the ordinary cold-open path. A second `HKWorkoutSession` is impossible: `WorkoutSessionController.start()` guards `session == nil`, `rejoinLiveSession` guards `sessionId == nil`.
- Test: `watchLaunchDecision` (reachable → no call; not installed / not paired → no call; installed + unreachable → call).
- **Hardware only:** that `startWatchApp` actually launches the app (needs HK authorisation and a real pair — the sims have no workout launch), that the delegate's `handle` arrives before or after `.task`, and whether watchOS keeps a launched-but-idle app alive until the queued open lands (if it does not, the wrist adopts at next wake — no worse than 8.4.0).

### W5.3 — leftovers
- **Widget:** `OnyxSnapshot.Today.hrSpark: [Double]?` (optional on the wire, `spark` non-optional, init default `[]` → key omitted) filled by `WidgetSnapshotBuilder` from the longest session's telemetry cache (`SessionMasthead.spark`); the finished **Medium** draws it (24 pt, heart red, white in mono) in the band that was empty. Tests: cache → six points; no cache → no key; an old payload without the key decodes. Sample carries a spark.
- **`SessionHeaderCard`** draws the same line under `OnyxMasthead` when `hrSpark.count > 1`; `SessionHeader.hrSpark` is filled in `SessionAnalysis.headers` via Lane A's public `sessionMasthead(sessionId:userId:name:)`; the Train done card passes it, and **`PulseWorkout` now passes `masthead:`** (Lane C request).
- **Export:** `ExportSupplement.otherIngredients` + `SupplementRow.otherIngredients` (optional); the builder writes it (JSON export + the AI export, which serialises the same input); `consolidateSupplements` ends the line "· also A, B". New `supplements-consolidate` vector; builder test expects it on the creatine row.
- **Golden diff (ONYX_REGOLD):** regenerated `weekly-export.json` is **byte-identical — empty diff.** The Markdown has had no supplement line since export v5 (`4fa87315` removed the STACK section on purpose: "seven sections of data"); `consolidateSupplements` is the supplement line the goldens and the report read, and it now prints the ingredients. Re-adding a stack section to the Markdown is an open call, not done.
- **Effort tokens:** `OnyxInk.Fixed.effortHard = FBB359`, `effortVeryHard = F38554` (the Oklab mix of `FFD35C`→`E5484D` at 0.25 / 0.6, round-trip ΔE 0.09 / 0.07); `EffortBandInk` reads them. `EffortInkTokenTests` resolves the shipped `Color.mix` on the simulator and holds both tokens < ΔE 2 of it (passed — so SwiftUI's `.perceptual` IS Oklab-close; a linear-sRGB mix would have been 2.2 / 3.8 off).
- **DSLD count → mass: RESCALED, not cleared.** `DSLD.micros(_:amount:unit:)`: count→count unchanged (per unit); →mass = the label serving's TOTAL (per-unit × serving count), credited ×1; mass→count = the total split over the units typed. The W5 rule holds — a mass dose still never scales with the typed mass. `SupplementEditSheet.save` stores the re-based micros. Test `microsFollowTheSavedUnit`.

### Shots reviewed (Read, every PNG; SHOT_OUT in the scratchpad, deleted)
- **Round 1** (Slate; `session session-hr session-share session-share-bars`, default + AX5; the exported PNGs pulled from the sim container; four MP4 frames extracted with AVAssetImageGenerator): caption "11 PR" under a masthead of 9 (pair sides double-credited); tonnage dots knotted at the end; 88 pt card mostly empty around an 18 pt bar; share date "WED, 2 SEP" on a Tuesday session (UTC start instant); MP4 10.03 s (301 frames); masthead hidden for 9 s of the video. **`ui-ux-designer` round on the share frames** (13 findings): taken — card+wordmark as one block, bigger chart, slab 0.78 (bullseye), second glow + vignette, smoothed 2.5 pt trace, ring in the card's ink, smaller record ping, masthead visible and counting up, single PR count (caption drops its own), wordmark 0.7, radius 24 / padding 20. NOT taken (open calls): a 52 pt hero figure (would fork `OnyxMasthead`, the shared face), per-set tonnage columns, a closed ring mark (the brand mark is the mark), noise dither, a Clay-specific L cap, compressing the phases to hold a final frame (the 0–6/2–8/8–9/9–10 phases are the brief's).
- **Round 2** (Slate + Clay + Iris; `session session-hr session-share session-share-bars`): Stories PNG 1080 × 1920 and square 1080² verified by `sips`; MP4 10.0 s, 1080 × 1920, 30 fps, avc1 verified by AVFoundation; Clay backdrop reads warm-brown, not muddy. Found at AX5: the caption truncated ("5 movements · 9…") and the share glyph outgrew its 44 pt target → caption 2 lines, glyph capped at xLarge (fixed after the re-shoot; not re-photographed).
- **Watch** (49 mm Ultra 2, 40 mm SE 3): round 1 — "0 movements · 0 sets" on a phone-only session and the masthead's second row cut at 40 mm → no caption without sets, 48 pt track; round 2 — fits at 40 mm. Smoke re-shot after the delegate change: draws.
- **W5.3** (Slate): `widgets-24` shows `training-today-logged-systemMedium` with the heart spark in the band. The Pulse card and the Train done card are covered by the build, not a shot (`day-session` scrolls the card below the fold; the harness's `train-done` draws `SessionFallbackCard`, as Lane C recorded).
- Known and left: faint banding at the radial's centre in H.264 frames (8 Mbit/s); Instagram recompresses anyway.

### Code review (`code-reviewer`, before this record)
0 critical / 1 high / 4 medium / 5 low. Fixed in `01a66848`: HIGH — a pair's two sides can hold the same axis under one set number, flashing more records than the masthead counts → distinct axes once; MED — video cancellation + cleanup; MED — the final frame had no duration → `endSession` at 10 s; MED — delegate-owned watch model; LOW — caption index guard, zero-length guard, the "lands on drawn track" header wording for a late-starting series. Left (noted): `headers` makes two small reads per header for the spark (batch if History grows); fixed temp file names in `tmp/replay` (concurrent shares of one session collide; never cleaned); the watch replay reads sets for `context.session`, the same word the banner came from.

### Gates
- `npm run check` — **exit 0** (version 8.4.0, types, body, atlas, mirror up to date, doms, report, `swift:ui` **49/49**, `check:watch` BUILD SUCCEEDED).
- `swift:core` **766/766**; `swift:data` **803/803**.
- **OnyxTests** on iPhone 15 `B5C31206…`: 215 tests, 21 issues; failing names = **exactly Lane C's 10-name baseline** — `A capsule counts its week and marks the days that were missed`, `Week 0 is the week the block opened on`, `a credible previous session still gets its delta`, `a previous session's impossible clock produces no delta, not a wrong one`, `a treadmill logged on this phone is titled Treadmill, not its slug`, `finishing a session leaves the tab on .done…`, `ready to progress fires only after the ceiling is cleared twice`, `the ledger rows are this session's sets and only this session's`, `the seeded previous session reaches TopLifts.previousBests` (date-anchored), and OnyxDataTests' Keychain `stores, retrieves and removes a session blob`. The first run (before the review fixes) also tripped the known `SeamBenchmarkTests` "the nutrition day is one read" timing flake; the final run on `01a66848` did not. **No new names.**
- `graphify update .` run; `graphify-out/` left uncommitted.

### Open calls
1. **Markdown supplement line** — the export has had none since v5; `otherIngredients` reaches the JSON/AI export and the consolidated line only. Founder: re-add a stack section to the Markdown or not.
2. **Share frame hero figure** — the designer wanted one 52 pt figure (PRs or tonnage); declined to keep `OnyxMasthead` the one face. W6 polish can decide.
3. **Watch replay without the phone's sets** — a phone-only session replays its trace alone on the wrist (no dots); carrying set clocks in `SessionLifecycle` would fix it at wire cost.
4. **startWatchApp keep-alive** — if watchOS suspends a launched app before the queued open arrives, the wrist adopts on next wake. Starting the HK session from `handle(_:)` before the row exists would need a born-open row on the wrist; not done.
5. **Video frame rate of the renderer** — measured 2.7–4 s on a sim; on an older device it may be ~10 s behind the share sheet's spinner. A timeline-hash cache (ponytail note in `ReplayExporter.video`) is the next step if people share the same session twice.
6. The two warm effort inks now have names, but the phone's older `Color.onyx.effort` still exists beside them (Lane A open call 4) — W6.
