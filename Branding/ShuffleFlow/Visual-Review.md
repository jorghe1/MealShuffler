# Application visual review

15 September 2026 · Meal Shuffler

## Implementation update

The main findings below are now fixed in source:

- Eight bundled food-category illustrations cover all 40 built-in recipes. Onboarding no longer enlarges emoji over a gradient.
- `MealArtwork` shares photo priority, loading/failure fallback and bounded image sizing across onboarding, thumbnails, recipe detail and import preview. First-week rows now pass through the selected meal.
- Pizza/pasta/soup/taco labels use a neutral meal symbol instead of unrelated cross-grid, drink, coffee and flame symbols.
- LaunchBackground and AccentColor include dark appearances generated from `AppTheme`. Bootstrap checks for drift with `ci/sync-theme-colors.py --check`.

Validation: six repository static/localization/theme checks passed; asset validation confirmed eight opaque 768 × 768 images (778 KiB total) and category coverage for all 40 built-in meals. The frontend skill's strict static audit reports no findings. These are source checks, not a Swift compiler or native UI test. See [implementation notes](../FoodIllustrations/Verification.md).

In-app logo placement, widget image alignment and disabled community visuals remain follow-up items. The original findings below are retained as the review baseline.

## Assessment

The app already has a coherent foundation: warm cream backgrounds, adaptive green accents, rounded system headings, shared shape sizes and familiar native controls. The most noticeable identity weakness was the detailed app icon. The larger remaining opportunity is consistent meal imagery, especially on the first-run screens.

Scope: direct inspection of the former and new app icons, plus source inspection of the theme, asset catalog, onboarding, meal components, planner, editor, category symbols, tabs, widget and disabled community views. No running iPhone UI was available on this Windows host; layout judgments below identify source-level risks rather than observed rendering defects.

## Findings and next steps

| Priority | Surface and evidence | Assessment | Recommended action |
| --- | --- | --- | --- |
| Completed | App icon: former `AppIcon-GraphicDinner-v3.png` | Plate, salmon, vegetables, arrows, texture and dimensional shading compete within one small icon. | Replaced with two broad crossing shuffle arrows in cream and sage on green. The previous icon is archived. |
| High | [Onboarding TasteCard](../../MealShuffler/Views/Onboarding/OnboardingFlowView.swift), [sample meals](../../MealShuffler/Data/SampleMeals.swift) | The first food impression is a 112-point emoji with shadow on a gradient. The 40 built-in recipes have no `heroImageURL`, so the default experience cannot benefit from the photo-aware thumbnail component. Emoji also repeat across distinct dishes. | Give built-in meals a consistent set of locally bundled food photos or category illustrations. Use the same image-selection/fallback policy for onboarding, rows and recipe detail. Start with onboarding meals and reusable category coverage. |
| High | [LaunchBackground](../../MealShuffler/Resources/Assets.xcassets/LaunchBackground.colorset/Contents.json), [AccentColor](../../MealShuffler/Resources/Assets.xcassets/AccentColor.colorset/Contents.json), [AppTheme](../../MealShuffler/Theme/AppTheme.swift) | Both named color assets contain one appearance, while `AppTheme` defines light and dark values. The launch background is referenced by `Info.plist`; it can show a cream launch before the dark app. The global accent asset can also diverge from explicit themed controls. | Add dark appearance values matching the theme: launch/background `(0.07, 0.08, 0.07)` and accent `(0.44, 0.78, 0.58)`. Check launch-to-app continuity and native control contrast on device. |
| Medium | [MealTag.symbol](../../MealShuffler/Models/Meal.swift) | Pizza uses a cross-grid symbol, pasta a takeaway drink/bag, soup a cup and saucer, and taco a flame. These communicate different objects or meanings from their labels. | Keep text labels. Use one consistent family of category illustrations, or a neutral food symbol where a suitable native symbol is unavailable. Reserve flames for heat/spice. |
| Medium | [WelcomeStepView](../../MealShuffler/Views/Onboarding/OnboardingFlowView.swift), [empty widget](../../MealShufflerWidget/DinnerWidget.swift) | Identity surfaces use the same generic shuffle symbol as the product action. The app icon currently has no reusable in-app logo asset. | Add a separate template or vector rendition of the approved mark for welcome/about use. Keep SF Symbols for functional actions. Avoid enlarging or cropping the app-icon background into a template mark. |
| Medium | [MealThumbnail](../../MealShuffler/Views/Components/MealThumbnail.swift), [recipe hero](../../MealShuffler/Views/Planner/WeekPlanView.swift), [editor](../../MealShuffler/Views/Meals/RecipeEditorView.swift) | List thumbnails correctly prefer photos and clip to a square. Hero imagery has a separately implemented fallback and layout, increasing the chance of different crops and loading behavior. A filled remote photo needs a device check within the 220-point hero. | Introduce a shared meal-artwork view supporting thumbnail and hero sizes. Constrain the image frame before clipping; keep a stable fallback and check wide, tall, failed and missing images. Preserve users' own/imported photography. |
| Medium | [First-week rows](../../MealShuffler/Views/Onboarding/FirstWeekStepView.swift), [widget](../../MealShufflerWidget/DinnerWidget.swift) | First-week rows pass only emoji into `MealThumbnail`. Widgets render emoji directly. An imported meal may therefore show a photo in the planner and emoji elsewhere. | Pass the meal through to first-week thumbnails. For widgets, use a deliberate compact illustration style or share locally cached image data; avoid making the widget depend on a fresh remote image request. |
| Low | [Community views](../../MealShuffler/Views/Community/CommunityView.swift), [feature flags](../../MealShuffler/App/FeatureFlags.swift) | Community repeats large emoji/gradient treatments and uses a hard-coded yellow rating color. The feature is currently disabled. | Reuse shared artwork and a semantic rating color when this feature is enabled. This is not a current launch blocker. |

## Retain

- **Adaptive theme:** preserve `AppTheme.onAccent`, which accounts for the lighter dark-mode accent, plus the existing semantic warning and destructive colors.
- **Native navigation symbols:** the calendar, cart, fork/knife, sliders and gear provide useful recognition. Branding does not need to replace them.
- **Week composition:** the category palette has a text/count legend and an accessibility summary; it does not rely on color alone. Keep those separate category colors rather than forcing everything into brand green.
- **Shared shapes and spacing:** the card/control/chip/hero radius hierarchy already supports consistency. Avoid introducing a new visual scale with each artwork surface.
- **Photo fallback behavior:** `MealThumbnail` has a complete static fallback and hides decorative imagery from accessibility. Preserve that clarity when replacing emoji artwork.
- **System typography and motion preferences:** keep the existing Dynamic Type styles and Reduce Motion handling. The identity board does not justify fixed-size marketing typography throughout the app.

## Proposed visual rules

1. Identity uses the flowing shuffle mark; actions use native symbols; meals use photos or a consistent fallback illustration family.
2. Photo framing uses neutral plates, natural light and simple backgrounds. Distinguish actual dishes with content, not arbitrary tile colors.
3. Use one crop and fallback policy across each size class. Avoid mixing large emoji, photo cards and unrelated illustration styles on a single screen.
4. Keep the green/cream/sage identity in containers and controls. Let food provide natural color; retain semantic and category colors where they carry information.
5. Use the new board for direction. Its mockup labels and drawn utility icons are illustrative, not production copy or assets.

## Suggested implementation order

1. Verify the new installed app icon; align the named color assets with dark-mode tokens.
2. Establish shared meal artwork and add consistent built-in image coverage, starting with the onboarding deck.
3. Correct misleading category symbols and carry the identity into welcome/about surfaces.
4. Align first-week and widget imagery, then revisit community when it becomes active.

## Device review still needed

Check the home-screen icon at native size and with supported appearance treatments; onboarding and planner in light/dark modes; largest supported text sizes; imported portrait and landscape photos; missing/failed photos; and the small/medium widgets. Confirm that any new decorative imagery remains hidden from VoiceOver and does not displace labels or controls.
