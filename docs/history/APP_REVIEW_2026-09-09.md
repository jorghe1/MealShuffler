# Meal Shuffler review — 9 September 2026

The app has a useful dinner-planning foundation, but reliable recipe capture and library maintenance need to become its next major release. Adding more rule options before fixing ingredient fidelity, portion semantics, and constraint enforcement would make the app more capable on paper than in daily use.

This is a source-based product and engineering review of the checked-in app, models, store, import paths, planning engine, shopping flow, persistence, extensions, tests, and roadmap. It is not a device usability test or a production-service audit. No application code was changed. The findings below distinguish observed implementation defects from proposed capabilities.

**Validation performed**

- All five Python repository checks passed: localization, localized formats, Swift structure, store API references, and call labels.
- `npm run check` passed: TypeScript checking and all 12 server tests.
- The repository contains 128 XCTest test methods. They were inspected selectively but could not be executed here: this Windows environment has no Xcode or Swift compiler.
- Server tests cover page-processing helpers, not end-to-end model extraction or the endpoint's request handling. Passing them does not establish photo/text extraction quality.
- The recipe-service URL is blank in the checked-in build configuration. A deployed build could override it; no deployed build was available for verification.

**What is worth keeping**

The local planner, injectable randomness, recipe-extractor interface, shared state repository, manual meal selection, locks, undo, cooking mode, day contexts, unit normalization, and English/Bokmål localization provide a good base. Photo, document scan, URL, pasted text, and share-extension entry points already exist. The rule vocabulary includes daily requirements/exclusions, weekly counts, time limits, recurring dinner modes, repetition windows, periodic inclusion, and consecutive-day avoidance.

Community and household synchronization are correctly hidden while their supporting services are absent. Household synchronization should nevertheless rank above community for a product aimed at families. Keeping the existing SwiftUI app and improving its domain layer is a better next step than a UI rewrite.

**Highest-priority correctness findings**

P1 means address before relying on the affected feature with real households. P2 means a material correctness or usability problem for the next release. These are code-path findings, not claims of executed iOS reproductions.

| Priority | Finding and concrete consequence | Evidence and recommended correction |
|---|---|---|
| P1 | Required constraints can be relaxed. With only fish recipes and a required maximum of zero fish meals, the relaxed candidate pool can still schedule fish. Required repeat windows can also be bypassed without a repeat conflict. | [Fallback selection](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:162), [early return](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:316), and [missing repeat validation](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:671). Never relax required constraints implicitly; return an unfilled day with an actionable explanation. |
| P1 | Ingredient substring matching is presented as a place for allergies, but it is only text search. Different names/languages and compound ingredients are not resolved; unrecognized ingredients can pass. Dietary classification also guesses vegetarian from absence of recognized animal keywords. | [Ingredient matcher](C:/dev/meal_shuffler/MealShuffler/Models/PlanningRule.swift:105), [classifier](C:/dev/meal_shuffler/MealShuffler/Services/RecipeClassifier.swift). Separate ingredient exclusions from reviewed dietary/allergen metadata; represent unknown explicitly and never infer safety from an absent keyword. |
| P1 | Local pasted-text and OCR imports leave servings at 4 and time at 30 minutes, even when the source states otherwise. A recipe for 2 imported as 4 is halved when the household cooks for 2. | [Draft defaults](C:/dev/meal_shuffler/MealShuffler/Services/RecipeImportService.swift:10), [text structurer](C:/dev/meal_shuffler/MealShuffler/Services/RecipeTextStructurer.swift:23), [OCR draft](C:/dev/meal_shuffler/MealShuffler/Services/RecipeImportService.swift:514). Extract yields and timing, retain their evidence, and require a base yield before claiming accurate scaling. |
| P1 | Common ingredient amounts are misread. `1 1/2 cups flour` becomes quantity 1 with `1/2 cups flour` as the name; `500g chicken` becomes quantity 1 with the amount in the name. Missing amounts become 1. | [Ingredient parser](C:/dev/meal_shuffler/MealShuffler/Services/RecipeImportService.swift:567). Add mixed fractions, attached units, ranges, package sizes, bullets, and unknown quantities. Store the original line alongside structured data. |
| P1 | Remote extraction loses information on its way into the editor. The server's structured ingredients are rendered to strings and reparsed; returned aisles are discarded and a null quantity becomes 1. Editing an existing recipe also reparses every ingredient, losing prior aisle corrections and rounding quantities to two decimals. | [Remote draft conversion](C:/dev/meal_shuffler/MealShuffler/Services/RemoteRecipeExtractor.swift:137), [editor initialization](C:/dev/meal_shuffler/MealShuffler/Views/Meals/RecipeEditorView.swift:26). Keep structured ingredients through import/edit/save; reparse only edited rows. |
| P1 | Shared sources are deleted before the user saves the recipe. Successfully extract an inbox photo, then cancel the editor: the inbox item and stored image have already been removed. | [Import handoff](C:/dev/meal_shuffler/MealShuffler/Views/Meals/MealLibraryView.swift:91). Consume the inbox item only after a successful durable save. Persist unfinished drafts. |
| P1 | Editing a planned recipe changes what the household will cook without refreshing rule conflicts. Adding an excluded ingredient can leave a previously clean conflict banner unchanged. | [saveMeal](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:817). Revalidate affected plans, recalculate shopping deltas, and reconcile shopping state after every recipe edit. |
| P1 | Leftovers have no shared portion balance. Two days can each claim the same four extra portions. Changing the source meal through a day shuffle or manual selection does not consistently update dependent leftover entries. | [Portion check](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:97), [source resolution](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:238), [store mutations](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:587). Model dated cooked batches and allocations, and update dependents for every relevant mutation. |
| P1 | Persistence failures are silent. A corrupt snapshot is treated as a fresh install; subsequent writes can replace it. The repository cannot report a failed save to the editor. | [File repository](C:/dev/meal_shuffler/MealShuffler/Services/AppStateRepository.swift:229). Distinguish missing, corrupt, unsupported, and unavailable state; preserve corrupt data, keep a last-good backup, and report failed writes. |
| P2 | Repairing weekly minimums can introduce another violation. It checks day rules but not the day's contextual time limit, adjacency, or repeat window; it may replace a meal needed by a previously repaired minimum. It also chooses a replacement recipe before finding a feasible day. | [Minimum repair](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:521). Validate all constraints against each replacement, or replace the greedy repair with bounded search. Never describe a failed greedy attempt as proof that no solution exists. |
| P2 | Consecutive-day validation collapses gaps. Fish on Monday and Wednesday with Tuesday away is reported as back-to-back because non-cooking days are removed before adjacency checks. The previous week's last day is not considered. | [Consecutive validation](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:656). Compare adjacent calendar dates and define whether leftovers count as eating the same category. |
| P2 | Next-week generation drops conflicts and uses history relative to the current week, excluding the current plan. Deleting a recipe or changing servings does not consistently reconcile next week. | [planNextWeek](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:202), [history window](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:981), [deletion/rescaling](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:841). Make the target date and all affected plans explicit inputs; show next-week conflicts. |
| P2 | Shopping state outlives the amount it represents. Buying 500 g chicken can leave chicken checked when a later change requires 1 kg. Weekly rollover can carry checks, stocked flags, day overrides, and locks into the next week. | [Check reconciliation](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:1053), [rollover](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:177). Track purchased/owned amounts and shopping sessions; distinguish recurring defaults from dated exceptions. |
| P2 | Manual grocery entries are matched using the original unit after the amount has been normalized. Planned `500 g flour` plus manual `1 kg flour` creates two entries with the same resulting ID; normalized manual entries can also lose their remove action. | [Manual aggregation](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:721), [manualItem lookup](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:418). Use the same canonical identity for aggregation and retain contribution IDs for editing/removal. |
| P2 | A preferred dinner-mode rule behaves as required: all enabled mode rules overwrite day contexts regardless of strength. Contradiction checks also ignore strength, preventing reasonable soft alternatives. | [Resolved contexts](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:1008), [addRule](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:753). Give hard and soft rules consistent semantics across every rule type and editing path. |

**Recipe capture: the experience to build**

Use one prominent **Add recipe** entry point with camera/scan, photos, paste, link, and manual options. Allow images and a short explanatory note together. Keep the share extension as a quick capture inbox.

Bevel is a useful interaction reference: its documented food flow accepts a photo or natural description, supports added context, and presents a reviewable result before saving. Its food-photo flow estimates what is on a plate. That is a different task from faithfully transcribing a cookbook recipe. [Bevel: How to Log Food](https://help.bevel.health/en/articles/11247745).

Support these as explicit input intents:

| Input | Expected result | How to handle uncertainty |
|---|---|---|
| Cookbook photo or screenshot | Transcribe visible ingredients, quantities, yield, sections, and instructions. | Mark cropped/illegible fields; preserve the source crop. |
| Several pages/screenshots | One ordered recipe, with ingredient and method sections linked. | Let the user reorder pages and identify multiple recipes. |
| Written recipe | Extract supplied facts, including prose rather than only newline lists. | Leave missing amounts/yields unknown; distinguish omitted steps from extraction failure. |
| Informal description, e.g. “our usual salmon pasta” | A meal draft using supplied facts, optionally with a suggested recipe. | Clearly label generated additions; do not mix them with extracted facts. |
| Photograph of a finished meal | Suggested identity and possible components. | Ask for hidden ingredients and quantities needed for a reproducible recipe; do not claim exact quantities from appearance. |
| URL | Identify the intended recipe and preserve attribution. | If several recipes exist, select by page identity or ask the user; the longest recipe is not necessarily the intended one. |

The current service prompt says never to invent missing ingredients or steps, which suits transcription. A dish-photo suggestion feature needs a separate intent and output contract. Merely deploying the service will not make these tasks equivalent. Bevel's published Intelligence limitations also distinguish food logging from creating/editing saved recipes; use the interaction pattern as inspiration rather than assuming complete feature parity. [Bevel Intelligence capabilities](https://help.bevel.health/en/articles/11586817).

The proposed flow is **capture → extract → review uncertain fields → save or update → plan**. The review screen should show the source next to the parsed result, editable ingredient rows, original yield, target portions, and clearly marked unknown fields. A sentence such as “That was 2 tablespoons, not 2 teaspoons; use oat milk” should produce visible proposed changes to the affected rows. Saving a partial recipe should be possible, but its shopping/scaling readiness must be clear.

Persist sources and drafts locally before starting extraction. Show progress and cancellation; retry without duplicate saves. Return an honest local-fallback status when the remote service fails. All imports should be reviewable even when the model declares high confidence; model confidence alone should not suppress attention to critical fields.

**Import implementation improvements**

- Configure and verify the existing remote service in a test build, after fixing the structured-data round trip. Evaluate the configured model with actual samples instead of accepting the roadmap's quality and cost claims as measurements.
- Send multiple images as one extraction job. Today `RecipeCapture.extract(fromImages:)` always routes two or more images to local OCR, even when the remote service is configured.
- Normalize photo orientation and supported encoding; resize to a known pixel/byte budget before upload. HEIC data currently falls through MIME detection as JPEG, and raw photo data can exceed the server's limit.
- Use column-aware document layout. Sorting OCR observations by vertical position and then horizontal position still interleaves two columns; it does not read an entire column before the next one. Preserve section headings and wrapped ingredient lines.
- Add a quality gate to local URL extraction. The current chain returns the first non-throwing result, including an incomplete recipe with instructions but no ingredients, so the remote extractor never sees it.
- Preserve ingredient sections such as sauce, filling, and garnish. Repeated ingredients in different sections need distinct row IDs; name/unit is an aggregation key, not a unique ingredient-line ID.
- Prefer recipe identity (`mainEntity`, URL/ID, page heading) over ingredient count when choosing JSON-LD. Scope microdata to the recipe rather than collecting unrelated page properties.
- Validate server inputs at runtime, enforce actual streamed request size rather than just declared Content-Length, and validate output bounds/completeness. Typed TypeScript declarations alone do not validate JSON. Add endpoint tests with a mocked model client, timeouts, malformed bodies, empty outputs, and rate-limit failures.
- Align user-facing data-transfer copy with reality: pasted text also goes to the service when enabled, and remote hero images can be fetched while browsing saved meals. Settings currently mentions only link/photo imports.

**Scaling needs a richer ingredient model**

The existing shopping builder and cooking mode already multiply ingredient quantities by planned servings divided by base servings. Retain that arithmetic, but improve what the numbers mean.

Store a stable ingredient-line ID, original text, normalized ingredient identity, amount kind (exact/range/unknown/to taste), unit and measurement system, package size, preparation note, optional status, section, and extraction evidence/review status. Use exact decimal or rational representation where appropriate and round only for display.

| Example | Correct behavior |
|---|---|
| 500 g chicken for 4; cook 6 | Show 750 g in the cooking view and shopping contribution. |
| 1 ½ cups flour | Preserve 1.5 cups and the measurement system. Convert to weight only with ingredient-specific conversion data. |
| 2 × 400 g cans tomatoes | Preserve can count and package size; distinguish needed amount from packages to buy. |
| 2–3 cloves garlic | Scale a range; retain the unit and leave a practical cooking choice. |
| Salt to taste | Keep “to taste”; do not manufacture or multiply a quantity of 1. |
| 2 adults, two smaller portions, one lunch portion | Sum explicitly chosen portion factors plus planned extra portions. Do not assign portion factors solely from age. |
| “Reserve 100 ml of the water” in a step | Keep the step linked to its ingredient allocation; update referenced amounts when the recipe is scaled. |
| Bake at 200°C for 30 min | Do not multiply temperature or duration with servings; flag batch/pan capacity when relevant. |

Separate active preparation time, cooking time, waiting time, and total elapsed time. URL import often fills `prepMinutes` from total time, while the server schema asks for active time; the planner and start-cooking reminder use the same field. A 15-minute preparation task with an hour in the oven must not appear equivalent to dinner ready in 15 minutes.

Recipe detail currently shows base amounts, while cooking mode shows planned amounts. Give the detail screen a serving selector and clearly pass planned portions when opened from a day. Changing a display portion count must never rewrite the source recipe's base yield.

**Maintaining the meal library after the first import**

Adding recipes is only half of the requested feature. Build these maintenance actions into the same flow:

- **Update an existing recipe:** match source URL, normalized title, and ingredient similarity, then offer update, variant, or separate recipe. Currently duplicates produce a warning asking the user to cancel and find the original.
- **Review changes:** show ingredient/yield/step differences and preserve household corrections. Reimport should not silently replace a substitute the family deliberately chose.
- **Versions and variants:** keep original attribution, local changes, and a prior version that can be restored. Support “mild version,” “vegetarian version,” and “for guests” without losing their relationship to the base meal.
- **Stable history:** archived plans currently reference live recipe IDs. Editing or deleting a recipe can change or remove what history can display. Preserve the version/name used at the time, with a separate rule for updating future plans.
- **Organization:** collections, ingredient/tag/time filters, recently added, needs review, favorites, frequently cooked, and not cooked recently. Add bulk tagging/archive operations once the library grows.
- **A clear detail screen:** open a recipe for reading first; put Edit, Duplicate, Update from source, Archive, and Plan on visible actions. Currently tapping a library row immediately opens the editor and planning is in a long-press menu.
- **Recovery:** draft autosave, undo delete/archive, library export/import, last-good backups, and later shared-household synchronization. Source photos should remain available for corrections; remote thumbnails should have an offline cache.
- **Library coverage:** before a rule is saved, show whether the library can support it jointly with existing rules. For example, “You need four suitable fish dinners across this rotation; you have two.” Link directly to import or candidate-rule adjustments.

Implement single-recipe correctness first, then batch imports with per-recipe review status. Bulk ingestion magnifies parsing mistakes if introduced before the review model.

**Household rules: realistic coverage**

“All realistic cases” is best treated as a composable rule system with explicit limits, not an ever-growing list of unrelated switches. Keep the default experience simple, then expose additional controls when needed. The matrix below is a proposed acceptance scope, not a claim that these capabilities exist today.

| Household request | Current coverage | Improvement needed |
|---|---|---|
| “Pizza Saturday; fish twice a week” | Supported vocabulary | Correct hard-rule enforcement; count combined tags consistently. |
| “Never this ingredient” | Substring matcher | Canonical ingredient identities and reviewed exclusions; handle unknowns. |
| “A person has dietary restrictions” | No dedicated profile | Person-specific requirements, ingredient evidence, and explicit uncertainty. |
| “One vegetarian; others eat chicken” | One meal per day | Shared base with portion-specific variants or multiple dishes; aggregate shopping. |
| “Avoid what Emma dislikes when she is home” | Per-member storage and matcher exist | A usable preference editor and per-date attendance; current UI records onboarding preferences for the primary member. |
| “Children here every other week” | No recurrence cycle | Alternating-week schedules with effective dates and one-off changes. |
| “Guests Friday; partner away Tuesday” | Manual diner counts | Named attendance, guests, and explicit portion factors. |
| “No cooking Wednesday, but this week is different” | Recurring mode rules and day contexts | Dated exceptions that override standing rules without changing future weeks. |
| “Shift work; my weekend is Tuesday/Wednesday” | Weekend fixed to Saturday/Sunday | Arbitrary day sets and household calendar patterns. |
| “20 minutes hands-on; ready by 18:00” | One time field | Active versus elapsed time; cook availability and serving deadline. |
| “No oven / only a microwave on holiday” | Custom-label workaround | Equipment requirements and temporary availability. |
| “Cook twice; eat leftovers on two other days” | Extra servings and source weekday | Dated batches, allocation balance, freezer availability, and compatible storage/reheating metadata. |
| “Sunday's leftovers on Monday” | Sources limited to weekdays within one plan | Cross-week dated batch references. |
| “No pasta two days running” | Supported but defective | True date adjacency, including the week boundary; define whether leftovers count. |
| “Repeat our favorite every fortnight” | Periodic inclusion exists | Target-date history; configurable planned-versus-cooked basis. |
| “A familiar dinner most days; one new recipe a week” | Favorites and taste scoring | Explicit novelty/familiarity limits and an optional rule priority. |
| “Use the spinach before shopping again” | Pantry items can be hidden | Quantity-aware inventory, use-by metadata, and ingredient reuse preferences. |
| “Stay under our weekly food budget” | No supported budget rule | Real entered/catalog prices, portion scaling, package costs, and clear handling of missing prices. |
| “Less washing up / no difficult meals on workdays” | Custom-label workaround | Structured effort, skill, equipment, and cleanup attributes where useful. |
| “Breakfast, lunch, dinner, and packed lunches” | Dinner-only | Explicit later scope expansion to meal slots; do not imply present support. |
| “A weekly nutrition target” | No nutrition model | Optional verified nutrient data and coverage indicators before adding quantitative rules. |
| “Keep what I chose; explain why the rest fails” | Locks and conflict messages | Minimal conflicting set, valid alternatives, and explicit unresolved days. |

A practical rule model has a **scope** (dates/day set/meal slot/people), **predicate** (all/any/not conditions), **constraint** (require/exclude/count/limit/spacing/dependency), **strength/priority**, and **exceptions/effective dates**. That supports “on school days when Emma is home, prefer a mild meal ready within 25 minutes” without adding a bespoke rule type for every sentence.

Natural-language entry can turn that sentence into an editable rule preview. The stored rule must remain deterministic and inspectable; an AI conversation should not be the enforcement engine. Dietary restrictions should not be relaxed by a weighted score or a manual lock.

Separate plan generation from plan validation. Use the same validator after generation, manual selection, recipe edits, swaps, portion changes, rule edits, and rollover. For the current seven dinner slots, consider bounded backtracking with the most-constrained day first, pruning, and soft scoring among valid candidates. Retain seeded randomness for variety. If a search budget expires, distinguish “no valid plan found yet” from “these rules are contradictory.”

**Other app-wide improvements**

Onboarding should ask household size and essential exclusions before generating the first week, then present starter rules as editable suggestions. Fish Tuesdays/Thursdays and pizza Saturday are a useful example, but they should not silently define every new household. Allow importing one family favorite early to demonstrate the app's actual value.

Make next week editable at day level, with locks, diners, and visible conflicts. Let the shopping view select a date range spanning current and next week. Show an explicit empty day with Choose/Adjust rules actions when planning fails; the current main list only renders days with entries.

For shopping, preserve ingredient provenance and show why an amount changed. Offer “remaining items” versus “whole list” when exporting. Repeated Reminders export currently appends duplicates. Bring export sends the original website URL, so local recipe edits are not exported; label that limitation or export the actual adjusted ingredients through a supported route. The “cheaper” swap still uses tag-based guessed costs, so it cannot reliably promise a cheaper result.

For cooking, add section-aware ingredients, linked step quantities, timers, substitution notes, and an easy return to the recipe. For history, distinguish what was planned from what was actually cooked and allow corrections; repetition rules currently use planned archives even if a meal was skipped.

Notification actions need a dated plan-entry identifier, not only a weekday and recipe ID. Acting on an old notification should not mark or reshuffle the current week's same weekday. Serialize notification rescheduling so an older asynchronous schedule cannot finish after a newer one.

Accessibility needs device testing: long localized ingredient names, large Dynamic Type, VoiceOver navigation of library cards, narrow rule-sentence rows, reduced motion, and camera/import recovery. The existing labels and system controls help, but structural checks do not establish usable layouts.

The store is now responsible for recipes, shopping, plans, history, rules, reminders, and persistence. Gradually move validation, recipe mutation, shopping reconciliation, and dated planning into focused services, keeping UI bindings thin. Do this alongside behavior changes rather than as a separate rewrite. Documentation should distinguish implemented behavior, disabled capability, and future intent; several current comments/roadmap claims overstate what the corresponding code guarantees.

**Recommended delivery order and acceptance gates**

1. **Make the current product trustworthy.** Fix required-rule relaxation, recipe edit fidelity, save errors, premature inbox deletion, leftover allocation, and stale conflicts. Acceptance: no hard exclusion violation; cancel/relaunch never loses a captured source; opening and saving an unchanged recipe preserves all structured values.
2. **Ship reliable recipe capture and updates.** Introduce source-backed drafts, typed quantities, yield extraction, multi-image handling, quality-based fallback, and update/variant actions. Configure and evaluate the service in a test build. Acceptance: source → saved recipe → scaled cooking view → shopping list preserves ingredient meaning and quantity.
3. **Make planning fit a real household.** Add dated exceptions, attendance and portions, meal variants, consistent rule validation/search, next-week editing, and date-range shopping. Acceptance: the household matrix above has explicit supported, unsupported, or deferred outcomes; no rule is silently ignored.
4. **Make the library durable and shared.** Add export/restore, recipe versions, collections, and offline household sync with visible conflict handling. Acceptance: both household members see the same saved recipe, portions, and shopping changes after reconnecting; conflicting edits remain recoverable.
5. **Expand only on measured demand.** Package-aware budgets, nutrition targets, additional meal slots, and community. These depend on data quality and should not delay the core dinner workflow.

Before calling capture reliable, create a curated English/Bokmål corpus covering clean and blurry scans, two-column pages, multi-page recipes, handwritten notes, screenshot chrome, wrapped lines, recipe sections, metric/imperial quantities, missing yield, prose-only input, contradictory sources, and multi-recipe pages. Record field accuracy, omitted/invented ingredients, yield accuracy, correction effort, latency, and fallback frequency. Establish a baseline first; do not invent an accuracy claim.

Add regression cases for each finding above. Rule tests should include feasible and infeasible combinations, very small libraries, locked meals, empty days, week boundaries, multiple consumers of leftovers, and recipe edits after shopping. Use a small exhaustive reference solver for generated small cases to catch false impossibility reports. Add end-to-end iOS tests for import cancellation, saved drafts, serving changes, and household planning. Run the complete XCTest suite and physical-device camera/share-extension checks on macOS before release.
