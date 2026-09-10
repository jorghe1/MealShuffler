# Review follow-up implementation

Implemented locally September 9–10, 2026. This records the changes following the
[app review](APP_REVIEW_2026-09-09.md). The review remains a record of the original findings.
The changes have not been deployed or validated on an iPhone.

## Recipe capture and maintenance

- Photos and scans support up to five ordered pages plus text context. Pages can be reordered
  before extraction. Images are redrawn in display orientation, resized and encoded as JPEG.
  A configured service receives the pages together. Local OCR remains the fallback.
- Pasted text and photo sources are saved as resumable drafts before extraction. Extraction
  results are saved before opening the editor. Editor changes autosave; cancelling retains
  unfinished work in the library. Shared captures remain in the inbox until a recipe saves.
- Extraction retains structured ingredient amounts, aisles and source text. Editing another
  row no longer reparses and overwrites untouched ingredient corrections. Duplicate ingredient
  lines have separate identities. Original photos remain available for review.
- Quantities support mixed fractions, attached units, ranges, package sizes and unspecified
  amounts. Missing amounts stay unspecified; they no longer become a fabricated quantity of one.
  Grocery quantities use the upper end of a range and normalize supported units. Package mass
  contributes to shopping quantities; a retail package-rounding/purchasing model remains future work.
- Imported yield is retained. Missing yield and total elapsed time require confirmation before
  saving a recipe for planning. An incomplete recipe can remain a draft. Total time drives the
  existing planner; remote active time is retained separately. Detailed timing phases are future work.
- Recipe details open for reading with a serving selector. Opening from a planned day uses that
  day's portions. Cooking and shopping scale from the original yield; display scaling does not
  change the recipe. Instructions remain source text: embedded quantities inside steps are not
  automatically scaled, and temperature/time are not multiplied.
- Library actions expose Edit, Plan, variant creation, Update from source and previous versions.
  Duplicate title/source matches offer updating an existing recipe or making a variant. The editor
  can show existing ingredients/steps and keep either. Custom labels survive source refreshes.
- Updates retain up to ten previous versions. Deleted custom recipes can be restored. New archived
  weeks retain the recipes used at archival time; older archives cannot recover missing historical
  versions retroactively. This is not a snapshot of every past cooking event.
- Settings includes recipe library export/merge import with source photos, bounded validation and
  filename checks. It exports active custom recipes/customizations, not the entire household state,
  draft queue or revision history. Matching IDs update; others are retained.

## Planning and persistence

- Required maxima, repeat windows and consecutive-day constraints are no longer dropped in the
  fallback pool. An unfillable day remains unresolved with a visible conflict and recovery actions.
  User-locked choices remain visible and are validated; the app does not silently replace them.
- Generation uses bounded backtracking when the first pass has conflicts, choosing constrained days
  first and pruning unreachable weekly minimums. The search has budgets of 20,000 nodes and 250,000 candidate evaluations and preserves
  its safe partial result. A failure means no compliant plan was found, not proof of impossibility.
  Soft scoring among all valid complete plans and a minimal conflicting rule set remain future work.
- Validation also runs after recipe changes and manual plan changes. Leftover links are refreshed
  in both weeks. Multiple leftover dinners consume the same source's available extra portions
  cumulatively. Exclusions are checked against leftover meals as well as cooked dinners.
- Per-person likes/dislikes can be edited. Attendance by day controls personal exclusions, while
  diners and extra portions remain explicit independent quantities.
- Rules can use selected day groups, an effective starting week and a recurrence interval of one
  to eight weeks. Standing dinner modes support exceptions in an individual week. Dinner modes are
  fixed commitments; preference strength applies to food rules. Legacy preferred dinner-mode rules
  retain their previous effective fixed behavior and now display it explicitly.
- Next week has separate contexts, day selection, locks and conflicts. Editing its day context
  preserves the other planned days. Rollover promotes its contexts or starts with fresh day settings.
- Higher shopping quantities invalidate completed/already-owned ticks. Matching manual/derived
  items use the same normalized identity. This is not quantity-aware pantry inventory.
- File saves surface errors, retain a last-good backup and preserve corrupt input before recovery.
  Newer schema files cannot be overwritten. Recipe save failure keeps the editor open. Notification
  rescheduling is serialized. Dated notification-action identity remains to be implemented.

## Household coverage and remaining scope

| Request | Status after this change |
|---|---|
| Fixed meal/category days, weekly counts, time limits, repeats, spacing | Implemented, with conflicts for infeasible combinations |
| Work shifts/custom day groups/alternating weeks | Implemented for weekly schedules |
| A one-week change to a standing dinner plan | Implemented through day exceptions |
| A member is absent or has dislikes | Attendance-aware exclusions implemented |
| Guests, larger portions, packed leftovers | Manual diners and extra portions supported |
| Fractional appetites or several different dishes on one day | Deferred; one dinner and integer portions per day |
| Several leftover dinners using one batch | Portion allocation implemented within the week |
| Freezer batches across weeks, expiry, planned versus actual consumption | Deferred |
| Allergies/religious/medical restrictions with ingredient verification | Deferred; name matching is explicitly not allergen verification |
| Read a cookbook photo, screenshot, link or written recipe | Implemented review/draft paths; online service setup and real-source evaluation remain |
| Infer an exact recipe from a finished dish photo | Not offered; hidden ingredients/amounts cannot be established from appearance |
| Natural-language corrections, generated suggestions, compound natural-language rules | Deferred |
| Collections, bulk tagging, date-range shopping, shared household sync | Deferred |
| Budgets, nutrition targets, breakfast/lunch slots and community | Deferred as recommended in the review |

Local OCR still uses row order, not full column/layout recognition. URL selection still needs
recipe identity and scoped-microdata improvements. The model-assisted path has no measured
accuracy claim: a real English/Bokmål corpus is needed for blurry scans, handwriting, columns,
wrapped lines, prose, multiple recipes and contradictory sources. Meal categories remain
reviewable suggestions. They cannot certify dietary suitability.

## Verification and activation

- Server TypeScript check and all 18 server tests pass, including malformed requests, multi-image
  context, actual body limits, rate limits, unknown fields, invalid ranges and incomplete packages.
- All five Python repository checks pass: Swift structure, call labels, store API, localized format
  arguments and Norwegian coverage. `git diff --check` is clean.
- Added XCTest regressions for structured import fidelity, quantities, missing yield, recipe archive
  validation/history, hard constraints, interacting rules, attendance, leftovers, recurrence,
  corruption recovery, future schemas and independent next-week settings. The existing remote import
  test now requires review at high confidence. XCTest and Swift compilation have **not run** here.
- This Windows environment has no Xcode/iOS simulator. Run the complete test target, build all app
  extensions, then test camera/photo/share imports, cancel/resume, backup restoration, accessibility,
  serving changes and rollover on a device before release. Static checks do not establish compilation
  or UI correctness.
- `RECIPE_SERVICE_BASE_URL` remains empty and Wrangler is unauthenticated. Online extraction needs
  Cloudflare login, an Anthropic API key, Worker deployment and a configured test build. See
  [server setup](../server/README.md). No production deployment or live model evaluation was performed.

Suggested next sequence: macOS build/device validation, online service activation and corpus
evaluation, then compound rule/portion support and shared library synchronization. Account-backed
features and data-dependent budget/nutrition features should be built against explicit requirements.
