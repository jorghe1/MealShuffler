# Architecture

How Meal Shuffler is put together, as of 0.6.0. Written against the code on
`claude/phase-1-3`; when this file and the code disagree, the code wins and this file is out of
date. Product behaviour is in [README.md](../README.md), the design system in
[DESIGN.md](../DESIGN.md), status and backlog in [ROADMAP.md](ROADMAP.md).

## Targets

Defined in [`project.yml`](../project.yml) (XcodeGen). iOS 17+, Swift 5 language mode, no
third-party dependencies. `MARKETING_VERSION` is 0.6.0.

| Target | Type | Bundle id | Compiles |
| --- | --- | --- | --- |
| `MealShuffler` | app | `no.mealshuffler.app` | All of `MealShuffler/`, plus `PrivacyInfo.xcprivacy` as a resource. Embeds both extensions. |
| `MealShufflerWidget` | WidgetKit extension | `no.mealshuffler.app.widget` | `MealShufflerWidget/` plus, from the app: `Models/`, `Data/`, `Localization/`, `Theme/`, `Resources/`, `App/AppGroup.swift`, `Services/AppStateRepository.swift`, `Services/IngredientUnits.swift`, `Services/PlannedDinnerReader.swift`. Own privacy manifest. |
| `MealShufflerShare` | share extension | `no.mealshuffler.app.share` | `MealShufflerShare/` plus the same shared set as the widget, and `Services/RecipeInbox.swift`. Accepts one web URL, text, or one image. Own privacy manifest. |
| `MealShufflerTests` | unit tests | `no.mealshuffler.tests` | `MealShufflerTests/` (about 250 XCTest methods), hosted by the app. Run by the `MealShuffler` scheme. |
| `MealShufflerUITests` | UI tests | `no.mealshuffler.uitests` | `MealShufflerUITests/`: smoke flows through onboarding, the week and every tab, with a screenshot at each main screen. Own scheme `MealShufflerUITests`, kept out of the `MealShuffler` scheme so a flaky UI test never blocks a TestFlight build. Being added in phase 5. |

The extensions compile the model layer and the repository only — never the store, the
generator or the views, which would pull SwiftUI app code, Vision and PhotosUI into an
extension. Anything an extension needs must live in one of the shared paths above. A missing
type in an extension build usually means a file is missing from that target's list in
`project.yml`.

`TARGETED_DEVICE_FAMILY` is `"1"` (iPhone) in `project.yml` today. The iPad kitchen board
needs it widened to `"1,2"`; check `project.yml` before relying on either.

Build settings that reach the app through `Info.plist`:

- `RECIPE_SERVICE_BASE_URL` → `RecipeServiceBaseURL`. Empty by default; the app then never
  calls the Worker.
- `CODE_SIGNING_ALLOWED` → `CloudKitSigningAllowed`. Unsigned builds keep CloudKit off.

Shared identifiers: App Group `group.no.mealshuffler.shared`, CloudKit container
`iCloud.no.mealshuffler`, URL scheme `mealshuffler`, background task
`no.mealshuffler.app.refresh`.

## App layout

```
MealShuffler/
  App/           entry point, AppDelegate, AppRouter + AppStoreHost, BackgroundRefresh,
                 AppGroup, FeatureFlags, DinnerIntents (Siri "What's for dinner")
  Models/        Codable value types: Meal, WeeklyPlan, PlanningRule, Household,
                 HouseholdTools, MealFeedback, Weekday, WeekAnchor, IngredientVocabulary,
                 WidgetSummary, Community
  Data/          SampleMeals (the 40 built-in dinners)
  Services/      planning, reminders, import, sharing, persistence, export (no SwiftUI views,
                 except DeviceBackupView and CloudSharingView which live beside their services)
  Store/         AppStore.swift: the single observable store
  Views/         Planner/ Meals/ Grocery/ Family/ Rules/ Settings/ Onboarding/ History/
                 Community/ Components/, plus RootView
  Theme/         AppTheme (tokens, button styles, modifiers), Haptics
  Localization/  L10n
  Resources/     en.lproj, nb.lproj, Assets.xcassets
```

`RootView` owns the four tabs — `Uke` (`WeekPlanView`), `Retter` (`MealLibraryView`),
`Handle` (`GroceryListView`), `Familie` (`FamilyView`) — each in its own `NavigationStack`,
bound to `AppRouter.tab`. Onboarding, incoming shares, backup and iCloud sheets are presented
from `RootView`.

## State flow

```
View ──calls──▶ AppStore (@MainActor, @Published fields)
                   │ didSet → save()  (400 ms debounce; flushPendingWrites() on background)
                   ▼
               writeState() → AppStateRepository.saveOrThrow(AppStateSnapshot)
                   │                 FileStateRepository: <App Group>/State/state.json
                   ▼ after a successful write, never before
               refreshBackgroundSurfaces()
                   ├─ WidgetRefreshing.reload()        (WidgetKit timelines)
                   └─ ReminderScheduling.reschedule()   (DinnerReminderService)
```

- **One write funnel.** Every persisted field on `AppStore` calls `save()` in its `didSet`.
  `writeState()` encodes one `AppStateSnapshot`, writes it, then refreshes the widget and
  the reminder schedule. Views never schedule notifications or reload widgets themselves;
  `ci/check-store-api.py` checks that every `store.<member>` a view uses exists.
  `refreshBackgroundSurfaces` hashes the plan, next week, custom meals and reminder settings
  and skips the refresh when nothing relevant changed.
- **Persistence.** `FileStateRepository` writes `state.json` atomically with file
  protection, keeps the previous good copy as `state.json.backup`, sets aside unreadable files
  instead of overwriting them, and refuses to overwrite a file with a newer `schemaVersion`.
  Without an App Group container (unsigned runs, missing capability) it falls back to
  `UserDefaultsStateRepository`. Older installs are migrated from defaults once.
- **Forward compatibility.** Entities carry `updatedAt`/`updatedBy`; deleted custom meals stay
  as tombstones; new fields on synthesized-`Codable` types (`DayPlanContext`,
  `HouseholdTools`) must be optional or old saves fail to decode.
- **One store instance.** `AppStoreHost.shared` is the store the scene, notification actions
  and background refresh all use. Two stores would write the same file over each other, and a
  lock-screen action that launches the app without a scene would have nowhere to go.
- **Routing.** `AppRouter.shared` holds the selected tab and whether the Week tab shows next
  week. `open(ReminderDestination)` serves notification taps; `open(URL)` serves widget
  links: `mealshuffler://week` (alias `tonight`), `next-week`, `shop`. `RootView.onOpenURL`
  tries the router first and hands anything else (share links) to
  `store.handleIncomingURL`.
- **Scene lifecycle** (`MealShufflerApp`): on `.active` → `rollOverIfNeeded()`,
  `refreshPendingCaptures()`, `refreshRemindersAndWidget()`; on `.background` →
  `flushPendingWrites()` and `BackgroundRefresh.schedule`.

## Planning engine

- **`MealPlanGenerator`** — pure domain logic, no UI or network. Takes preferred and all
  meals, rules, per-day `DayPlanContext`, a `TasteProfile`, the existing plan (locked days are
  kept) and swap intents. Picks by softmax over a score (temperature 30: repetition is a strong
  deterrent, taste a mild one). Randomness comes from an injected `RandomSource`
  (`SeededRandomSource` in tests). Returns the plan plus explained conflicts.
  `GroceryListBuilder` in the same file aggregates and scales ingredients.
- **Rules** — `PlanningRule` (title, enabled, `RuleStrength` required/preferred,
  `RuleConstraint`, optional every-N-weeks schedule, optional `expiresAfter` for one-week
  rules). `RuleConstraint` cases: `requiredOn`, `excludedOn`, `maximumPerWeek`,
  `minimumPerWeek`, `maximumPrepTime`, `dinnerMode`, `noRepeatWithin`, `requiredEvery`,
  `notOnConsecutiveDays`. `DayScope`: one day, weekdays, weekend, every day, or a set.
- **`MealMatcher`** — what a rule is about: `tag(MealTag)`, `exactMeal(UUID)`,
  `ingredient(String)`, `customTag(String)`, `dislikedBy(memberID:)`. Ingredient matching is
  by text and never verifies allergens.
- **`IngredientVocabulary`** (Models) — the known foods in Norwegian and English with their
  inflected forms, search needles and parent category, so "laks" is a food, finds "salmon" in
  ingredients, and can be offered as "fish". `TextFolding` normalises text for matching.
- **`RuleSentenceParser`** — deterministic, offline grammar for rules typed in words, in
  Bokmål or English regardless of device language. `read(_:)` returns a `Reading`: the
  `Outcome` (`rule`, `incomplete(hint:)`, `notUnderstood`), tokens with roles for highlighting,
  ignored words, the food and its alternatives, and any further foods the sentence named.
  `readAll(_:)` splits a line into clauses ("taco på fredag og fisk på tirsdag", commas,
  "men ikke…" inheriting the food), capped at `batchLimit` (12). `parse`/`parseAll` are the
  outcome-only wrappers. The composer (`Views/Rules/RuleComposer.swift`) shows the reading
  back before anything is saved.

## Reminders

`DinnerReminderService` (behind `ReminderScheduling`) schedules local notifications only. The
store passes it a `ReminderSchedule` value. The logic is static and pure so tests can ask what
a household would receive:

1. `candidates(for:)` — everything the settings ask for: dinner at a fixed hour, prep start
   from the recipe's prep time, thaw the evening before a freezer dinner, a plan-next-week
   nudge on the last day when next week is empty, a new-week reminder on the first evening of
   an unplanned week, and shopping day.
2. `oneADay(_:)` — at most one notification per day. The highest `ReminderKind` leads
   (grocery > prep > dinner > thaw > newWeek > planNextWeek); the nudge becomes a line on it.
3. `content(for:)` — the text, category (for "We cooked this" / "Something else" actions)
   and `ReminderDestination` (`tonight`, `nextWeek`, `shop`) the tap opens.

`AppDelegate` is the notification centre delegate and routes actions through
`AppStoreHost.shared` and `AppRouter.shared`, so they work from a cold launch.

## Background refresh

`BackgroundRefresh` registers a `BGAppRefreshTask` (`no.mealshuffler.app.refresh`, listed
in `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes: fetch`) in
`didFinishLaunching`, and asks for it shortly after the current week ends each time the app
goes to the background. The task rolls the week over, flushes the write, refreshes reminders
and the widget, and schedules the next one. iOS decides when it actually runs, which is why the
reminder service also schedules the plain new-week reminder as a fallback.

## Extensions

- **Widget** (`MealShufflerWidget/DinnerWidget.swift`). Reads the saved plan through
  `PlannedDinnerReader`, which decodes `state.json` with `FileStateRepository` and never
  touches `AppStore`. The timeline has an entry at every midnight until the week turns, then
  reloads. `WidgetSummary` (Models) carries what the widget cannot compute itself — remaining
  shopping items and a preview, and days marked cooked — which the app writes into App Group
  defaults after saving (being wired up in phase 4). `WidgetActionInbox` is where a widget button leaves "cooked" notes for the app to
  record, because the widget must not write `state.json` itself. Widget families, interactive
  buttons and lock-screen widgets are being extended in phases 4–5; see the code for the
  current set.
- **Share extension** (`MealShufflerShare/ShareViewController.swift`). Captures the shared
  URL, text or image into `RecipeInbox` (App Group defaults plus image files under
  `RecipeInbox/`) and returns immediately. It does not extract or save a meal: share
  extensions have tight time and memory limits, and two processes writing the state file lose
  data. The app turns captures into drafts on next open (`refreshPendingCaptures`).
- **Siri / Shortcuts** (`App/DinnerIntents.swift`). `WhatIsForDinnerIntent` answers from
  the plan without opening the app.

## Recipe import

Every path ends in the recipe editor with a draft marked for review.

- **`RecipeCapture`** decides the chain. Online reading is used only when the user turned it on
  (`online-extraction-enabled`, off by default) **and** `RecipeServiceBaseURL` is set.
  - Links: `RecipeImportService` (on-device JSON-LD, microdata fallback) first, then
    `RemoteRecipeExtractor`.
  - Photos and scans (up to 5 pages): remote first, then `RecipeOCRService` (Vision).
  - Pasted text: remote first, then `RecipeTextStructurer`.
- **`ChainedRecipeExtractor`** tries extractors in order, returns the first draft with usable
  ingredients and confirmed servings, otherwise the best partial draft flagged `needsReview`.
- **`RecipeClassifier`** guesses categories so imported meals are visible to rules;
  `IngredientParser`/`IngredientUnits` read quantities and units.
- **The Worker** (`server/`, Cloudflare Worker `mealshuffler-extract`). `POST
  /v1/recipes/extract` calls Anthropic's API with a fixed schema. Guarded by JSON-only
  requests, per-install and per-IP rate limits, a daily model-call budget in a Durable Object
  (`MODEL_BUDGET`, `DAILY_MODEL_CALL_LIMIT`), and SSRF checks on every redirect hop. It stores
  nothing and logs only route, status and duration. It also serves the share landing pages
  (`/s/rules`, `/s/recipes`), `/v1/bring/list` for Bring!, and `/privacy` and `/support`. Not
  deployed yet. Details in [server/README.md](../server/README.md).

## Sharing between households

`HouseholdShare.swift`: house rules, one recipe, a collection, or a week's recipes are encoded
into the link itself — JSON, raw DEFLATE, base64url, prefixed with format version `1.` — in
the URL **fragment**, which browsers never send to a server. Link shape is
`mealshuffler://share/<rules|recipes>#1.<payload>`, or `https://<service>/s/<kind>#1.<payload>`
when the service is configured. The receiver sees `IncomingShareView`, picks what to add, and
nothing overrides their own rules. There is no account and no server state. The week poster
(`WeekShareView`, `WeekPosterContent`) is an image shared through the system share sheet.

## iCloud household sync (off)

`CloudHouseholdSync` shares the whole household as one `CKShare`d record (a JSON asset plus
recipe photos) in a private custom zone, polls every 30 seconds while the app is active, and
asks the user to choose a version on conflict. `FeatureFlags.householdSyncEnabled = false`:
the screens are hidden, the poll does not run and incoming invitations are ignored. It is
replaced by per-entity sync in the next release. Setup and the acceptance test are in
[ICLOUD_SHARING.md](ICLOUD_SHARING.md). `FeatureFlags.communityEnabled` is also false.

## Localization

- English is the development language and the source of every key. Norwegian Bokmål lives in
  `Resources/nb.lproj/Localizable.strings` (and `InfoPlist.strings`).
- SwiftUI literals localize automatically. Everything else — generator explanations, reminder
  text, exports, errors — goes through `L10n.string(key, args...)`, which also picks singular
  forms for a fixed set of `%ld` keys.
- `ci/validate-localizations.py` fails when a key is missing in Norwegian or placeholders
  differ; `ci/check-localized-format.py` checks the argument count at each `L10n.string` call.
- The rule parser reads both languages whatever the device language is.

## CI

- **`ci/` checks** (Python, no Xcode): `validate-localizations.py`,
  `check-localized-format.py`, `check-swift-structure.py` (braces, stale symbols,
  duplicates), `check-store-api.py`, `check-swift-call-labels.py`, and
  `sync-theme-colors.py --check` (launch/accent colour assets match `AppTheme`).
  `ci/bootstrap-ios.sh` runs them all, lints the plists, then runs XcodeGen.
- **GitHub Actions**: `checks.yml` runs the Python checks and plist lint on every push and
  PR, plus the server's `npm ci`, typecheck, tests and bundled share-page test.
  `ios-validation.yml` runs on pull requests to `main`, pushes to `main` and on demand (macOS
  minutes cost money): unsigned simulator build and XCTest, plus an informational
  `ui-smoke` job (`MealShufflerUITests` scheme, allowed to fail) that uploads screenshots.
  Check the workflow file for the current triggers; it is being changed in phase 5.
- **Codemagic** ([CODEMAGIC.md](CODEMAGIC.md), `codemagic.yaml`): `ios-smoke` runs unsigned
  build and tests on every push and PR; `ios-testflight` runs on tags matching `ios-*`,
  signs all three bundles and uploads to TestFlight.

## Repo hygiene

- Branding images (`Branding/**/*.png`, `*.jpg`) go through Git LFS from now on
  (`.gitattributes`). Images already committed stay in normal history; no migration was run.
- Dated reviews and status reports live in [docs/history/](history/). They are records, not
  current status.

## Known limits / next release

Deferred to the next ("network") release. Reasons and prerequisites are in
[ROADMAP.md](ROADMAP.md#next-release--network).

- AI fallback for rule parsing on the Worker, for sentences the grammar cannot read.
- `CKSyncEngine` per-entity iCloud sync with push, and notifications when a partner changes
  the plan. Replaces the whole-household snapshot sync above.
- App Clip and universal links (AASA) so share links open the app or a clip directly.
- Worker hardening for real traffic: App Attest, per-install quotas, KV caching of
  extractions, and a model evaluation set.
- Anonymous cooking statistics.
- Shareable rule packs.
- A public community (needs identity and moderation first).
