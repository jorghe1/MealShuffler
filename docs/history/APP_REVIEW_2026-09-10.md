**Meal Shuffler — current-state review, 10 September 2026**

The app has a substantial foundation: a local planner, dated weeks, required and preferred rules, day exceptions, per-person preferences, leftovers, recipe capture, drafts, revisions, grocery aggregation, cooking mode, notifications and extensions. The next release should concentrate on reliable quantities, consistent plan state and understandable language. These have more immediate value than expanding the rule vocabulary or opening community features.

This review covers the current working tree, including the uncommitted September 9–10 implementation. It does not treat findings in the previous review as automatically still open. No application code was changed; this document is the review deliverable.

**Evidence and limits**

- All five repository Python checks passed: localization coverage, localized format arguments, Swift structure, store references and Swift argument labels. Coverage reported 846 source keys and 880 Norwegian entries.
- `npm --prefix server run check` passed TypeScript checking and all 18 server tests.
- `git diff --check` reported no whitespace errors; Git emitted line-ending conversion notices.
- There are 149 XCTest test methods in the current sources. Swift, Xcode and an iOS simulator are unavailable here, so these tests, app compilation, extension compilation and actual screen layouts were not executed.
- The recipe metadata regexes were replayed on concrete examples using Python. This confirms their matching behavior on those inputs; it is not an executed Swift import test.
- Contrast ratios below were calculated from the source palette. They are not measurements of rendered iPhone screenshots.
- The checked-in recipe-service URL remains empty. Server unit tests use a substitute extractor and do not establish live model quality or production readiness.

The functional findings below are traced code paths. Layout and interaction recommendations are source-based assessments requiring device verification. P1 means fix before depending on that feature in a household release; P2 means a material next-release issue; P3 means polish or expansion.

**What the latest implementation already improves**

Required constraints are retained in fallback selection, a bounded search handles interacting rules, and unresolved days can be displayed. Next week has separate contexts and conflicts. Structured imported ingredients survive untouched edits; missing quantities are no longer automatically one; imported yield and timing have review flags. Captures survive cancellation, drafts resume, source photos and previous versions are retained, and custom recipes can be exported. Storage now has backup/recovery handling and reports failed writes. Keep these improvements and verify them on iOS rather than rebuilding the app's architecture from scratch.

**Functionality and data correctness**

1. **P1 — Norwegian instructions can become a false recipe yield.** The yield regex accepts `til` followed by any number anywhere in the source. `Forvarm ovnen til 200 grader.` therefore supplies a yield of 200 when an earlier recognized yield is absent. That value sets `servingsConfirmed` to true. For four portions, 500 g of an ingredient then becomes 10 g. Restrict yield parsing to explicit yield fields and phrases such as `til 4 personer`; retain the evidence and mark ambiguous matches unconfirmed. Add an import regression containing an oven temperature and no yield. Evidence: [metadata parsing](C:/dev/meal_shuffler/MealShuffler/Services/RecipeTextStructurer.swift:111), [draft confirmation](C:/dev/meal_shuffler/MealShuffler/Services/RecipeTextStructurer.swift:29).

2. **P1 — Preparation/cooking time can be mistaken for total elapsed time.** `Prep time: 10 minutes\nTotal time: 50 minutes` matches 10; `Steketid: 20 minutter\nTotal tid: 45 minutter` matches 20. The regex takes the first matching `time` or `tid`, including inside another label, and the draft treats it as known total time. This can incorrectly satisfy a time limit and schedule the start reminder too late. Prefer an explicit total field regardless of position, parse preparation/cooking fields separately and leave total unknown when it cannot be established. Evidence: [time parsing](C:/dev/meal_shuffler/MealShuffler/Services/RecipeTextStructurer.swift:113).

3. **P1 — Several starter recipes use purchase containers as cooking amounts.** Baked salmon contains one bottle of olive oil; chicken stir-fry contains one bottle of soy sauce; lentil curry contains one bag of curry powder. These values also appear in cooking mode and multiply with servings. Multiple dinners can accumulate several bottles even though only spoonfuls are consumed. Audit all 40 starter recipes: store consumed amounts in g/ml/spoon measures, keep package purchasing separate, and check that ingredients, method, yield and total time agree. Pantry hiding should not compensate for incorrect recipe data. Evidence: [olive oil](C:/dev/meal_shuffler/MealShuffler/Data/SampleMeals.swift:31), [soy sauce](C:/dev/meal_shuffler/MealShuffler/Data/SampleMeals.swift:74), [curry powder](C:/dev/meal_shuffler/MealShuffler/Data/SampleMeals.swift:162), [aggregation](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:740).

4. **P1 — Notification actions have a weekday but no meal date or plan identity.** A delivered notification survives the week it describes. Tapping its “Something else” action after rollover sends the old meal ID and weekday to `markSkipped`, which regenerates that weekday in the current plan. “Cooked” records the time of the tap rather than the intended dinner date. Carry the dated planned-entry identity, verify that replacement still targets the same entry, and make cooked actions idempotent. Old notifications should never replace a different week's dinner. Evidence: [notification payload](C:/dev/meal_shuffler/MealShuffler/Services/DinnerReminderService.swift:358), [action handler](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:297), [feedback](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:851).

5. **P1 — Changes to this week can leave next week's conflicts stale.** `refreshConflicts()` validates both weeks, but `shuffleAll()` uses `apply()` and rule changes use `regenerate()`; those update only current-week conflicts. Prepare next week, then introduce a required rule or shuffle this week into a meal next week already uses under a repeat window: next week's displayed conflicts can still describe the old state. Route all relevant plan/rule mutations through a common reconciliation step that validates both target weeks. Revalidation need not silently reshuffle the prepared plan. Evidence: [regeneration](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:694), [rule changes](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:786), [both-week validation](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:1151), [apply](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:1177).

6. **P1 — “Shuffle the rest” can replace past and already-cooked dinners.** The button calls the same whole-week shuffle as the header; only explicit locks are preserved. Marking a dinner cooked appends an event without completing or locking its plan entry. On Thursday, Monday's cooked meal can therefore change, affecting the eventual archive and shopping list. Introduce dated planned/cooked/skipped status; preserve completed and past entries by default, with an explicit correction action. Define “rest” as remaining eligible dinners and show its count. Evidence: [button](C:/dev/meal_shuffler/MealShuffler/Views/Planner/WeekPlanView.swift:82), [shuffle](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:671), [mark cooked](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:851).

7. **P2 — Removing a family member leaves their preferences and rules behind.** Removal changes the roster only. The merged preference map and match context still iterate all stored member preferences, so a removed person's dislikes can continue affecting selection and a required personal exclusion. Remove or retire their preference state, attendance references and personal rules together, then revalidate both weeks. Evidence: [member removal](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:962), [merged preferences](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:587), [match context](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:1074).

8. **P2 — Export can create a backup the app refuses to import.** Import rejects files over 100 MB, while export has no equivalent preflight or partitioning. Source images are embedded in JSON as base64, so roughly 75 MB of image bytes alone approaches that limit. A legitimate growing library can export successfully and fail at restoration. Use a bounded archive format with separate image files or split exports; validate every exported artifact against the actual import path. Test a library crossing the limit. Evidence: [archive/export/import](C:/dev/meal_shuffler/MealShuffler/Views/Meals/LibraryTransferView.swift:42).

9. **P2 — Some ordinary Norwegian ingredient lines still parse poorly.** The supported unit list includes `boks`, but not `bokser`; `2 bokser à 400 g hakkede tomater` therefore does not become two 400 g cans. Package notation after a container and plural Norwegian units need support. In addition, a missing quantity displays “Etter behov,” which implies an intentional cooking instruction rather than an unreadable or absent amount. Distinguish unknown from “to taste,” preserve the source line, and flag unsupported structures in the editor and shopping list. Evidence: [units and parser](C:/dev/meal_shuffler/MealShuffler/Services/RecipeImportService.swift:597), [amount display](C:/dev/meal_shuffler/MealShuffler/Models/Meal.swift:72).

10. **P2 — Reminders export duplicates entries and includes purchased items.** Both text export and Reminders receive `store.groceryItems`, which includes checked rows. Each Reminders export creates fresh reminders, so exporting twice doubles them. Offer “Remaining items” and “All items,” default to remaining, and reconcile app-owned entries for the chosen shopping period. Weekly-plan text also needs a date range and explicit unresolved days; today it has weekday names and silently omits absent entries. Evidence: [grocery export](C:/dev/meal_shuffler/MealShuffler/Views/Grocery/GroceryListView.swift:229), [new reminders](C:/dev/meal_shuffler/MealShuffler/Services/PlanExportService.swift:37), [plan text](C:/dev/meal_shuffler/MealShuffler/Services/PlanExportService.swift:5).

11. **P2 — “Quicker,” “cheaper” and “favorite” can quietly return an ordinary alternative.** If the requested subset is empty, `candidatePool` returns its unrestricted base. A “quicker” action can produce an equally slow or slower dish. “Cheaper” also relies on fixed category estimates and compares whole-recipe costs without accounting for different base yields. Return the achieved outcome and explain when no matching replacement exists; label cost as an estimate or require usable cost data. Evidence: [intent fallback](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:361), [cost heuristic](C:/dev/meal_shuffler/MealShuffler/Models/Meal.swift:245).

12. **P2 — Swapping non-cooking days separates the visible plan from its day settings.** `swapMeals` swaps meal ID/kind, but leaves both day contexts in place and applies cooking-serving counts to either kind. Swap an away day with a cooking day: the visible modes move while the editors retain their previous modes; another shuffle can reverse the apparent choice. Define whether the action swaps recipes or entire day arrangements. Restrict recipe swaps to cooking entries, or move the relevant context and reconcile leftovers and servings atomically. Evidence: [swap](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:761).

13. **P2 — Automatic leftovers choose the latest dinner, not a batch with capacity.** If Monday has enough extras and Tuesday has none, Wednesday's automatic source picks Tuesday and reports insufficient leftovers. Search earlier batches by remaining portions, exclusions and chronological eligibility; show source and remaining balance in the editor. Current bounded search also carries fallback leftover links while changing source meals; validate the final resolved links during search, not only afterwards. Evidence: [source choice](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:309), [search](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:232), [link refresh](C:/dev/meal_shuffler/MealShuffler/Services/MealPlanGenerator.swift:296).

14. **P2 — Recipe and cooking history still need clearer identity.** Repeated “We cooked this” taps create repeated events. Activity resolves live recipe IDs: deleted custom meals disappear from the list and renamed recipes change old activity labels. Archived weeks now have snapshots, but History does not expose an archived-week browser. Store a dated cooking event and recipe snapshot/version, support correction, and separate planned-week history from confirmed cooking history. Evidence: [feedback append](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:851), [activity rendering](C:/dev/meal_shuffler/MealShuffler/Views/History/MealHistoryView.swift:114), [archive model](C:/dev/meal_shuffler/MealShuffler/Models/WeeklyPlan.swift:103).

15. **P2 — Deleting a customized starter recipe makes its original reappear.** Editing a built-in preserves its ID but changes the source to manual, enabling Delete. Catalog resolution removes the deleted override and falls back to the built-in recipe. Expose “Reset to original” explicitly and provide a separate archive/hide choice if the user wants the dish removed from planning. Evidence: [editor save](C:/dev/meal_shuffler/MealShuffler/Views/Meals/RecipeEditorView.swift:335), [catalog resolution](C:/dev/meal_shuffler/MealShuffler/Models/MealFeedback.swift:44).

16. **P2 — Rule scheduling and management are incomplete.** Existing rules can be enabled, deleted or have strength changed, but their day, target, count and recurrence cannot be edited. Starting week is not shown in the list. Duplicate checks compare raw dates and optional intervals even though activation normalizes to a week; equivalent schedules can be accepted twice. Add an edit flow, display the effective period and next active week, normalize recurrence identity, and provide clear feedback from the household “Avoid these dislikes” action, which currently ignores the add result. Evidence: [rules UI](C:/dev/meal_shuffler/MealShuffler/Views/Rules/RulesView.swift:1), [duplicate check](C:/dev/meal_shuffler/MealShuffler/Store/AppStore.swift:814), [household action](C:/dev/meal_shuffler/MealShuffler/Views/Household/HouseholdView.swift:102).

17. **P2 — Fast onboarding taps can advance multiple cards.** `choose` writes the current preference and schedules a delayed index increment, but has no transition guard. Two quick taps can schedule two increments for the same displayed card and skip the next one; Back is also available during that delay. Disable choices during the transition and use one cancellable transition operation. Evidence: [swipe selection](C:/dev/meal_shuffler/MealShuffler/Views/Onboarding/OnboardingFlowView.swift:179).

18. **P2 — The share inbox has a cross-process lost-update risk.** App removal and extension addition both read and rewrite one array in shared defaults without coordination. An overlapping remove/add can overwrite a new capture or resurrect an old one. Store captures as independent files keyed by ID or use coordinated transactions. Test the actual extension/app overlap and do not report “saved” until durable capture succeeds. Evidence: [inbox mutations](C:/dev/meal_shuffler/MealShuffler/Services/RecipeInbox.swift:43), [share capture](C:/dev/meal_shuffler/MealShufflerShare/ShareViewController.swift:39).

**Norwegian: fix sentence construction first**

Your example is a real defect. The current builder composes `På` + `Mandag` + `er vi` + `takeaway`. Other current options produce `På Mandag er vi lag middag`, `… er vi spis rester` and `… er vi ingen hjemme`. Changing only the translation of “we're” cannot make all of these grammatical. Evidence: [sentence assembly](C:/dev/meal_shuffler/MealShuffler/Views/Rules/RulesView.swift:185), [mode labels](C:/dev/meal_shuffler/MealShuffler/Models/WeeklyPlan.swift:123), [translation](C:/dev/meal_shuffler/MealShuffler/Resources/nb.lproj/Localizable.strings:857).

For a recurring rule, use full sentences such as:

| Meaning | Proposed Bokmål |
|---|---|
| Recurring takeaway Monday | På mandager bestiller vi takeaway. |
| This Monday only | På mandag bestiller vi takeaway. |
| Cooking Monday | På mandager lager vi middag. |
| Leftovers Monday | På mandager spiser vi rester. |
| Away Monday | På mandager spiser vi ikke middag hjemme. |
| Fish on weekdays | På hverdager spiser vi fisk. |
| Fish at weekends | I helgene spiser vi fisk. |
| Fish every day | Vi spiser fisk hver dag. |
| Selected days | På mandager og onsdager spiser vi fisk. |
| Exclusion for a person | Vi unngår retter Emma ikke liker på mandager. |
| Weekly maximum | Vi spiser kylling høyst to ganger i uken. |

The recurring examples describe eating occasions; the engine currently counts cooking entries for weekly totals. Either extend the count to include leftovers or make that distinction explicit in the final wording.

The day scope needs grammatical context: `på mandager`, `på hverdager`, `i helgene`, and bare `hver dag`. The universal `%@ på %@` template currently creates `fisk på hver dag` and `fisk på helgen`. Norwegian weekdays use lowercase within sentences; a standalone heading may start with a capital. [Språkrådet's capitalization guidance](https://sprakradet.no/godt-og-korrekt-sprak/rettskriving-og-grammatikk/stor-eller-liten-forbokstav/).

Localize complete sentence templates with typed placeholders, including mode-specific verbs and scope-specific phrases. Keep menu labels separate from sentence forms. Preserve capitalization in user names and recipe titles rather than blindly lowercasing matcher labels. For editable sentence tokens, allow the localized template to determine token order; reuse the same formatter for preview, saved summary, accessibility and conflict messages.

**Other Norwegian corrections and editorial suggestions**

These distinguish malformed output from wording that is valid but unnatural. “Takeaway” itself is a reasonable product-language choice; consistency matters more than replacing every loanword.

| Current output/copy | Suggested replacement | Why |
|---|---|---|
| På Mandag er vi Takeaway | På mandager bestiller vi takeaway | Wrong verb, capitalization and recurring-day form. |
| … på hver dag / … på helgen | … hver dag / … i helgene | Incorrect scope/preposition assembly. |
| `2 clove` after importing `2 fedd` | 2 fedd | Normalization produces an English unit with no localized display case. |
| `ALREADY AT HOME` in the stocked section | HAR ALLEREDE | `.uppercased()` is applied before localization, creating a dynamic untranslated string. |
| 1 porsjoner / 1 minutter | 1 porsjon / 1 minutt | Add plural-aware quantity strings; `1 person`, `1 rett`, `1 uke` need the same treatment. |
| Regler vi antok | Forslag til regler | More natural and explains these are editable starting suggestions. |
| Når uken snur | Når neste uke begynner | Literal translation of “when the week turns.” |
| Forkast neste uke | Slett planen for neste uke | Says what will actually be deleted. |
| Stokk resten | Stokk om resten av uken | Clearer, once the action really preserves completed days. |
| Gjør regelen myk | Endre til «Bør følges» | Matches the existing strength label instead of introducing another term. |
| Harde regler / myke regler | Regler som må følges / ønsker | More understandable; choose one vocabulary throughout. |
| Vis onboarding på nytt | Vis introduksjonen på nytt | Avoids internal product terminology. |
| Smakssvar | Matpreferanser | Easier to understand in reset copy. |
| Lagringen trenger oppmerksomhet | Kunne ikke lagre endringene | Use operation-specific messages and a clear recovery action; load failure needs different copy. |
| Lengst siden dere laget den, først | Rettene dere ikke har laget på lengst tid, vises først | Natural sentence structure. |
| Legg på en dag | Velg dag | Names the next action clearly. |
| Midlertidig gjentakelsesstraff | Retter dere nylig har laget, velges sjeldnere | Explain the result, not scoring internals. |
| Klar til butikken | Klar til å handle | More natural shopping heading. |
| MIN badge | EGEN | Better description of a household's own recipe; optional editorial change. |

Evidence for the localization bypass and unit leak: [stocked heading](C:/dev/meal_shuffler/MealShuffler/Views/Grocery/GroceryListView.swift:145), [unit normalization/display](C:/dev/meal_shuffler/MealShuffler/Services/IngredientUnits.swift:20). Most other entries are in the [Bokmål catalog](C:/dev/meal_shuffler/MealShuffler/Resources/nb.lproj/Localizable.strings:1).

Recipe instruction wording also deserves an editorial pass: “Stek … til kanten er mørk i toppene” is an awkward translation; describe browned edges directly. Keep temperature spacing consistent (`200 °C`) and use the intended cooking verb in context. The current catalog still contains obsolete allergy assurances and old backend/onboarding wording that the active views no longer use; remove or label unused keys so they are not accidentally reused. English service error strings are passed through directly; return stable error codes and localize the user-facing explanation in the app.

Use `du` for the person operating the phone and `dere` for the household, consistently. “Må følges”/“Bør følges,” `rett` for a dinner choice, `oppskrift` for ingredients/method, and `ukeplan` for the dated plan would make a useful small terminology guide. A passed key-coverage check proves neither grammatical sentences nor that every UI string takes a localization path.

**UI and UX improvements, screen by screen**

| Area | Current friction | Recommended change |
|---|---|---|
| First launch | Eight swipes are compulsory; portions and assumed fish/pizza rules are folded away after generation. | Offer Skip and Neutral, clarify whose preferences are being recorded, and make the household portion count visible before the first shopping list. Keep the real first-week preview. |
| Week home | Two shuffle entry points; seven detailed cards; cooking is inside the overflow menu. | Give today a prominent card with Open recipe, Start cooking and a visible completion state. Keep a compact week overview and put future changes within easy reach. |
| Day editing | Attendance and portion count are separate controls, so a household member can be switched off while portions stay unchanged. | Retain explicit portions for flexibility, but offer “Use attendance count” and show `3 eating + 2 extra = 5 portions`. Hide irrelevant fields on away days. |
| Conflicts | Current-week details are collapsed and often offer only softening a rule. Next week shows plain messages. | Show affected day, failed requirement and a relevant repair: choose a matching recipe, change portions, unlock, edit rule or select a leftover batch. Make relaxation one deliberate option. |
| Rule creation | Nine template chips, four/five segmented targets, sentence tokens and recurrence controls compete for attention. | Start with common presets, reveal advanced controls progressively, and show a complete grammatical preview plus the effect on this week's plan. Add existing-rule editing. |
| Next week | Meal selection is an unfiltered menu; absent entries lack a day-context button; rows do not open recipe details; discard has no undo. | Reuse the current-week day card, searchable picker and detail flow with an explicit target week. Allow away/takeaway on unresolved days and add undo for shuffle/discard. |
| Library | Helpful detail view now exists, but fixed add-method chips occupy the top and organization stops at All/Favorites/Mine. | Use a prominent Add recipe action with named methods. Add category/time/tag filters, sorting by recent addition/last cooked, and a “Needs review” view. |
| Import review | A long form alternates raw ingredient text and a parsed preview; critical metadata uses steppers up to 1,000 servings and 10,080 minutes. | Use numeric entry plus steppers, editable ingredient rows, visible uncertainty and section headings. Offer source zoom and focused comparisons. Say why Save is unavailable and distinguish Save draft from Save recipe. |
| Cooking | Full ingredient list sits above each step; progress is lost when the view closes; no timers. | Collapse gathered ingredients, retain progress for the dated dinner, show a step overview, and add optional timers. When portions change, explain that quantities written inside method text remain the source values. |
| Shopping | No week/date scope, no completed-items section, generic “nothing to buy” when everything is owned, removal hidden in a long press. | Show the shopping period and planned-dinner coverage; offer remaining/all/completed views, visible edit/remove actions, and distinct all-done/no-plan/incomplete-recipe states. Support shopping for next week. |
| History | Tapping a rotation row toggles favorite; planning is in a long press; only twelve rotation entries are shown. | Open recipe details on tap, keep the heart explicit, add Plan as a visible action and offer full rotation/archived-week views. |
| Settings | Recipe backups lead the Household section; local-only family terminology can imply collaboration; reminder time doubles as desired dinner time. | Group Family, Notifications, Data and About clearly. Explain local household profiles, and distinguish “Dinner at” from “Remind me at.” |

The visual direction is coherent in source: warm background, green accent, rounded cards and common controls. Retain it. Reduce repeated explanatory copy and oversized decorative space as the library grows. Imported recipe photos have a useful role; make photography optional and consistent rather than requiring images for every starter recipe.

**Accessibility and layout work to verify on-device**

- **Small screens and large type:** the onboarding stack is not scrollable and the taste card has a 380-point minimum height. Several rows force recipe names to one line. The rule sentence HStacks, target segmented picker and composition legend do not adapt to wrapping. Test the narrowest supported iPhone with the largest accessibility text size, landscape where supported, and the keyboard visible. Use adaptive vertical layouts and multi-line names.
- **Touch targets:** the common icon frame is 44 points, but Choose pills, category tags, source discard and some cooking ingredient controls do not explicitly enforce that size. Audit the rendered hit areas, including gaps between neighboring actions. Apple recommends 44 × 44-point controls in its [UI design guidance](https://developer.apple.com/design/tips/).
- **Contrast:** the source warning color has about **4.39:1 on white** and **3.49:1 on the warning-tinted planner background**. It is used for small labels. Darken the light-mode warning text or separate warning text/icon/background tokens. Normal-size text generally needs 4.5:1 under Apple's [sufficient-contrast guidance](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria). Check actual rendering and increased-contrast settings too.
- **VoiceOver correctness:** the week-strip label substitutes “Not planned” for away/takeaway entries because it only reads meal names. Day cards announce “Opens the recipe” even when there is no recipe to open. Tag selection needs selected-state announcements, and interactive cards should use proper button semantics. Announce save, completion and shuffle outcomes without stealing focus.
- **Reduced Motion:** the custom swipe rotation, scale transitions and week animations have no explicit reduced-motion alternative in these sources. Honor the setting and verify behavior; do not assume that declaring Dynamic Type fonts or a shared theme completes accessibility.

Evidence: [onboarding layout](C:/dev/meal_shuffler/MealShuffler/Views/Onboarding/OnboardingFlowView.swift:256), [day labels](C:/dev/meal_shuffler/MealShuffler/Views/Planner/WeekPlanView.swift:299), [palette](C:/dev/meal_shuffler/MealShuffler/Theme/AppTheme.swift:17), [composition legend](C:/dev/meal_shuffler/MealShuffler/Views/Components/WeekCompositionView.swift:93).

**Engineering and product semantics to settle**

- **What counts as eating a category?** Weekly maxima/minima and consecutive-day validation count `.meal` entries, excluding leftovers. Consecutive-day rules also have no previous-week neighbor. A fish dinner Sunday followed by fish Monday is allowed; fish leftovers do not count towards “fish twice.” Decide whether each rule concerns cooking or eating, label it accordingly and test the week boundary.
- **Main-thread work:** AppStore runs planning synchronously, including up to 20,000 search nodes and 250,000 candidate evaluations. Editor draft identities include image data; `saveDraft` re-encodes images with the draft, and existing source images are read synchronously. Repeated photo preparation also re-encodes JPEGs. Profile real large libraries and five-page imports; move expensive work behind cancellable background operations and store image references in draft metadata. Show progress when it is needed.
- **Import fidelity:** URL selection still chooses the recipe with the most ingredients, rather than page identity. Microdata collects page-wide properties. Local OCR remains ordered text, not full column layout recognition. Local URL download checks size only after buffering. Prioritize main-entity selection, scoped microdata, streamed limits and an English/Bokmål corpus with columns, wrapped lines, multiple recipes and missing fields.
- **Recovery:** recipe backups omit household settings, plans, preferences, drafts and revision history. Say exactly what is exported and add a full-device backup/restore option separately. Prune unreferenced source images only after accounting for live recipes, drafts, revisions and archived snapshots. Surface recovery status with a retry/export route rather than a dismiss-only generic alert.
- **Online extraction:** keep the service optional, expose whether local or online reading was used, and preserve sources on failure. Before activation, verify actual deployment, model availability, timeouts and costs with real test imports. Per-IP/per-install limits do not supply a global spending ceiling; add aggregate operational limits and useful failure metrics without logging recipe contents.
- **Shared-family use:** sharing plain text is already useful, but it is not shared state. Keep sync/community feature flags off until those features work. Shared shopping checks, recipes and preferences are the most valuable eventual collaboration additions.

**Suggested delivery sequence**

1. **Reliability and language pass:** fix false yields/times, starter recipe quantities, dated notification actions, both-week reconciliation and preservation of completed dinners. Replace rule sentence fragments, unit leaks and untranslated dynamic text. Run a macOS build for the app, widget and share extension plus all XCTest tests.
2. **Complete the existing workflows:** add rule editing, next-week parity and undo, useful conflict repairs, numeric metadata entry, export reconciliation and a backup round-trip that respects size limits. Improve today/cooking/shopping visibility and resolve large-type and VoiceOver problems.
3. **Measured import quality:** evaluate local and configured online extraction using a fixed source corpus. Track correct yield, total time, ingredient amounts/units, recipe identity and correction effort. Do not use a successful HTTP response as the quality metric.
4. **High-value additions:** date-range shopping, shared household shopping/library, fractional portions, leftover/freezer batches across weeks, recipe collections and cooking timers. Defer nutrition claims, budget optimization, broad natural-language rules and public community until the underlying data and requirements support them.

**Acceptance cases for the next pass**

- Oven temperature alone never establishes servings; preparation time never masquerades as total time.
- Cooking and shopping agree at 1, 2, 4 and 6 portions, including ranges, unknown amounts and packages.
- Starter recipes use actual cooking amounts; multiple dishes do not request one condiment bottle each by default.
- Changing rules or this week's plan updates next-week validation immediately without silently replacing its choices.
- Shuffling remaining dinners preserves past/completed entries; duplicate cooked actions do not inflate history.
- An old notification cannot change a different dated meal; feedback records the intended date.
- Removing a member removes their influence and handles associated rules explicitly.
- Automatic leftovers find an eligible batch with remaining portions; both weeks show shortages accurately.
- Every export is importable within declared limits; export twice to Reminders does not duplicate app-owned entries.
- All rule modes × day scopes × strengths × singular/plural counts produce grammatical English and Bokmål, including user names and long recipe titles.
- Test blank, partial, conflicting and all-away plans, offline imports, cancellation/resume, corrupted storage, process overlap in share capture, maximum text size, VoiceOver and Reduced Motion on a physical iPhone.
