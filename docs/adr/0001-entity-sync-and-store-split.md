# ADR 0001: Entity sync and splitting the store

- **Status:** Proposed
- **Date:** 2026-10-12
- **Deciders:** the owner
- **Supersedes:** the snapshot sync in `MealShuffler/Services/CloudHouseholdSync.swift` once
  phase 5 below ships
- **Related:** [ARCHITECTURE.md](../ARCHITECTURE.md), [ICLOUD_SHARING.md](../ICLOUD_SHARING.md),
  [ROADMAP.md](../ROADMAP.md#per-entity-icloud-sync-cksyncengine)

## Context

### State is one blob, saved whole

`AppStateSnapshot` (`Services/AppStateRepository.swift`) holds 26 top-level fields: onboarding
flag, `memberPreferences`, `rules`, `plan`, `nextWeekPlan`, `dayContexts`, `nextWeekContexts`,
`archivedWeeks` (up to 26), `checkedGroceryIDs`, `stockedGroceryIDs`, `manualGroceryItems`,
`pantryStaples`, `aisleOrder`, `customMeals` (up to 2,000, with ingredients and instructions),
`favoriteMealIDs`, `feedbackEvents` (up to 2,000), `householdSize`, `household`, six reminder
settings, and `tools` (`HouseholdTools`: shopping period and sessions, cooking progress,
freezer, collections, dinner hour, wishes, `sharesIngredients`).

Every persisted property on `AppStore` calls `save()` from its `didSet`
(`Store/AppStore.swift` lines 13–68). `save()` debounces 400 ms and then
`writeStateInBackground()` encodes the entire snapshot and `FileStateRepository.saveOrThrow`
rewrites `<App Group>/State/state.json`, after first re-reading and re-decoding the previous
file to keep it as `state.json.backup`. Ticking one grocery item rewrites the meal library.
The widget and share extension decode the same whole file to answer "what is for dinner".

### The sync ships that blob

`CloudHouseholdSync` puts the whole snapshot in one `Household` record as a `CKAsset` (field
`state`) in the custom zone `MealShufflerHousehold`, plus a `RecipeImage` record per photo
parented to the root, and shares the root with a `CKShare`. It polls every 30 seconds while
the app is active (`App/MealShufflerApp.swift`). Conflict detection is a three-way compare of
the whole household — `local`, `remote` and an `icloud-baseline.json` — via
`CloudHouseholdSync.equivalent`, which compares 18 fields at once. If both sides changed
anything, the user must choose a whole household version (`resolve(useRemote:)`).

Consequences, all visible in the code:

1. **Two people editing the same week always conflict.** One ticks milk in the shop while
   the other swaps Thursday: `equivalent` is false on both sides and neither is the baseline,
   so both get "choose which household version to keep". Field-level intent is lost.
2. **Monday rollover is a guaranteed conflict.** `rollOverIfNeeded` (`AppStore.swift` ~L234)
   runs on every device — on launch, on `.active` and in `BackgroundRefresh.handle`. With no
   prepared next week it calls `shuffleAll()`, which draws from `SystemRandomSource`. Every
   device archives the old week and generates a *different* random new week. Whichever syncs
   second sees a remote that differs from both baseline and local.
3. **Even a seeded rollover would not agree today.** The generator's inputs differ per device:
   `contexts(forWeek:)` folds in `busyDays(inWeekStarting:)` from the device's own calendar
   (`CalendarBusyEvenings`); `Weekday.ordered()` follows the device's `firstWeekday`, which
   changes the order the generator fills days; `WeekAnchor.startOfWeek` uses the device's
   calendar, so a Sunday-first phone and a Monday-first phone disagree on when the week
   starts; past days are pinned relative to `Date.now`; and the built-in catalog
   (`SampleMeals`) differs between app versions.
4. **Deletes are not representable everywhere.** Custom meals have tombstones (`deletedAt`),
   but `consumeFreezerBatch` removes an empty batch outright, `removeManualGroceryItems`,
   `deleteRules` and `removeHouseholdMembers` hard-delete, and set-valued fields
   (`checkedGroceryIDs`, `favoriteMealIDs`, `pantryStaples`, `collections`) cannot tell
   "removed here" from "never added there".
5. **Freezer portions are a counter.** Two phones consuming 2 and 1 portions of a 4-portion
   batch must end at 1; any last-writer-wins on `portions` ends at 2 or 3.

That is why `FeatureFlags.householdSyncEnabled` is `false` and why the roadmap calls for
per-entity `CKSyncEngine` sync. Because the flag has been off in every shipped build, **no
production CloudKit data exists in the old format.** The new design does not need to migrate
anything out of iCloud.

### The store owns everything

`AppStore.swift` is 1,951 lines (plus 178 in `AppStore+Family.swift`) and owns planning
(shuffle, regenerate, locks, swaps, next week, rollover, conflicts), the library (custom
meals, favorites, photos, imports, tombstones), rules, groceries (derived list, checks,
stocked, manual items, staples, aisle order, shopping periods), reminders and background
surfaces (`refreshBackgroundSurfaces`, `publishWidgetSummary`, `drainWidgetActions`),
undo (`PlanCheckpoint`), household and family (members, size, wishes, cook assignment),
freezer, history and statistics, and persistence (`makeSnapshot` / `restoreSnapshot`). Any
sync design that keeps this shape has to rebuild sync logic inside every `didSet`.

What is already in our favour:

- `MealFeedbackEvent` is immutable and identified — the comment in `Models/MealFeedback.swift`
  already says merging is a union by id.
- `Meal` carries `updatedAt`, `updatedBy` (`DeviceIdentity.current`) and `deletedAt`.
- `MealPlanGenerator` takes an injected `RandomSource`, and `SeededRandomSource` is a
  documented SplitMix64 ("same seed, same sequence, on every platform").
- Every read of a blob goes through `AppStateSnapshot.decoding` and `StateMigrations`, so a
  one-time export of the blob into entities has a single, tested entry point.
- `DeviceBackupDocument.retainRecovery` already exists for "save a recovery copy first".
- CloudKit sharing setup (container `iCloud.no.mealshuffler`, entitlements,
  `CKSharingSupported`) is in place; iOS 17 is the deployment target, which is what
  `CKSyncEngine` requires.

## Decision

Replace the snapshot with **entities that each carry their own identity and modification
metadata**, persisted locally per entity, synced with **`CKSyncEngine` in one zone-wide shared
record zone**, merged with an **explicit per-entity conflict policy**, with a **single
deterministic week rollover** per household. Split `AppStore` into **domain stores over one
repository protocol**, keeping `AppStore` as a thin façade while views move over. Ship in the
phases below; sync stays off until every item in "Before turning sync on" is done.

### 1. Entity model

Every synced entity has a stable id and the same metadata:

```swift
struct EntityMeta: Codable, Hashable {
    var createdAt: Date
    var modifiedAt: HLC            // hybrid logical clock: max(wall, last) + counter, + device
    var modifiedBy: UUID           // DeviceIdentity.current
    var deletedAt: Date?           // tombstone; never hard-delete a synced entity
    var fieldClocks: [String: HLC] // last write per field, for field-level merge
}
```

A hybrid logical clock rather than `Date.now`, because phone clocks drift and a household's
phones are not synchronised; an HLC still sorts like time but never goes backwards on one
device and breaks ties by device id, so every device picks the same winner.

| Entity | Id (CloudKit record name) | Fields | Replaces |
|---|---|---|---|
| `Household` | `household` (singleton per zone) | name, dinnerHour, `weekStartsOn`, timeZone id, `sharesIngredients`, aisleOrder | `household.name`, `householdSize`, `tools.dinnerHour`, `aisleOrder` |
| `Member` | `member-<uuid>` | displayName, role, sortIndex | `household.members` |
| `Meal` | `meal-<uuid>` | everything on `Meal` today; ingredients and instructions as one JSON field | `customMeals` (custom meals and built-in overrides) |
| `RecipePhoto` | `photo-<content hash>` | asset | `RecipeImage` records, `photoName` files |
| `Favorite` | `fav-<mealID>` | isOn | `favoriteMealIDs` |
| `Collection` | `col-<uuid>` + `colitem-<colID>-<mealID>` | name / isOn | `tools.collections` (keyed by name today) |
| `Rule` | `rule-<uuid>` | title, isEnabled, strength, constraint (JSON), repeatEveryWeeks, firstWeek, expiresAfter, sortIndex | `rules` |
| `Week` | `week-<yyyy-mm-dd>` | weekStart (local date), generatorVersion, seed, rolledBy, shoppingStart/End | implicit week identity, `tools.shoppingStart/End` |
| `PlanDay` | `day-<yyyy-mm-dd>` | the `PlannedMeal` fields (mealID, kind, servings, portionScale, isLocked, freezerBatchID, freezerConsumed) **and** the `DayPlanContext` fields (diners, extraServings, maximumPrepMinutes, mode, leftoverSourceDay, attendingMemberIDs, cookMemberID, …), plus `origin` (`rollover` / `user`) and, once the week is past, `recipeSnapshot` | `plan`, `nextWeekPlan`, `dayContexts`, `nextWeekContexts`, `archivedWeeks` |
| `ShoppingMark` | `shop-<periodID>-<groceryKey>` | checked, stocked, amountOverride | `checkedGroceryIDs`, `stockedGroceryIDs`, `tools.shoppingSessions` |
| `ManualItem` | `item-<uuid>` | name, quantity, unit, aisle, addedAt, periodID | `manualGroceryItems` |
| `Staple` | `staple-<stapleKey>` | isOn | `pantryStaples` |
| `Preference` | `pref-<memberID>-<mealID>` | value | `memberPreferences` |
| `Feedback` | `fb-<uuid>` | the `MealFeedbackEvent` fields | `feedbackEvents` |
| `FreezerBatch` | `frz-<uuid>` | recipe snapshot, initialPortions, frozenOn, label | `tools.freezer` |
| `FreezerUse` | `frzuse-<uuid>` | batchID, portions, date | `consumeFreezerBatch` decrements |
| `Wish` | `wish-<uuid>` | memberID, mealID, createdAt, resolvedAt | `tools.wishes` |

Design choices worth calling out:

- **Plan days are keyed by local calendar date, not by `(weekStart instant, Weekday)`.** Today
  `PlannedMeal.id` is its `Weekday` and the week is an instant (`WeeklyPlan.startDate`), which
  is why `reanchor(to:)` exists. A date string is the same on every phone in every time zone.
  "This week", "next week" and "the archive" become date ranges over one table, so
  `nextWeekPlan`, the rollover's promote step and `ArchivedWeek` disappear as separate
  structures; a past day stores its `recipeSnapshot` (what `ArchivedWeek.recipeSnapshots` does
  today) when its week closes.
- **The week start is a household setting** (`Household.weekStartsOn`, `timeZone`), set from
  the owner's calendar at migration. Display order can still follow each device's locale; the
  plan's identity and the generator's day order must not.
- **Natural keys where the data has one**: `groceryKey` is already `IngredientUnits.key(name:unit:)`,
  staples are already keyed by `AppStore.stapleKey`, a favorite is a meal id. Two phones that
  add the same thing create the same record, which merges instead of duplicating.
- **Sets become records with an `isOn` flag** (favorites, staples, collection items, shopping
  marks). Removal is `isOn = false` with a newer clock, not absence, so a removal syncs.
- **Counters become logs.** Freezer portions remaining = `initialPortions - Σ FreezerUse`.
  Feedback is already a log.
- **Local-only state is never synced** and moves out of the synced model: reminder settings,
  `tools.cooking` (cooking progress), the undo checkpoint, `pendingCaptures`,
  `hasCompletedOnboarding`, widget summary, CloudKit system fields and engine state. This is
  the list `CloudHouseholdSync.upload` already neutralises by hand.

### 2. Local persistence and the repository

One protocol replaces `AppStateRepository`:

```swift
protocol EntityRepository: Sendable {
    func all<E: SyncedEntity>(_ type: E.Type) -> [E]           // excludes tombstones by default
    func entity<E: SyncedEntity>(_ type: E.Type, id: E.ID) -> E?
    func apply(_ changes: ChangeSet, origin: ChangeOrigin) throws // atomic; .user / .remote / .migration / .rollover
    var changes: AsyncStream<AppliedChanges> { get }             // what changed, and from where
}
```

- **Storage: SQLite in the App Group container** (WAL mode, so the widget and share extension
  can read while the app writes), one table per entity type, one row per entity, fields as
  columns or a JSON column. A user action writes only the rows it touched. GRDB is the
  pragmatic wrapper; raw `sqlite3` works if adding a package is unwanted.
- **Not SwiftData / `NSPersistentCloudKitContainer`.** It would sync, but with record-level
  server-wins resolution we cannot customise, no hook for a deterministic rollover, no way to
  express the freezer log or `isOn` sets with our semantics, and a schema Android and the web
  could not share.
- **Extensions read a small read model**, not the store: extend `WidgetSummary` into a
  "tonight + next days + shopping preview" file written after each applied change. The widget
  stops decoding 2,000 meals.
- `apply` is the single write funnel the current `save()` is, with the same post-write rule
  ("refresh widgets and reminders after the write, never before"), now driven by `changes`
  instead of by `didSet`.

### 3. Sync transport: `CKSyncEngine`, one shared zone

- **One custom zone per household** (`Household-<householdID>`) in the owner's private
  database, shared with a **zone-wide share** (`CKShare(recordZoneID:)`). No root record or
  parent references needed — every record in the zone is shared, which removes today's
  `parent = rootID` plumbing for photos. Participants see the zone through the shared database.
- **Two `CKSyncEngine` instances** (private database for the owner, shared database for
  participants); only one is active for a given household. The engine handles push
  subscriptions, batching, retries, account changes and change tokens — replacing the 30-second
  poll. Persist `CKSyncEngine.State.Serialization` in the repository.
- **Outgoing:** every `.user`/`.rollover` change enqueues `pendingRecordZoneChanges` for the
  records it touched, and remembers which **fields** are dirty.
- **Incoming:** fetched records go through the merge policy below and are applied with
  `origin: .remote`. Domain stores update from `changes`.
- **Record system fields** (`encodeSystemFields`) are cached per row so each save carries the
  right change tag; a `serverRecordChanged` error returns the server record, which is merged
  and re-sent.
- **New zone name.** The old `MealShufflerHousehold` zone and `Household`/`state` record are
  never read in production (the flag was off). Development data is discarded.
- **Photos** stay content-addressed assets (`photo-<hash>`), uploaded once, never modified.

### 4. Conflict policy per entity

Merging happens when the server record and the local row both changed since the last
known server version.

| Entity | Policy | Why |
|---|---|---|
| `Meal`, `Rule`, `Member`, `Household`, `ManualItem`, `Collection`, `Wish`, `Week` (shopping period) | **Field-level last-writer-wins** by `fieldClocks` (HLC, ties by device id). Tombstone wins over edits older than the delete; an edit newer than the delete resurrects (shown as a notice). | Two people rarely edit the same field of the same recipe at once; when they edit different fields (one renames, one fixes an amount) both survive. |
| `PlanDay` | **Field-level LWW**, with three domain rules: (1) a `user` change beats a `rollover` change regardless of clock; (2) `mealID`, `kind`, `servings`, `freezerBatchID` are **one field group** (a dinner is a unit — never keep A's meal with B's servings); (3) a day marked cooked (feedback exists for that date) is not replaced by a remote shuffle — the remote shuffle loses and the user is told. | Locking, choosing a dinner and adjusting diners are per-day edits; today they make the whole household conflict. |
| `ShoppingMark`, `Favorite`, `Staple`, collection items | **LWW per record on `isOn`/`checked`/`stocked`.** | Two people in the shop tick different items: different records, no conflict. The same item ticked and unticked: latest wins, as a person would expect. |
| `Preference` | **LWW per (member, meal).** | Per-member already; collisions only when two adults edit a child's taste at once. |
| `Feedback`, `FreezerUse` | **Append-only union by id.** Never modified, never conflicting. Pruning (feedback over 2,000, `AppStore.prunedFeedback`) becomes deterministic by age, applied by every device identically. | Already designed as a log. |
| `FreezerBatch` | Immutable after creation except label (LWW); portions are derived from `FreezerUse`. A negative remainder is shown as "used more than was there" rather than hidden. | Counter semantics without a counter. |
| `RecipePhoto` | Immutable, content-addressed. | Same bytes, same name. |

No whole-household "choose a version" screen survives. The only user-facing conflict left is
"someone replaced a dinner you had already cooked", which is a notice, not a choice.

### 5. Deterministic rollover

The week must turn over **once per household**, and every device must agree on the result
even while offline. Three mechanisms, in order of authority:

1. **A claim record.** Rolling over week `W` means creating `week-<W>` and its seven
   `day-<date>` records **in one atomic batch** (`CKSyncEngine.RecordZoneChangeBatch(…,
   atomicByZone: true)`). Creating a record name that already exists fails with
   `serverRecordChanged`; the losing device discards its own generated days (they have
   `origin: rollover` and no user edits) and adopts the server's. Exactly one device's week
   wins; the others never archive or shuffle twice.
2. **A seeded generator, so the loser rarely flips.** The rollover uses
   `SeededRandomSource(seed: hash(householdID, W))` and only household-shared inputs: rules,
   members, preferences, feedback, library, the household's `weekStartsOn` and a canonical day
   order. It **excludes** the device calendar (busy evenings stay a per-device hint shown on
   the day, applied only when that user shuffles) and pins past days by date, not by `now`.
   With identical inputs and generator version, an offline phone shows the same week it will
   later receive. `Week.generatorVersion` records which generator produced it; a device with an
   older generator never claims a week, it waits for one.
3. **Prepared weeks win.** If `nextWeekPlan` was prepared (today: `planNextWeek()`), those
   `day-<date>` records already exist with `origin: user`, so rollover only archives and
   generates the missing days.

User edits made on an offline device on top of its own rollover are re-applied as ordinary
field changes after it adopts the winning week (they are `origin: user`, so rule (1) above
keeps them).

Alternative considered: **"only the owner rolls over."** Simpler, but the week would not turn
if the owner's phone is off for days, and participants would show a stale week. The claim
record gives the same single-writer outcome without depending on one phone.

### 6. Migration from the blob

1. Bump `AppStateSnapshot.currentVersion` and add a final `StateMigrations` step that gives
   every implicitly identified thing an id (collections by name → uuid; manual items already
   have ids; plan days get dates from `WeeklyPlan.date(for:)`).
2. On first launch of the new version, `EntityImporter` reads `state.json` through
   `AppStateSnapshot.decoding` (so v1–v4 blobs all work), explodes it into entities with
   `origin: .migration`, `modifiedBy: DeviceIdentity.current` and a clock older than any
   future edit, writes them in one transaction, and renames `state.json` to
   `state.v4.json` (kept for two releases as a manual rollback).
3. `Household.weekStartsOn`/`timeZone` come from the device at migration;
   `archivedWeeks` become past `PlanDay`s with their `recipeSnapshots`; the freezer's current
   `portions` becomes `initialPortions` (no history to reconstruct).
4. **Dual write for one release:** after each applied change the app also writes an
   `AppStateSnapshot` built from entities. A downgrade, the old widget code path and
   `DeviceBackupDocument` keep working. Backup files stay `AppStateSnapshot` JSON in both
   directions (export builds one from entities; restore imports one as `.migration` changes),
   so users' existing backup files remain valid.
5. **Joining a household** (accepting a share) with local data: the shared zone's plan days,
   members and household settings win; the local library and rules are **merged in** (union
   by id, dedupe by name), after `DeviceBackupDocument.retainRecovery` as today.

### 7. Splitting `AppStore`

Domain stores, each `@MainActor @Observable`, each reading from and writing to the
`EntityRepository`, each owning one slice of today's file:

| Store | Takes from `AppStore.swift` |
|---|---|
| `PlanningStore` | plan/next week, `shuffleAll`, `regenerate`, `shuffle(day:)`, locks, swaps, `setMeal`, `updateContext`, conflicts, `rollOverIfNeeded`, `explanation(for:)` |
| `LibraryStore` | `customMeals`, `meals`, favorites, collections, photos (`savePhoto`), `saveMeal`, `mergeRecipes`, deletes and tombstones, shared-recipe import |
| `RuleStore` | rules, `addRule`, `impossibility`, toggles, strength, shared-rule import |
| `GroceryStore` | derived list (`groceryItems`), marks, manual items, staples, aisle order, shopping period |
| `HouseholdStore` | household, members, size, preferences, wishes, cook assignment (`AppStore+Family.swift`) |
| `FreezerStore` | batches and uses |
| `HistoryStore` | feedback, `markCooked`/`markSkipped`/`snooze`, `weeksSinceLastPlanned`, year summary |
| `SurfaceCoordinator` | `refreshBackgroundSurfaces`, `publishWidgetSummary`, `drainWidgetActions`, reminders — subscribed to `changes`, not called from `didSet` |
| `UndoStack` | `PlanCheckpoint` becomes a recorded `ChangeSet`; undo applies its inverse **only to records not changed remotely since**, otherwise says what could not be undone |

`AppStore` stays as a façade that forwards to them, so views and `ci/check-store-api.py`
keep working while views move to the stores they need one tab at a time. Cross-store
reads (planning needs rules, library, household, history) go through small read-only
protocols (`PlanningInputs`), which is also exactly the value the seeded rollover hashes.

## Phased plan

| Phase | Work | Ships to users? |
|---|---|---|
| 0 — groundwork | This ADR. Characterisation tests for today's behaviour (rollover, locks surviving shuffle, grocery checks surviving a day shuffle, undo, freezer). Extract `PlanningInputs`; make the generator's day order canonical (not `Weekday.ordered()`); make past-day pinning date-based. | Yes, no visible change |
| 1 — entities, locally | `EntityMeta`, HLC, entity types, SQLite `EntityRepository`, `EntityImporter`, dual write. `AppStore` reads/writes entities behind the façade. Tombstones everywhere; freezer log. | Yes, behind nothing — it is the new storage |
| 2 — split the store | Domain stores, `SurfaceCoordinator`, change-set undo, widget read model. | Yes |
| 3 — deterministic rollover | `Week` claim records (locally they are just rows), seeded rollover, household `weekStartsOn`, calendar excluded from rollover. Simulated two-store tests. | Yes |
| 4 — sync, internal | `CKSyncEngine` adapter, zone-wide share, merge policies, sharing UI rebuilt on `UICloudSharingController` with the new zone. New flag `FeatureFlags.entitySyncEnabled`, on only in internal/TestFlight builds. Schema deployed to Production. Two-account acceptance run. | TestFlight only |
| 5 — sync on | Flip the flag; delete `CloudHouseholdSync`, `icloud-baseline.json`, `householdSyncEnabled`, the 30-second poll; local notification when a partner changes tonight's dinner. Stop the dual write one release later. | Yes |

### Before turning sync on (phase 5 gate)

- [ ] Every synced entity has a stable id, `EntityMeta` and tombstones; no synced hard delete
      remains (grep for `removeAll`, `remove(at:)` and `removeValue(forKey:)` on synced collections).
- [ ] Rollover produces one week per household in the simulation tests below, across time
      zones, Sunday-/Monday-first locales, an offline device and an older app version.
- [ ] Merge policies have property tests (convergence, idempotence, commutativity).
- [ ] The two-account run in [ICLOUD_SHARING.md](../ICLOUD_SHARING.md) is rewritten for
      per-entity behaviour and passed on two physical iPhones, development then production.
- [ ] Production CloudKit schema deployed (record types, `modifiedAt` indexes if queried).
- [ ] Privacy policy and App Store label reviewed: the data is still in the user's iCloud and
      not collected by the developer, so no label change is expected, but the policy must say
      what household members can see.
- [ ] A recovery package is written before joining a household and before any remote change
      replaces a cooked day.
- [ ] Rollback plan: turning the flag off leaves local entities intact and the app fully
      usable offline.

## Testing strategy

- **Merge unit tests** per entity, plus property tests: for random edit sequences on two
  replicas, applying remote changes in any order converges to the same state; re-applying a
  change is a no-op; a newer user edit is never lost to an older or a `rollover` change. Use
  `SeededRandomSource` so failures replay.
- **Sync simulation without CloudKit.** A fake zone that implements change tags and
  `serverRecordChanged` exactly, and N in-process devices (each a repository + domain stores)
  driven by a seeded scheduler: edit, go offline, cross midnight Monday, reconnect. Assert
  convergence, one week per household, no duplicate archive, freezer remainder correct. This
  is where today's two failure modes (same-week edits, Monday rollover) become regression
  tests.
- **Rollover determinism tests**: same `PlanningInputs` + seed → identical days, across
  `TimeZone`s and `Calendar.firstWeekday` values; calendar busy days do not change rollover.
- **Migration tests**: v1–v4 blob fixtures (`PersistenceMigrationTests`, `StateStorageTests`,
  `docs/history/review-2026-09-29/fixtures.json`) → entities → `AppStateSnapshot` round-trip is
  equivalent (reuse the field list in `CloudHouseholdSync.equivalent`). Backup files from 0.6.x
  restore.
- **Performance**: 2,000 meals, 26 archived weeks, 2,000 feedback events — one tick writes one
  row; widget read model under a few KB.
- **Device acceptance**: the rewritten two-account run, including "both people tick groceries
  in the shop with phones offline, then reconnect — no prompt, union of ticks".
- CI: all of the above are XCTest and run in `ios-validation.yml`; merge rules also get JSON
  test vectors (see below).

## What Android and the web would need

- **CloudKit is Apple-only.** CloudKit JS can reach a user's iCloud data from a browser with
  an Apple ID sign-in, but there is no supported Android SDK. A household with an Android
  member therefore needs **our own sync backend**, which is the decision this app has avoided:
  accounts (Sign in with Apple / Google), a household invitation flow, and a privacy policy
  and App Store label that say the developer stores household data.
- **What this ADR makes portable:** the entity model, record names, `EntityMeta`/HLC and
  merge policies are platform-neutral by design. Write them down as a versioned contract
  (`docs/sync-schema.md` + JSON Schema) with **shared JSON test vectors** for every merge rule,
  run by the iOS tests now and by Kotlin/TypeScript tests later.
- **A backend that fits:** the existing Cloudflare Worker plus one Durable Object per household
  (strongly consistent, single-threaded per household) storing the same records in its SQLite,
  with a pull/push-changes API mirroring `CKSyncEngine`'s shape. The Durable Object is also the
  natural **single roller** of the week, which removes the claim race entirely for that
  transport.
- **Generator portability:** `SeededRandomSource` is specified (SplitMix64), but the generator
  uses floating-point softmax and `exp`, whose last bits can differ between platforms' math
  libraries. Cross-platform agreement must come from one roller (the claim record or the
  Durable Object), not from every client computing the same week. The built-in catalog
  (`SampleMeals`) and the rule vocabulary should become data files shared by all clients.
- **Sharing links** (`HouseholdShare`, fragment-encoded) already work in any browser via the
  Worker's share pages; the web client can start from those.

## Consequences

- **Positive:** two people can plan and shop at the same time without a "choose a version"
  screen; the week turns over once; every write is small; the widget stops decoding the whole
  household; `AppStore` stops being the place every change has to touch; the model is ready for
  a non-Apple transport.
- **Negative:** a real storage layer (SQLite) and a migration to get right once; more record
  types to deploy and keep in the CloudKit schema; HLC and per-field clocks add bookkeeping to
  every write; field-level LWW can still pick a winner the losing person did not expect (shown
  as a notice where it matters: cooked days, resurrected deletes).
- **Risks:** migration bugs lose real data — mitigated by `state.v4.json`, dual write for a
  release and recovery packages; CloudKit schema drift between Development and Production —
  mitigated by the deploy step in the gate; rollover edge cases at DST and week-start changes —
  mitigated by date-keyed days and the simulation tests.

## Alternatives considered

1. **Keep the snapshot, merge smarter** (three-way merge per field of the blob). Fixes
   same-week edits partly, not rollover; still rewrites and uploads everything; no path to
   Android. Rejected.
2. **`NSPersistentCloudKitContainer` / SwiftData with sharing.** Least code to first sync,
   but server-wins at record level, no deterministic rollover hook, no counter/log semantics,
   and a Core Data model nobody else can share. Rejected.
3. **Own backend now (Worker + Durable Objects) for iOS too.** One transport for all
   platforms, but requires accounts and moves household data to the developer, against the
   current privacy position. Deferred until Android is real; the entity contract keeps it
   possible.
4. **Only the owner's phone rolls over.** Simple, but a week does not turn when that phone is
   off. Replaced by the claim record (section 5).
