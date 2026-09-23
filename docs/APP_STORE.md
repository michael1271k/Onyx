# ONYX — App Store 1.0

Everything App Store Connect asks for, in the order it asks, and what still
stands between the binary and a first-pass approval.

**Rewritten end to end at App Store sprint W7 (7.16.0, 2026-09-23)** against the
binary and the live project, not against the previous edition of this file.
Line numbers are `native/project.yml` at that commit — the XcodeGen spec is the
source of truth, `native/Onyx.xcodeproj` is generated and never hand-edited.
Live facts carry the date they were read.

---

## 0. Status at a glance

| # | What | Guideline | State |
|---|---|---|---|
| 1 | **Gate 0 — the Apple Developer Program.** A free personal team cannot sign the App Group, `applesignin` or `associated-domains`, cannot upload, and cannot run Instruments on a device. | — | **Open.** A purchase, not a commit. |
| 2 | **Account deletion may be failing live.** The only body git has ever held for `delete_my_account()` (Phase 3 E6) deletes from four tables that were dropped on 2026-09-10; PL/pgSQL fails on the first of them at run time. `docs/sql/w7-delete-my-account.sql` replaces it with a body that reads the table list from the catalog. | 5.1.1(v) | **Closed 2026-09-23.** The founder ran the hardened file; § 4 read `t · t · f · t · f · t · 36 · 0 · 0 · 1`, so the live function is the new body. |
| 3 | **New accounts cannot be created live.** `GET /auth/v1/settings` (2026-09-23) reads `disable_signup: true`. "Create an account" fails, and so will the FIRST Apple or Google sign-in of anyone who is not already a user — which is every reviewer who does not use the demo account. | 2.1 | **Founder setting** (§8 step 3). |
| 4 | **Apple and Google are off in the live project.** The same endpoint lists `email` as the only enabled provider. The app's buttons are written and compile; they cannot succeed until both providers are configured. | 4.8 | **Founder setting, after Gate 0** (§8 steps 4–6). |
| 5 | **Sign in with Apple token revocation on deletion is not built.** Apple asks apps that offer Sign in with Apple to revoke the user's tokens through its REST API when the account is deleted. That needs the team's Sign in with Apple key and a server-side call (an Edge Function) — neither exists before Gate 0. | 5.1.1(v) | **Open — founder decision.** |
| 6 | **The iOS/watchOS 18–26 SQLite risk (W4).** The store did not open on the 26.5 simulator runtimes until W4 unqualified a TEMP-trigger INSERT. Fixed and pinned by a test; **not checked on hardware**, and the minimums are iOS 18 / watchOS 11. | 2.1 | **Verify on a device at Gate 0.** |
| 7 | **Credentials no commit can rotate** — the Supabase `service_role` key and the demo account's password. | — | **Open**, at the provider. |

Closed, and re-verified this wave:

- **Privacy policy and support pages are live.** `curl -I`, 2026-09-23:
  `https://onyx-health-fitness.netlify.app/privacy/` → `HTTP/2 200`;
  `https://onyx-health-fitness.netlify.app/support/` → `HTTP/2 200`. Both are
  static HTML under `site/`, no login in front of them.
- **In-app account deletion ships**: Settings → Delete account → "Delete
  everything" (two taps, the second one naming what it does). The server half
  is item 2.
- **Metadata is written copy** (§2), never `⟨…⟩`.

Two standing rules, not defects:

- The pages live on a Netlify subdomain. Apple accepts it; a custom domain later
  is a change to `OnyxLinks.host` alone (`SettingsTabView.swift`).
- **"Single-user personal log" must never appear in the metadata or the review
  notes** — Apple rejects apps positioned for one person (4.2/4.3).

---

## 1. Identity

| Field | Value |
|---|---|
| iPhone app | `app.onyx.health.michael.native` (`:220`) |
| Home Screen widgets | `app.onyx.health.michael.native.widgets` (`:283`) |
| Watch app | `app.onyx.health.michael.native.watchkitapp` (`:384`) |
| Watch complications | `app.onyx.health.michael.native.watchkitapp.widgets` (`:442`) |
| Version | `package.json` → `"version"` is the one source; `npm run version:sync` writes `MARKETING_VERSION` (`:50`) and the derived `CURRENT_PROJECT_VERSION` (`:51`, `8.0.0` → `80000`). The submission ships whatever it reads at upload — **8.0.0**, the version the App Store sprint closed on. |
| Team | `W9UMPV973P` (`:229`, `:285`, `:387`) |
| Deployment target | iOS 18.0 (`:22`), watchOS 11.0 (`:26`) |
| Devices | iPhone, portrait only (`:163`); Apple Watch. Dark appearance only (`:162`). |
| Primary category | Health & Fitness |
| Secondary category | *(leave empty)* |
| Age rating | 4+ — no user-generated content shared with others, no web view of arbitrary URLs, no ads |
| App icon | `native/Onyx/Resources/Assets.xcassets/AppIcon.appiconset` — one 1024 × 1024, no alpha |

All four targets carry the same version pair; App Store Connect rejects an
extension whose version differs from its host. The Home Screen name is `Onyx`;
the widget extension reads `Onyx Activity`.

---

## 2. Metadata

**Name** (30) — `Onyx`

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
> • Apple Watch — start a session on either device and the other follows; log
>   and finish it from your wrist
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
> • A supplement stack that remembers the dose you took on each day
>
> AND EVERYTHING BACK TO THE FIRST SESSION
>
> • History week by week, day by day, with nothing summarised away
> • Charts for every metric, over any window
> • Weekly reports in plain text you can read, keep, or paste anywhere
> • Home Screen, Lock Screen and Apple Watch widgets
>
> PRIVACY, PLAINLY
>
> Onyx does not sell your data, does not share it with anyone, and contains no
> advertising or analytics code of any kind. It talks to exactly one server:
> your own private account. Sign in with Apple, Google or your email, and delete
> the account and everything in it from inside the app.
>
> Apple Health access is optional. Decline it and every screen still works — the
> figures that need a reading you have not shared say so, rather than guessing.

**Keywords** (100, comma-separated, no spaces)

> `gym,workout,lifting,strength,hypertrophy,macros,cutting,recovery,hrv,sleep,readiness,overload`

*(93 characters. `fitness`, `training` and `health` are already in the name,
subtitle and category, which App Store search indexes.)*

**Support URL** — `https://onyx-health-fitness.netlify.app/support/`
**Marketing URL** — *(leave empty)*
**Privacy Policy URL** — `https://onyx-health-fitness.netlify.app/privacy/`

---

## 3. App Privacy answers

Type these exactly. They match the app's `PrivacyInfo.xcprivacy` and
`site/privacy/`; a questionnaire that disagrees with the manifest is its own
rejection.

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data? | **Yes** |
| Health & Fitness → Health | Collected · **Linked** · not tracking · App Functionality |
| Health & Fitness → Fitness | Collected · **Linked** · not tracking · App Functionality |
| Contact Info → Email Address | Collected · **Linked** · not tracking · App Functionality |
| Identifiers → User ID | Collected · **Linked** · not tracking · App Functionality — **new at W7, and owed before it**: every row is stored against the account's id, and Apple's definition of User ID includes an assigned account id. Apple and Google sign-in add the provider's own account id to the same record. |
| Contact Info → Name | Collected · **Linked** · not tracking · App Functionality — **new at W7**: Google sign-in goes through Supabase, which requests Google's `email profile` scopes and stores the name on the account. Nothing in the app reads it. Apple is asked for email only. |
| Any other category | **No** |
| Used for tracking? | **No** — `NSPrivacyTracking` is `false`, no tracking domains |
| Third-party SDKs | GRDB and supabase-swift (with swift-crypto), bundled with their own manifests; none collects |

**Four manifests**, one per Mach-O — the required-reason check runs per binary,
so the app's does not cover its extensions: `Onyx/Support/`,
`OnyxWidgets/Support/`, `OnyxWatch/Support/`, `OnyxWatchWidgets/`. Declared
required-reason APIs: `UserDefaults` `CA92.1`, `FileTimestamp` `C617.1`,
`DiskSpace` `E174.1`.

**The HealthKit scope behind "Health" and "Fitness"** (re-audited in 7.15.0,
App Store W6 — the four manifests' comments say the same):

| | Phone | Watch |
|---|---|---|
| **Reads** | 45 types — `HealthCatalogue.readTypes`: 41 daily metrics (activity, heart, body, sleep-window HRV, 24 dietary incl. 18 micronutrients), sleep analysis, workouts, resting energy (per cardio bout), 1-minute heart-rate recovery (per session). `HealthScopeTests` pins every one to the screen that draws it | workouts, heart rate, active energy |
| **Writes** | the workout type and active energy (`WorkoutWriter`, a session no watch recorded) | the workout type; the live builder attaches heart rate and energy |
| **Leaves the device** | the daily log, sleep, body composition, nutrition and its micros, imported cardio — all **Health** or **Fitness** | the training log, via the phone |
| **Never leaves the device** | off-wrist minutes (`wrist_coverage`), 1-minute recovery, the session heart-rate series | — |

No Health category changed in 7.15.0. Sixteen types had been requested and
never read since the web era: nine dietary micros are now read and drawn, the
other seven left the request. The two new derived readings — off-wrist minutes
and 1-minute recovery — stay on the device, so they are not "collected".
Background delivery is **not** requested — the entitlement is a commented
Gate-0 block in `project.yml`, and Health is read on foreground only.

---

## 4. App Review Information

**Sign-in required:** Yes. Paste into **Notes**:

> Onyx is a training, nutrition and recovery app. The first screen offers three
> ways in — email and password, Sign in with Apple, and Sign in with Google —
> and any of them creates an account on first use. Any account can be deleted
> from inside the app: Settings → Delete account → Delete everything.
>
> A pre-seeded demo account is provided so you can see the app with real
> content without logging a workout first:
>
>   Email: appreview@onyx.fitness
>   Password: (see the App Review password field)
>
> It carries several months of training, nutrition, sleep and body data, so
> every tab, chart and widget has content on first launch.
>
> Apple Health: the app asks to read Health data, and to write the strength
> workouts logged on the phone, on first use — and works fully without it: the
> demo account's data is on the server, so you can decline the prompt and still
> review every screen. Health data is used only to compute the
> figures shown in the app; it is never sold, shared or used for advertising.
>
> Apple Watch: install Onyx from the Watch app. Starting a session on either
> device opens it on the other.
>
> Widgets: add any Onyx widget from the widget gallery. They read the app's
> local database and make no network requests.

> ⚠️ **The demo password is deliberately NOT in this file.** `origin` is a
> public repository and the Supabase URL and anon key ship in the app, so a
> literal here would complete a working credential pair. Set or reset it in the
> Supabase dashboard (Authentication → Users → `appreview@onyx.fitness`), paste
> it into **App Review Information → Password** (not public), and rotate it
> after approval.

---

## 5. Export compliance

`ITSAppUsesNonExemptEncryption: false` (`:181`), so App Store Connect never
stalls in *Missing Compliance*. Correct: the only cryptography is HTTPS, the
system Keychain, and a SHA-256 of the Sign in with Apple nonce — all exempt
under Category 5 Part 2.

---

## 6. Screenshots

```bash
scripts/store-shots.sh
```

Writes `native/__store__/6.9in/` (1320 × 2868, **required**) and
`native/__store__/6.3in/` — Today, Workout, Nutrition, Pulse, Body trends,
History. Deterministic: the `--onyx-screen` harness seeds in-memory data, so no
account and no network. **Its default devices (iPhone 17 Pro Max, 17 Pro) are
not installed on this machine** — W8 fixes the script or creates the devices.
The output is gitignored.

---

## 7. Preflight

| Rule | Verdict |
|---|---|
| `design/minimum_functionality` | **Pass.** Native SwiftUI on iPhone and Apple Watch, live logging on both, widgets, an interactive Live Activity. |
| `design/sign_in_with_apple` (4.8) | **In scope, written, NOT verified on a device.** Google sign-in makes Sign in with Apple mandatory, and both ship together (`SignInView`): Apple first, the same height as Google, both scaling together with Dynamic Type, beside the email form that stays. Apple → `ASAuthorizationAppleIDCredential.identityToken` + a SHA-256 nonce → `supabase.auth.signInWithIdToken`. Google → Supabase's OAuth page in an `ASWebAuthenticationSession` (PKCE), returning to `onyx://auth-callback` (the `onyx` scheme at `:212`). **The `applesignin` entitlement is PARKED** (`:118–130`): until it is uncommented at Gate 0 the Apple button fails with AuthorizationError 1000. **Never upload a build with the button and without the entitlement** — a sign-in button that always fails is a 2.1 rejection. |
| `entitlements/unused_entitlements` | **Pass.** App: App Group (`:104`), HealthKit (`:117`). Widgets: App Group. Watch: HealthKit (`:342`), App Group (`:351`). Complications: App Group. Parked, all as comments: `applesignin` (`:129`), `healthkit.background-delivery` (`:141`), `associated-domains` (`:142–150`). |
| Background modes | **Pass.** iPhone: none. Watch: `WKBackgroundModes: [workout-processing]` (`:367`) — used by the `HKWorkoutSession` that keeps a live session frontmost (W4). |
| `privacy/privacy_manifest` | **Pass.** Four manifests (§3), `NSPrivacyCollectedDataTypeName` and `…UserID` added at W7. |
| `privacy/unnecessary_data` | **Pass — since 7.15.0, and not before.** Until App Store W6 the read scope carried sixteen web-era types no code read, so the old "Pass" was false. The scope is now exactly `HealthCatalogue.readTypes`, and `HealthScopeTests` (in `npm run swift:data`, which `npm run check` does not run) fails if a type is added without naming the screen that draws it. W7's additions — Name and User ID — are declared (§3). No contacts, no location, no camera, no photos, no ATT. |
| **5.1.1(v) account deletion** | **Pass in the binary; founder gate on the server.** It was recorded here as N/A until this wave; that stopped being true when E6 opened sign-up. The row is in the app (Settings → Delete account, two taps, the second one naming "Delete everything"; the RPC, then sign-out, which erases the device). The function is now in the repo — `docs/sql/w7-delete-my-account.sql`, proved on a local PostgreSQL 17 cluster shaped like live (36 `user_id` tables cleared plus `auth.users`, the other user untouched, `anon` and a null `auth.uid()` refused, a held row rolls the whole call back). **Until the founder pastes it, the live body is unknown and possibly the broken E6 one** (§0 item 2). Sign in with Apple token revocation: §0 item 5. |
| 4.8 login services | **Pass as written.** Apple is offered wherever Google is, and asks for email only (with Apple's private relay available). |
| `metadata/accurate_metadata` | **Pass.** §2 describes what ships, Watch app included. |
| `metadata/apple_trademark` | **Pass** — "Apple Health", "Apple Watch", "Sign in with Apple" as Apple writes them; no Apple logo in a screenshot. |
| `metadata/competitor_terms` | **Pass.** "Hevy" and "Whoop" appear nowhere in shipping copy or keywords. |
| `metadata/china_storefront` | **N/A.** No licence needed. |
| `subscription/*` (3 rules) | **N/A — Onyx ships free** (founder decision 1). No IAP, no paywall, nothing links StoreKit. In-app purchase lands in 1.1 against a live App ID. |
| 1.4.1 medical | **Pass.** Settings → About's footer: "not a medical device… talk to a doctor before making a health decision". Unchanged by W7's Settings redesign, on purpose. |

**Security gate** (unchanged by W7, re-read against the source):

- The only credential in the bundle is the Supabase **anon** key; RLS protects
  the data. `service_role` appears in no source file.
- The session lives in the Keychain (`KeychainAuthStorage`), never in
  `UserDefaults`. The Google PKCE verifier is kept by the same storage.
- `Secrets.xcconfig` is gitignored and untracked.
- ATS is untouched: no arbitrary loads, no exception domains, no `http://`.
- Every debug affordance — `PreviewHarness`, the SQL tracer, the `ONYX_*`
  launch switches — is inside `#if DEBUG`.
- The widget extensions make no network request; they open the App Group
  database read-only.

**Performance gate:** launch does its database open and Keychain read in a
`.task` behind a `ProgressView`; the Health pull is on foreground, never on
launch. The < 1 s cold-launch number needs Instruments on a device — Gate 0.

---

## 8. The founder's checklist, in order

1. **Buy the Apple Developer Program** (Gate 0).
2. ~~**Run `docs/sql/w7-delete-my-account.sql`**~~ — **done 2026-09-23**, § 4
   read as expected. Kept for the record: run it in the Supabase SQL editor. The
   editor shows only a run's last result, so first select and run § 1a–§ 1d
   and § 2 one at a time (read-only): 36 tables, zero missed references,
   `uuid` everywhere, one DELETE trigger (`nutrition_entries.trg_sync_daily_macros`,
   which the function's repeat pass handles), and write down § 2's
   `names_dropped_table` (true = deletion was broken until now). Then run the
   whole file; its last result is § 4, one row that must read
   `t · t · f · t · f · t · 36 · 0 · 0 · 1`.
3. **Supabase → Authentication → Sign In / Providers → allow new users to sign
   up.** Live reads `disable_signup: true` (2026-09-23). Email confirmation is
   off live (`mailer_autoconfirm: true`), which `AppEnvironment.signUp`'s
   comment says the opposite of — decide which you want; the code handles both.
4. **Developer portal:** register the App IDs in §1; enable App Groups
   (`group.app.onyx.health`), HealthKit, **Sign In with Apple** and Associated
   Domains on the iPhone app. Then in `native/project.yml` uncomment
   `com.apple.developer.applesignin` (`:129–130`), restore
   `com.apple.developer.associated-domains: [webcredentials:onyx-health-fitness.netlify.app]`
   where its block says (`:142`), and run `cd native && xcodegen generate`.
5. **Supabase → Providers → Apple:** enable it; add
   `app.onyx.health.michael.native` to *Client IDs* (the native identity-token
   flow needs no secret).
6. **Google Cloud → Credentials:** create an OAuth client (type *Web
   application*) with Supabase's callback URL
   (`https://<project>.supabase.co/auth/v1/callback`) as its redirect; put its
   id and secret into **Supabase → Providers → Google**. Then **Supabase →
   Authentication → URL Configuration → Redirect URLs:** add
   `onyx://auth-callback`. Without that entry Google returns to the Site URL
   and the app never hears back.
7. **On a device:** sign in with Apple, sign in with Google, then delete an
   account made with each and confirm it is gone from Authentication → Users.
8. **Decide Sign in with Apple token revocation** (§0 item 5).
9. **Rotate** the `service_role` key and the demo password.
10. Run §6, type §3 into the questionnaire, paste §4, archive, upload.
