# ONYX — App Store 1.0

Everything App Store Connect asks for, in the order it asks. Written for Wave 8
of `NATIVE_MIGRATION_PLAN.md`, refreshed at Wave 2.12 (the rename) and re-run at
**Wave 2.13, the Phase 2 ship gate**. Fill the `⟨…⟩` placeholders in the web
form; every other line is already true of the binary and was verified against a
Release build, not asserted.

**The app is called Onyx, and so are the identifiers.** Phase 2.5's Wave 2 did
the rename all the way down, ahead of Gate 0 rather than after it — which was
free precisely because the App Group had never been provisioned, so there was
nothing to re-provision. Register `app.onyx.health.michael` in the developer
portal; the values in §1 are read from `native/project.yml`,
which is the source of truth (`native/Onyx.xcodeproj` is generated from it and
must never be hand-edited).

The `.native` suffix is a deliberate leftover of installing beside the retired
Capacitor build. It is never shown to anyone — but it is permanent once the App
ID is registered, so if you would rather ship `app.onyx.health.michael`, change
`native/project.yml` BEFORE the portal, not after.

---

## 0. Blockers — nothing below matters until these are done

Found by the Wave 13 preflight (2026-09-06). The first two are the ones a
reviewer hits before they ever open the app.

| # | What | Guideline | Where |
|---|---|---|---|
| 1 | ~~**The privacy-policy URL 404s.**~~ **CLOSED at U7 (2026-09-10).** `site/privacy/index.html` is static HTML (W6; U7 had it as a prerendered web route), served with no login in front of it, and its collected-data table is written in `PrivacyInfo.xcprivacy`'s own vocabulary so the policy, the manifest and §3 below cannot disagree. Re-verify with `curl -I` once Netlify publishes `site/`. | 5.1.1(i) | `site/privacy/index.html` · `OnyxLinks.privacyPolicy` |
| 2 | ~~**The support URL 404s.**~~ **CLOSED at U7.** `site/support/index.html`, same terms, plus a **Settings → About → Support** row that opens it. Re-verify with `curl -I` once Netlify publishes `site/`. | 1.5 | `site/support/index.html` · `OnyxLinks.support` |
| 3 | ~~**No demo account.**~~ **CLOSED.** E6 opened in-app sign-up (`SignUpView`) and seeded the account; U7 gave the sign-up sheet a real dismiss affordance. The account is `appreview@onyx.fitness` and it exists in Supabase — see §"App Review Information" for where the password lives and what to do if it ever has to be recreated. | 2.1 | §"App Review Information" |
| 4 | ~~**The metadata is still `⟨…⟩` placeholders.**~~ **CLOSED at U7** — §2 is written copy. | 2.1 | §2 |
| 5 | **Apple Developer Program membership.** A free personal team cannot sign the App Group entitlement or upload. **Still open — it is a purchase, not a commit.** | — | §"Gate 0" |

One more that is a decision rather than a defect:

- **The pages live on a Netlify subdomain, not a custom domain.** `onyx-health-fitness.netlify.app` serves only `site/` — the privacy policy, the support page and the AASA file. Apple accepts a subdomain; moving to a custom domain later is a change to `OnyxLinks.host` alone.
- **"Onyx is a single-user personal training log"** must never appear in the metadata or the review notes — Apple rejects apps positioned for one person (4.2/4.3). The copy in §2 and §4 is written accordingly, and the old single-user framing has been removed from both.

Verified clean at the same pass, with values: bundle ids and the extension's
parentage, matching versions across both targets, the App Group in all four
places, entitlements (nothing unused, nothing missing), both `PrivacyInfo.xcprivacy`
manifests, the HealthKit usage strings, no iCloud health data, no tracking SDK,
no placeholder or dead UI, the icon's alpha channel, and `Secrets.xcconfig`
untracked.

### Re-run at W-GATE (2026-09-08)

Rows 1–5 above are **all still open.** Track U's wave U7 — the wave that was to
close 1, 2 and 3 — never shipped: there is no `src/app/privacy` and no
`src/app/support` route, so `OnyxLinks.privacyPolicy` still points at a 404, and
`OnyxLinks` still has no `support` member. E6 landed the halves it owned (the
`delete_my_account` RPC, `src/app/delete-account`, `SignUpView`, the AASA file at
`public/.well-known/apple-app-site-association`, and `scripts/seed-demo-account.mjs`
for row 3), so the gap is U7's web pages, the Settings rows and the metadata copy.

Two findings the W-GATE preflight added:

| # | What | Guideline | Where |
|---|---|---|---|
| 6 | **The watch app shipped with no privacy manifest.** The required-reason API check runs per Mach-O binary, and `OnyxWatch.app` uses `UserDefaults` and its own GRDB store. The app and the widget each carry one; the watch did not. **Fixed at W-GATE** — `native/OnyxWatch/Support/PrivacyInfo.xcprivacy`. | 5.1.1 / Privacy Manifest | fixed |
| 7 | **`associated-domains` is PARKED until Gate 0.** A free personal team cannot sign the `webcredentials` entitlement, so it is commented out in `native/project.yml` (see the block above `info:`); `site/.well-known/apple-app-site-association` already names the native App ID, so restoring that one key — and enabling Associated Domains on the App ID in the portal — is the whole change once the paid program is in place. Until then Password AutoFill treats app and site as unrelated, which is not a review blocker. `applinks` stays absent — the app claims no URLs. | — | parked |

Also unresolved and not a code change: `npm audit` reports 11 high and 1 critical,
all transitive through build tooling (`tar` via `@capacitor/cli`, `sharp`, `postcss`,
`browserslist`, `undici`). Verification item 6 of the Phase 3 plan asks for no highs.

---

## 1. Identity

| Field | Value |
|---|---|
| Bundle ID | `app.onyx.health.michael.native` (`native/project.yml:169`) |
| Widget extension | `app.onyx.health.michael.native.widgets` (`native/project.yml:234`) |
| Version (`CFBundleShortVersionString`) | `1.0` |
| Build (`CFBundleVersion`) | `1` |
| Team | `W9UMPV973P` |
| Deployment target | iOS 18.0 |
| Devices | iPhone only, portrait only |
| Primary category | Health & Fitness |
| Secondary category | *(leave empty)* |
| Age rating | 4+ — no user-generated content, no web view of arbitrary URLs, no ads |
| App icon | `native/Onyx/Resources/Assets.xcassets/AppIcon.appiconset` — one 1024 × 1024, no alpha: the black onyx squircle with the broken lavender→indigo ring (§8 of the Phase 2 plan). The same ring `OnyxMark` draws in the app, so the Home Screen and the nav bar show one object. Verified compiled into `Assets.car`. |

The app and the widget extension carry the **same** marketing and build numbers.
App Store Connect rejects an extension whose version differs from its host, and
they are set from one pair of values in `native/project.yml`.

**The Home Screen name is `Onyx`** (`CFBundleDisplayName`, set in
`native/project.yml` for both the app and its widget extension, which reads
`Onyx Activity`). The web-shell app it replaced is gone (W6), so there is
no second icon to tell it apart from.

---

## 2. Metadata template

**Name** (30 chars) — `Onyx`

**Subtitle** (30) — `Train. Fuel. Recover. Repeat.` *(29)*

**Promotional text** (170, editable without a review)

> Your body reports in every morning — sleep, heart, load, fuel. Onyx reads it,
> scores it, and tells you what today is actually for. *(147)*

**Description** (4000)

> Most training apps are a notebook with a timer. Onyx is an instrument.
>
> It logs strength work set by set, reads your activity, heart, sleep,
> body-composition and nutrition data from Apple Health, and turns the two into
> a small number of figures you can act on before you have finished your coffee:
> a readiness score, a training battery, a stress index and an energy balance.
> Not a wall of charts. Four numbers, and the reason behind each one.
>
> BUILT FOR PEOPLE WHO ACTUALLY LIFT
>
> • Live logger — your prescribed sets, double progression, a rest timer that
>   keeps running on the Lock Screen, and RPE only where you want it
> • Progression that reads your last session, not a calendar. Load goes up when
>   every working set hit the ceiling, and not before
> • Personal records detected as they happen, and retracted honestly when a
>   later set supersedes them
> • Apple Watch — start, log and finish a session from your wrist, offline, and
>   it merges cleanly when your phone comes back
>
> THE RECOVERY SIDE, MEASURED
>
> • Readiness from six weeks of your own baselines — HRV, resting heart rate,
>   sleep and training load, never a population average
> • A training battery that drains through the day and recharges with the night
>   you actually had
> • Sleep broken into its stages, with the nights your watch got wrong flagged
>   rather than averaged in
> • Soreness and fatigue by muscle, on a body map that fills in as you log
>
> FUEL THAT FOLLOWS THE PHASE YOU ARE IN
>
> • Targets that move with your block — cut, maintain, build — instead of one
>   fixed number you stopped believing in week three
> • Protein, carbs, fat and water, read from Health or entered in seconds
> • Energy balance across the week, carried properly across the days you forgot
>   to log
>
> AND EVERYTHING BACK TO THE FIRST SESSION
>
> • History week by week, day by day, with nothing summarised away
> • Charts for every metric, over any window
> • Weekly reports in plain text you can read, keep, or paste anywhere
> • Home Screen and Lock Screen widgets for all of it
>
> PRIVACY, PLAINLY
>
> Onyx does not sell your data, does not share it with anyone, and contains no
> advertising or analytics code of any kind. It talks to exactly one server:
> your own private account. You can delete that account, and everything in it,
> from inside the app in two taps.
>
> Apple Health access is optional. Decline it and every screen still works — the
> figures that need a reading you have not shared say so, rather than guessing.

**Keywords** (100, comma-separated, no spaces)

> `gym,workout,lifting,strength,hypertrophy,macros,cutting,recovery,hrv,sleep,readiness,overload`

*(93 characters. `fitness`, `training` and `health` are omitted on purpose —
they are already in the app's name, subtitle and category, and App Store search
indexes those fields; spending keyword characters on them buys nothing.)*

**Support URL** — `https://onyx-health-fitness.netlify.app/support/`
**Marketing URL** — *(optional; leave empty)*
**Privacy Policy URL** — `https://onyx-health-fitness.netlify.app/privacy/`

> **Both pages are static HTML under `site/`** (W6), published by Netlify with no build step. `curl -I` each URL before submitting.

---

## 3. App Privacy answers

Match `PrivacyInfo.xcprivacy` exactly — a questionnaire that disagrees with the
manifest is its own rejection.

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data? | **Yes** |
| Health & Fitness → Health | Collected · **Linked** to identity · not used for tracking · App Functionality |
| Health & Fitness → Fitness | Collected · **Linked** · not tracking · App Functionality |
| Contact Info → Email Address | Collected · **Linked** · not tracking · App Functionality |
| Any other category | **No** |
| Used for tracking? | **No** — `NSPrivacyTracking` is `false`, `NSPrivacyTrackingDomains` is empty |
| Third-party SDKs | GRDB, supabase-swift and swift-crypto, all bundled with their own manifests; none collects |

**Required-reason APIs declared** (app and extension both):

| API category | Reason | Why |
|---|---|---|
| `UserDefaults` | `CA92.1` | App Group suite, read by the app and the timeline provider; never leaves the device |
| `FileTimestamp` | `C617.1` | GRDB stats `onyx.sqlite` and its `-wal` when it opens them |
| `DiskSpace` | `E174.1` | SQLite checks free space before a write |

The extension carries its **own** manifest: the required-reason check runs per
Mach-O binary at upload, so the app's does not cover `OnyxWidgets.appex`.

**The HealthKit scope behind "Health" and "Fitness"** (re-audited in 7.15.0,
App Store W6 — the four manifests' comments say the same):

| | Phone | Watch |
|---|---|---|
| **Reads** | 45 types — `HealthCatalogue.readTypes`: 41 daily metrics (activity, heart, body, sleep-window HRV, 24 dietary incl. 18 micronutrients), sleep analysis, workouts, resting energy (per cardio bout), 1-minute heart-rate recovery (per session). `HealthScopeTests` pins every one to the screen that draws it | workouts, heart rate, active energy |
| **Writes** | the workout type and active energy (`WorkoutWriter`, a session no watch recorded) | the workout type; the live builder attaches heart rate and energy |
| **Leaves the device** | the daily log, sleep, body composition, nutrition and its micros, imported cardio — all **Health** or **Fitness** | the training log, via the phone |
| **Never leaves the device** | off-wrist minutes (`wrist_coverage`), 1-minute recovery, the session heart-rate series | — |

No category changed in 7.15.0. Sixteen types had been requested and never
read since the web era: nine dietary micros are now read and drawn (Health,
already declared), the other seven left the request (flights, move time,
walking heart rate, height, UV, mono- and polyunsaturated fat). The two new
derived readings — off-wrist minutes and 1-minute recovery — stay on the
device, so they are not "collected". Background delivery
is **not** requested — the entitlement is a commented Gate-0 block in
`project.yml`, and Health is read on foreground only.

---

## 4. Review notes

Paste into **App Review Information → Notes**:

> Onyx is a training, nutrition and recovery app. Anyone can create an account
> from the first screen ("Create an account"), and any account can be deleted
> from inside the app at Settings → Delete account.
>
> A pre-seeded demo account is provided so you do not have to wait for a
> confirmation email or log a workout to see the app with real content:
>
>   Email: appreview@onyx.fitness
>   Password: (see the App Review password field)
>
> It carries several months of training, nutrition, sleep and body data, so
> every tab, chart and widget has content on first launch.
>
> Apple Health: the app asks to **read** Health data, and to **write** the
> strength workouts logged on the phone, on first foreground — and works
> fully without it — the demo account's data is already on the server, so you
> can decline the Health prompt and still review every screen. Health data is
> used only to compute the readiness, recovery and energy-balance figures shown
> in the app; it is never sold, shared or used for advertising.
>
> Home Screen widgets: add any Onyx widget from the widget gallery. They read
> the same local database the app writes and make no network requests.

> ⚠️ **The password is deliberately NOT written in this file.** `origin` is a
> **public** GitHub repository, the Supabase project URL and anon key ship in
> the app, and the demo account is a real account on the production auth
> endpoint — so a literal here completes a working credential pair for anyone
> who reads the repo.
>
> The account already exists; set or reset its password in the Supabase
> dashboard (Authentication → Users → `appreview@onyx.fitness`). If it ever has
> to be recreated: sign up in the app with that address and log a week of
> sessions and meals on the phone. The web-era seeder (`scripts/seed-demo-account.mjs`)
> was removed in 3.0.0 because it imported the deleted web catalogue; it is in
> git history before the sunset commit if a scripted reseed is ever wanted.
>
> Paste the password straight into **App Review Information → Password**
> in App Store Connect. That field is not public and is the correct place for it.
> Rotate it after the review is approved.

`Sign in required: Yes`. The first screen is a login wall, so credentials are a
**hard** requirement under 2.1 — but as of E6 it is no longer the *only* way in:
a reviewer can also create their own account from that screen, which is what
2.1 actually asks for. The demo account is the faster path, not the only one.

---

## 5. Export compliance

`ITSAppUsesNonExemptEncryption` is `false` in the binary, so App Store Connect
does not ask and TestFlight never stalls in *Missing Compliance*. The answer is
correct: the only cryptography is HTTPS to Supabase and the system Keychain,
both exempt under Category 5 Part 2.

---

## 6. Screenshots

```bash
scripts/store-shots.sh
```

Writes `native/__store__/6.9in/` (1320 × 2868, **required**) and
`native/__store__/6.3in/` (1206 × 2622) — six screens each: Today, Workout,
Nutrition, Pulse, Body trends, History, in that order. That is the app's own tab
order, then the two screens that show it has history. Deterministic: the
`--onyx-screen` harness seeds in-memory data, so no account and no network are
involved and the same command produces the same PNGs tomorrow.

The output is gitignored. Regenerate, upload, move on.

---

## 7. Preflight checklist

Against `capacitor-apple-review-preflight`'s rule set. Every row answered.

| Rule | Verdict |
|---|---|
| `design/minimum_functionality` | **Pass.** Native SwiftUI, five tabs (Today · Workout · Nutrition · Pulse · Settings), live logging, widgets, an interactive Live Activity. Not a web wrapper — the Capacitor shell is a separate bundle ID and is not what ships. |
| `design/sign_in_with_apple` | **N/A.** No third-party or social login. Email + password to a first-party server only, which does not trigger 4.8. |
| `entitlements/unused_entitlements` | **Pass.** Two entitlements, both used: `com.apple.developer.healthkit` (`HealthSync.requestAuthorization`) and the App Group (the shared GRDB file the widgets read). No `.access`, no `.background-delivery`. |
| `privacy/privacy_manifest` | **Pass.** `PrivacyInfo.xcprivacy` in both bundles; verified present in the Release build, not just in the repo. |
| `privacy/unnecessary_data` | **Pass — since 7.15.0, and not before.** Until App Store W6 the read scope carried sixteen web-era types no code read (flights, height, UV, nine micros…), so this row's old "Pass" was false. The scope is now exactly `HealthCatalogue.readTypes`, and `HealthScopeTests` (in `npm run swift:data`, which `npm run check` does not run) fails if a type is added without naming the screen that draws it. No contacts, no location, no camera, no photos, no ATT. |
| **5.1.1(v) account deletion** | **N/A, and it is the row most likely to be argued.** The guideline binds apps that *support account creation*; this one does not. `SignInView` is sign-in only — email and password against an account provisioned server-side — with no sign-up field, no OAuth, and no path in the binary that creates a user. §4's review notes say so in the first sentence, which is where a reviewer looks. **If that is ever challenged, or the moment a sign-up screen appears, this becomes a hard reject** and the fix is a `security definer` RPC that deletes the caller's rows and their `auth.users` row, called from a destructive row under Sign out. Deleting an auth user needs the service-role key, so it cannot be done from the client — it is server DDL, and server DDL in this project is pasted by hand. |
| `metadata/accurate_metadata` | **Open** until §2 is filled in. The description must not promise the Watch app — that is 1.1. |
| `metadata/apple_trademark` | **Pass** as long as §2 says "Apple Health" and "Home Screen", never "iOnyx", "for iPhone" in the name, or an Apple logo in a screenshot. |
| `metadata/china_storefront` | **N/A.** No ICP filing needed; ship to all storefronts or exclude China — either is fine, nothing in the app requires a licence. |
| `metadata/competitor_terms` | **Pass.** No competitor name in the keywords above. Keep it that way — "Hevy" and "Whoop" appear nowhere in shipping copy. |
| `subscription/*` (3 rules) | **N/A.** No IAP, no subscription, no paywall. Nothing in the binary links StoreKit. |

**Re-verified at Wave 2.13:** the whole Phase 2 diff to `native/project.yml` and
both `Info.plist`s is the Onyx rename — **no** new entitlement, background mode,
permission or usage string — so every verdict above still describes the binary.
Both `PrivacyInfo.xcprivacy` files are present (the app's and the extension's;
the required-reason check runs per Mach-O, not per app).

**Security gate** (verified against `Release-iphonesimulator/Onyx.app`):

- The only credential in the bundle is the Supabase **anon** JWT — the role
  claim was decoded and read `anon`. RLS is what protects the data.
- `service_role` appears in no file in the bundle and in no source file.
- The session JWT lives in the Keychain (`KeychainAuthStorage`), never in
  `UserDefaults`.
- `Secrets.xcconfig` is gitignored and untracked.
- **No `UIBackgroundModes` at all** — no `processing`, no `fetch`, nothing to
  register or justify. Health is pulled on foreground; the Live Activity clock
  runs without waking the app.
- ATS is untouched: no `NSAllowsArbitraryLoads`, no exception domains, no
  `http://` URL, and nothing overrides a certificate challenge.
- Every debug affordance is unreachable in Release — the whole of
  `PreviewHarness.swift` and its call site, `ONYX_START_TAB`, `ONYX_NO_HEALTH`,
  `ONYX_SESSION_FILE` and the SQL tracer are all inside `#if DEBUG` (the tracer
  is `#if DEBUG && targetEnvironment(simulator)` since W13 — it prints bound
  values, and a free-team device build IS a Debug build), and only
  the Debug configuration defines `DEBUG`. As of Wave 2.13 every `#Preview` is
  too: two in `OnyxUI` were not, and `#Preview` expands in **all**
  configurations, so they were compiling into the shipping framework.
- The widget extension makes **no** network request of any kind; it opens the
  App Group database read-only.

> **Not part of the binary, but found by the same review:** the Next.js web app
> that shares this Supabase project was serving the owner's health record to
> unauthenticated callers — the API routes authorised on an Origin header and
> queried with the service-role key. Fixed at Wave 2.13 (JWT-only, guard
> deleted, pinned by `src/tests/api-auth.test.ts`). The **service-role key must
> still be rotated by hand**; it was reachable while the hole was open.

**Performance gate:**

- Launch path audited: `OnyxApp` draws a `ProgressView` and does the
  database open and Keychain read inside a `.task`; `AppEnvironment.start()` is
  async; the Health pull is a detached task on foreground, never on launch. No
  synchronous network and no blocking work before the first frame.
- The **< 1 s cold-launch number itself is not measured yet.** It needs
  Instruments against a device build, which needs the paid Developer Program —
  Gate 0, still open. A simulator figure would be a Mac CPU running unthinned
  binaries and would not mean anything.

---

## 8. What is actually blocking submission

1. **Gate 0 — the Apple Developer Program.** A free personal team cannot sign
   the App Group entitlement, cannot upload to App Store Connect, and cannot
   run Instruments on a device. Nothing below moves until this is bought.
2. **The privacy-policy page.** URL is wired into the app and the metadata; the
   page has to exist.
3. **The demo account.** Create it, seed it, put the credentials in §4.
4. **Rotate the credentials that no commit can touch** — the Supabase
   `service_role` key and account password, the dead Anthropic and Notion
   tokens. (`widget_tokens` was dropped in W1.) None is in
   git; all are live at the provider. Tracked in the `auth-credentials-rotation`
   memory.
5. §2 filled in, §6 run, §3 typed into the questionnaire, archive, upload.

Everything else that Wave 8 owns is done and was verified against a Release
build: the privacy manifests, the export-compliance key, the version pair, the
app icon, the screenshot loop, the security gate — and a Release-configuration
build that compiles at all, which before this wave it did not.
