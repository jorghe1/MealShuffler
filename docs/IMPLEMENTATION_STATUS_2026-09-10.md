# September 10 review implementation

This follows [the September 10 review](APP_REVIEW_2026-09-10.md) and the request to implement its recommendations, including the selected **Apple iCloud sharing** account system. Changes are in the working tree. This is a source implementation report, not a device-release sign-off.

## Reliability findings

| Review item | Implemented behavior |
|---|---|
| 1–2: yield and timing | Yield requires an explicit yield line. Oven temperatures do not establish servings. Total and hands-on time are separate, including hours plus minutes and structured `prepTime`. Missing metadata requires review. |
| 3: starter amounts | Starter ingredients use cooking quantities rather than arbitrary whole condiment containers. Shopping and cooking scale from recipe yield. |
| 4: notification identity | Actions carry the dated meal; stale replace actions cannot change today's different dinner. Cooked events retain the intended date and recipe snapshot and are idempotent. |
| 5–6: week integrity | Both weeks are revalidated after relevant edits. Bulk remaining-week shuffle preserves past, completed and locked entries. Next-week choices are retained while new conflicts are exposed. |
| 7: household cleanup | Removing a person removes their preferences, attendance references and person-specific rules. Stale preferences are excluded on load and when scoring. |
| 8–9: exports and quantities | Recipe packages keep photos outside JSON and enforce read/write limits. Legacy JSON remains readable. Unknown amounts, ranges, packages and “to taste” remain distinct; malformed ranges/packages require correction. |
| 10: Reminders | Export updates app-owned reminders by shopping period and item ID, removing obsolete duplicates within that period while preserving unrelated reminders. |
| 11–12: replacements | Quicker/cheaper/favorite requests check whether the replacement meets the request; cost comparisons use cost per portion. Unmet requests preserve the dinner and explain why. Swaps preserve destination portions and reject completed/non-cooking arrangements. |
| 13: leftovers | Automatic sources consider remaining portions and exclusions. Allocation checks both weeks. Freezer choices retain a recipe snapshot; a missing batch stays unresolved instead of choosing an unrelated dinner. |
| 14–15: history/library | New cooking events and archives retain recipe snapshots; history uses planned dates. Starter recipes can be hidden and explicitly reset; deleting a customization does not resurrect its starter unexpectedly. |
| 16: rules | Existing rules are editable; recurring schedules have normalized duplicate detection and next-active-week display. Household dislike actions report duplicate/conflict outcomes. |
| 17–18: onboarding/capture | Skip/Neutral, visible portions, cancellable guarded card advances and scrolling address onboarding friction. Captures are independent durable files; app/extension migration is coordinated. |

## UI, UX and additions

- Today has a prominent recipe/cooking entry and completion state. Current and next weeks share cards, searchable selection, recipe details, day settings, conflict repairs and undo.
- Day attendance updates the diner count, with explicit guest adjustments and fractional portion sizes. Away days hide irrelevant controls. Cooking totals include extras; leftover/takeaway totals describe portions needed.
- Rule creation starts with four common templates. Additional templates and recurrence are disclosed progressively. A complete sentence previews the saved rule; weekly category counts explicitly concern cooking, with previous-week consecutive-day validation.
- The library has one **Add recipe** menu, category/label/time/collection/review filters, sorting, editable ingredients, numeric metadata and zoomable sources. Drafts store image references; stale asynchronous saves cannot overwrite newer drafts or resurrect a saved recipe's draft.
- Cooking retains steps/gathered ingredients and offers a step overview and timer. It explains that numbers embedded in the original method text are not rescaled.
- Shopping supports date ranges and current/next/archived coverage, period-specific checks, remaining/all/completed views, manual editing, incomplete-recipe warnings and distinct already-owned/done states. Increasing quantities reopens insufficiently checked items, including after switching periods.
- Freezer batches work across weeks, reserve portions and avoid adding their ingredients to groceries again. Consumption and undo keep inventory consistent. Named recipe collections are included.
- History opens recipe details, exposes favorite/plan actions, and includes the full retained rotation and archived weeks. Settings separates household, notifications, data and dinner time.
- Accessibility changes include larger hit areas, wrapping/adaptive controls, corrected semantic labels and selection traits, darker warning text, scrollable onboarding and reduced-motion alternatives. Actual maximum Dynamic Type, VoiceOver, contrast and screen layouts still require device verification.
- Full `.mealbackup` packages contain household state plus local recipes, drafts, revisions, capture metadata and source images. Restore first saves a recovery package; failed state writes roll back in-memory state. Existing local drafts/captures are retained when files are restored. Unused source-photo cleanup accounts for live recipes, tombstones, drafts, revisions, archives, cooking snapshots and freezer snapshots, with a seven-day grace period.
- iCloud sharing uses private invitations, source-photo assets, foreground retries, change-tag conflict protection and recoverable explicit version choices. See [setup and acceptance steps](ICLOUD_SHARING.md).
- Optional online extraction is visibly opt-in and leaves local parsing available. Stable error codes have localized explanations. A transactional daily global cap limits model-call attempts independently of client identifiers; aggregate status/latency logs omit recipe contents.

## Norwegian editorial rules

Use complete localized sentence templates, not concatenated menu tokens. The reported case now reads **“Vi bestiller takeaway på mandager.”** Cooking, takeaway, leftovers and away each use their own verb. Scope phrases are `på mandager`, `på hverdager`, `i helgene` and `hver dag`. Names and recipe titles retain their capitalization. Singular quantities, Norwegian unit forms and dynamic stocked headings are localized.

Use `du` for the person operating the phone and `dere` for the household; `rett` for a dinner choice, `oppskrift` for its ingredients/method, `ukeplan` for the dated plan, and `Må følges` / `Bør følges` for strength. Avoid backend/onboarding/scoring terminology in ordinary user copy. Obsolete allergy assurances were removed.

## Validation and remaining release work

- Server: TypeScript checking and **21 tests passed**, including malformed input, amount validity, rate limits, transactional global caps, UTC-day reset and service failures. Tests substitute the model; no paid/live extraction was invoked.
- Repository: all five Python checks passed for structure, call labels, store API, localized format arguments and Norwegian coverage (**989 detected source keys; 1,106 Norwegian entries**). `git diff --check` passed. Property lists, entitlements and privacy manifests parsed successfully. An additional tree-sitter parse inspected all 89 Swift sources. These checks do not establish Swift type correctness or rendered UI behavior.
- The repository now contains **171 XCTest methods**. XCTest additions cover the reported language/metadata failures, wrapped lines and recipe identity, fractional quantities, leftovers/freezer capacity and undo, stale/duplicate actions, removed members, next-week reconciliation, shopping-period increases, draft write ordering and backup round-trips.
- A fixed synthetic English/Bokmål metadata corpus is embedded in `ReviewImplementationTests.testFixedEnglishAndNorwegianMetadataCorpus`; additional parsing tests cover scoped microdata, related recipes, packages and wrapped amounts. These are regression fixtures, not a measured real-world OCR accuracy score.
- **Not executed here:** Xcode compilation, XCTest, app/widget/share-extension integration, UI snapshots, real OCR image-corpus benchmarking, performance profiling and two-account iCloud sharing. This workspace is on Windows with no Swift/Xcode/iOS runtime. A manual [iOS validation workflow](../.github/workflows/ios-validation.yml) now provides a build/test entry point; it has not been dispatched.
- Before release, follow the iCloud provisioning and two-device test document, run the manual macOS workflow or equivalent local Xcode tests, and review narrow-screen/large-type/VoiceOver/Reduced Motion flows on a physical iPhone. Profile large libraries and five-page imports: bulk planning and draft persistence run in the background, while some targeted planning, backup restore and source-review operations still perform synchronous work.
- Before enabling a deployed online service, verify the configured URL, actual model availability, timeout behavior, schema, costs and quality on the same consented English/Bokmål source corpus. Record correct identity, yield, total time, ingredient amounts/units, latency and correction effort; offline/local success is not evidence of online quality.

Public community, nutrition claims, automatic budget optimization and broad natural-language rules remain deferred as recommended in the review. No commit, push, deployment, invitations or paid model requests were performed by this implementation pass.
