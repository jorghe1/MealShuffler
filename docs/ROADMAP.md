# Roadmap

The one status and backlog file. What shipped, what is next, and what is parked. Dated
reviews and implementation reports from September 2026 are kept in [history/](history/) as
records; this file replaces them as the current status.

How the code is organised: [ARCHITECTURE.md](ARCHITECTURE.md). Store listing:
[APP_STORE.md](APP_STORE.md).

---

## Shipped in 0.5.0

0.5.0 is the first release meant for the App Store. It is local-first: no account, no
backend required, recipe service and iCloud sharing off.

### Phase 1 — release blockers (90972f1)

- **Privacy.** Privacy manifests for the app, widget and share extension (App Group reason
  `1C8F.1`, install id declared, all listed as bundle resources). Missing photo-library and
  camera usage strings added in both languages. In-app privacy page,
  [PRIVACY.md](PRIVACY.md), and `/privacy` + `/support` pages on the Worker.
- **Online recipe reading is opt-in.** Off by default, names Anthropic, asks once before it
  is turned on.
- **Worker hardening.** Non-JSON extraction requests rejected (415) before any budget is
  spent; IPv6 rate limits keyed on the /64; random per-request fence around untrusted page
  text; overlong model output clamped after parsing.
- **Rule parser rewrite.** `IngredientVocabulary` knows Norwegian and English food words,
  their forms, what they find on the shelf and their category ("laks" is also fish). Clauses
  split at "men/but" and "og/and"; negated limits, several banned foods, compounds,
  inflections, "-fri" words, "hver 2. fredag", member dislikes and one-letter typos are read.
  Every reading reports what each word did, what was ignored and the alternative readings.
- iCloud household sharing is off behind `FeatureFlags.householdSyncEnabled`.

### Phase 2 — reliability while the app is closed (e969fad)

- One shared store (`AppStoreHost`) for the scene, notification actions and background
  refresh. "Vi lagde den" from the lock screen is recorded on a cold launch.
- `AppRouter`: reminders, the widget and links open the right tab.
- `BGAppRefreshTask` turns the week over and reschedules reminders when the app is not
  opened. An unplanned week gets one plain reminder on its first evening as a fallback.
- Still at most one notification a day, but merged rather than dropped: shopping day carries
  tonight's dinner, the empty-next-week nudge rides on the last day's reminder, and the
  evening before a freezer dinner says to take it out.
- Widget timeline with an entry at every midnight until the week turns.

### Phase 3 — four tabs and redesign (0a0bd35)

- Tabs **Uke · Retter · Handle · Familie**, bound to the router.
- Week: tonight card, seven compact rows (swipe to lock or redraw), rule chips, this/next
  week switch, one "Stokk N dager" button with the rows spinning and landing.
- Husregler: what the rules decide as a week strip, the composer that highlights what it
  understood and asks about ambiguous foods, rules grouped by kind with Må/Helst.
- Retter: photo grid, filters, "Lengst siden sist", freezer, five import sources.
- Handle: progress, quick add with aisle guessing, folded bought/at-home items, one ⋯ menu.
- Familie: household, portions, tastes, reminders and sharing; settings behind a gear.
- Design tokens and three button styles in `AppTheme` (see [DESIGN.md](../DESIGN.md)).

## Added in 0.6.0

Built on the same branch and shipped together with 0.5.0's scope as the first App Store
version (marketing version 0.6.0). Everything works on the device alone; nothing here needs a
server. Check each item on an iPhone and an iPad before submitting.

### Phase 4 — the family around the week

- **Who cooks.** Chosen per day in the day sheet; it stays with the day through reshuffles.
  Shown on tonight's card, the day rows, the widget, the kitchen board, and in the dinner and
  prep reminders ("Kari lager", "På tide å begynne å lage mat, Kari").
- **Barnevisning (kids view).** Tonight's dinner in large type, a way to help, the week as
  pictures, thumbs up or down on six dishes (stored as that child's taste), and one wish for
  next week. Leaving it needs the phone's code or Face ID. Wishes appear under Familie, where
  a grown-up puts them on a day of next week or declines them.
- **Kjøkkenmodus (kitchen board).** Seven day columns with a side panel for groceries still
  to buy and the children's wishes. The screen does not go to sleep while it is open. The app
  now runs on iPad (`TARGETED_DEVICE_FAMILY` 1,2, all orientations).
- **Interactive widgets.** Small, medium, large and three lock-screen families. "Vi lagde den"
  works from the widget: the tap goes into an App Group inbox that the app records on its
  next activation, background refresh or notification response. The large widget shows the
  grocery count and first items. A medium widget's "Bytt" opens that day.
- **Cook-timer Live Activity** on the lock screen and in the Dynamic Island, from cook mode.
- **Siri phrases in Norwegian** (`AppShortcuts.strings`).
- **Photos after cooking.** After "Vi lagde den" or leaving cook mode, an optional sheet
  offers the camera or the photo library; the photo then replaces the drawing everywhere.
- **Middagsåret.** Dinners cooked this year, distinct and new dishes, fish and vegetarian
  counts, the top three and the busiest weekday, with a shareable card. From History and
  Familie.

### Phase 5 — planning that knows more

- **Busy evenings from the calendar** (Settings → Planlegging, off by default). An evening
  with an event from two hours before dinner until an hour after gets a time limit (25 min by
  default) when the week is drawn. The limit is never saved into the day.
- **"Bruk opp rømme" / "use up the cream"** makes a preferred rule for this week only
  (`PlanningRule.expiresAfter`).
- **Rules that cannot hold are refused when written**, with the reason: two kinds on one
  evening that no dish is both, a time limit no fitting dish meets, or protein minimums
  that add up to more than the cooked evenings.
- **Tight days.** Husregler lists days the required rules leave two or fewer dinners for.
- **Fewer things to buy** (opt-in): the generator nudges towards dinners that share
  ingredients with the rest of the week.
- **Shuffle feel.** Ticks while the reels roll, a firmer tap as each day lands, an optional
  click sound, and shake to shuffle.
- **Share card.** QR code to the App Store page (once `APP_STORE_URL` is set), "N av N
  husregler holdt ✓", and the week as one line of emoji.
- **Drawn dish illustrations** by dish form, with a household photo taking precedence.

### Engineering

- UI test target with screenshot smoke flows (own scheme, not on the release path).
- Versioned JSON migration step in front of every state decode (`StateMigrations`).
- Recovery packages pruned to the newest three.
- The community store is created only when Explore is opened.
- Strict concurrency checking (`complete`, warnings in Swift 5 mode).
- Dynamic Type: fixed frames on the week rows, onboarding and recipe steps scale.

### Already in place from earlier releases

Natural-language rules, the shuffle reel, the week as a 9:16 image, friend-to-friend sharing
of rules and recipes in the link fragment, the whole shopping list to Bring! (needs the
service), four import paths with on-device parsers, shopping periods, freezer portions,
collections, cook mode, full device backup, and complete Norwegian Bokmål localization.

---

## Before submitting

- [ ] 0.6.0 built by `ios-smoke`/TestFlight and checked on an iPhone and an iPad
      (widgets, Live Activity, kids view exit, kitchen board in landscape, calendar prompt).
- [ ] Set `APP_STORE_URL` in project.yml once the App Store record exists, so the share card
      carries its QR code.
- [ ] Manual test round from [IPHONE_TESTING.md](IPHONE_TESTING.md), including migration
      over an existing install.
- [ ] **Privacy policy and support URLs.** App Review needs both. They are served by the
      Worker at `/privacy` and `/support`, so either deploy the Worker (it can run with
      online reading unused) or host [PRIVACY.md](PRIVACY.md) elsewhere.
- [ ] App Store Connect record filled from [APP_STORE.md](APP_STORE.md); screenshots taken.
- [ ] Privacy nutrition label answered as in APP_STORE.md, matching the manifests.

---

## Next release — network

Everything here needs a server, a second account or a domain, which is why it was kept out
of 0.5.0. Rough order: the first item unblocks most of the rest.

### Deploy the recipe service

**Why.** Import stops guessing: the Worker reads prose, cookbook photos and pages with no
markup. It also hosts share landing pages, the Bring! list and the privacy pages. Written and
tested, never deployed; `RECIPE_SERVICE_BASE_URL` is empty.

**Needs.** A Cloudflare account and an Anthropic API key. Then:

1. `cd server && npm ci`
2. `npx wrangler login`
3. `npx wrangler secret put ANTHROPIC_API_KEY`
4. `npx wrangler deploy` — prints the URL.
5. Set `RECIPE_SERVICE_BASE_URL` in `project.yml`, regenerate the project.
6. Optionally set `APP_STORE_URL` and `SUPPORT_EMAIL` in `wrangler.toml`.
7. Watch the first real import with `npx wrangler tail`.

**Done when** a link from a site without schema.org markup imports with ingredients, and
switching the service off degrades import instead of breaking it.

**Also before EU users:** a data processing agreement with Anthropic, who processes what is
sent.

**Cost.** One `claude-opus-5` call at `effort: "low"` per import, capped by
`DAILY_MODEL_CALL_LIMIT` (200/day), plus Cloudflare's free tier.

### Bring! whole-list check

**Why.** Built in September (`GET /v1/bring/list`, `BringExport.listLink`, confirmation in the
Handle ⋯ menu) but never exercised against Bring's own parser.

**Needs.** The deployed Worker and a phone with Bring! installed. Test a 7-dinner week for
eight people: Bring opens with the items staged and the quantities match. The app must refuse
a list too long for the URL rather than truncate it. The free alternative stays: "Del som
tekst" to Bring's share extension.

### AI fallback for rule parsing

**Why.** The grammar is deterministic and offline, and it should stay first. Some sentences it
will never read ("noe lett etter trening på tirsdager"). A model can turn those into a
`RuleConstraint` that the composer shows back like any other reading.

**Needs.** The deployed Worker and Anthropic key; a new endpoint with the same guards as
extraction (JSON only, rate limits, budget); a fixed output schema of `RuleConstraint`; the
same opt-in as online recipe reading, and a line in PRIVACY.md and the nutrition label
(typed rule text leaves the device). A test set of real sentences in both languages.

### Per-entity iCloud sync (`CKSyncEngine`)

**Why.** Today's `CloudHouseholdSync` moves the whole household as one JSON asset every
30 seconds and resolves conflicts for everything at once — two people ticking groceries get
"choose a version". That is why it is off.

**Needs.** Records per meal, rule, plan day and shopping item on `CKSyncEngine`, with push so
changes arrive without polling; local notifications when a partner changes tonight's dinner or
the list. A two-account acceptance run on two physical iPhones with distinct Apple IDs
([ICLOUD_SHARING.md](ICLOUD_SHARING.md)), then the production schema deployed before
TestFlight. Remove the old snapshot sync once this replaces it.

### App Clip and universal links

**Why.** Share links open a web page or `mealshuffler://`. Universal links open the app
directly, and an App Clip lets someone without the app see and keep a shared recipe or rule
set.

**Needs.** A domain we control (not `workers.dev`), an
`apple-app-site-association` file served from it, Associated Domains entitlements on the app
(and a clip target), and App Clip experience setup in App Store Connect. Share links must keep
the payload in the fragment.

### Worker hardening for real traffic

**Why.** `X-Install-Id` is chosen by the caller, so the per-install limit is a courtesy; the
per-IP limit and daily budget are the real floor. Fine for a small launch, not for a popular
app.

**Needs.** App Attest (DeviceCheck as fallback) on extraction calls; per-install quotas keyed
on attested ids; KV caching of extractions by normalised recipe URL so popular recipes cost one
call; a model evaluation set (pages, photos, pasted text in both languages) run before any
prompt or model change. Logs stay free of content.

### Anonymous cooking statistics

**Why.** "Most cooked dinners in Norway this week" and better built-in defaults.

**Needs.** A decision first: the app currently promises no analytics. Opt-in only, counts of
built-in meal ids per week with no install id, an aggregate-only endpoint, and updates to
PRIVACY.md, the manifests and the nutrition label before it ships.

### Shareable rule packs

**Why.** Rule sharing between friends exists; packs ("Kjøttfri mandag-pakken", "Småbarn") make
a good set easy to start from.

**Needs.** A pack format on top of the existing `SharedRules` link payload; curated packs can
be bundled with no server. Public packs depend on the community work below.

### Public community

**Why.** Recipes from other households, with ratings. The friend-to-friend half already works
without any of this.

**Needs, in this order:** Sign in with Apple, so a post has an author; a backend behind
`CommunityRepository`; moderation before publication (report queue, someone reading it,
takedown); visible attribution for the source; only then flip
`FeatureFlags.communityEnabled`. Do not flip the flag to demo it.

---

## Later

### Prices, if households want them

Removed on 2026-09-09 because none of the built-in meals has a real price; the totals were
four hard-coded guesses. `Meal.estimatedCost` still decodes and `planningCost` still orders
"Noe billigere". To bring it back honestly:

1. Show a price only where a person typed one; built-ins show none unless priced for real.
2. Restore the price field in `RecipeEditorView` (see git history).
3. Show a weekly total only when every cooked dinner that week has a typed price.
4. Reintroduce `RuleConstraint.maximumCostPerWeek` under the same gate; `LenientRule`
   decoding makes adding a case safe.
5. Consider per-portion prices so household size compares fairly.

### Smaller ideas

- Per-field merge for any remaining whole-household conflicts.
- Paid tier for AI features, if the owner decides on one (see
  [APP_STORE.md](APP_STORE.md#business-model)).
