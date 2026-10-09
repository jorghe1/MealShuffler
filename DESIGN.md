---
version: alpha
name: Meal Shuffler
description: A calm native iPhone companion for family dinner planning.
colors:
  primary: "rgb(12%, 42%, 28%)"
  primary-soft: "rgb(82%, 90%, 80%)"
  on-primary: "rgb(100%, 100%, 100%)"
  background: "rgb(97%, 95%, 90%)"
  surface: "rgb(100%, 100%, 100%)"
  raised: "rgb(100%, 100%, 100%)"
  ink: "rgb(12%, 16%, 12%)"
  muted: "rgb(39%, 42%, 36%)"
  warning: "rgb(62%, 27%, 10%)"
  destructive: "rgb(78%, 22%, 20%)"
  artwork-paper: "#F7F2E6"
typography:
  body:
    fontFamily: "system-ui, sans-serif"
  display:
    fontFamily: "ui-rounded, system-ui, sans-serif"
    fontSize: "34px"
    fontWeight: 700
  title:
    fontFamily: "ui-rounded, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 700
  section:
    fontFamily: "ui-rounded, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 700
  eyebrow:
    fontFamily: "system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 700
    letterSpacing: "0.6px"
    textTransform: uppercase
rounded:
  card: "24px"
  control: "16px"
  chip: "12px"
  hero: "28px"
spacing:
  xxs: "2px"
  xs: "4px"
  s: "8px"
  m: "12px"
  l: "16px"
  xl: "24px"
  xxl: "32px"
  screen: "16px"
omitted:
  - section: components
    reason: Native SwiftUI component contracts and their runtime mapping are documented below.
---

# Meal Shuffler design

## Overview

A familiar family recipe book with a useful weekly planner. This is a native product
interface: food imagery carries warmth; controls stay familiar and quiet. The identity is the
intact dinner plate with crossing shuffle arrows and simple cutlery in
[Branding/DinnerShuffle](Branding/DinnerShuffle/README.md). Earlier marks are archived in
`Branding/LogoArchive` and `Branding/ShuffleFlow`.

Product facts come from [README.md](README.md) and the model/store code. How the code is
organised is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). English and Norwegian Bokmål are
supported; every visible string goes through localization.

**Canonical owner of every value below: [AppTheme.swift](MealShuffler/Theme/AppTheme.swift).**
The front matter mirrors its light-appearance values. If they disagree, `AppTheme` wins and
this file is updated.

## Tabs and where things live

Four tabs, in the order the week runs: plan, pick dishes, shop, and the family the rules
belong to. `AppRouter` owns the selected tab; notifications and widget links move it.

| Tab | View | What lives there |
| --- | --- | --- |
| **Uke** (Week) | `WeekPlanView` | Tonight on top, seven compact day rows (swipe to lock or redraw, tap for everything else), one shuffle button for whatever is unlocked, a this/next-week switch, active rules as chips where they shape the week. |
| **Retter** (Meals) | `MealLibraryView` | Photo grid with category filters, "Lengst siden sist" (history), freezer. "+" opens the five import sources: link, paste text, scan pages, photos, write it yourself. |
| **Handle** (Shop) | `GroceryListView` | Progress and an add-item field first. Bought and "har hjemme" fold away at the bottom. Export, shopping period, pantry staples and aisle order are in the ⋯ menu. |
| **Familie** (Family) | `FamilyView` | House rules, who eats and what each person likes, reminders, sharing. Settings (backup, recipe import, privacy) behind the gear. |

Phase 5 adds the kids view (Barnevisning) and, on iPad, the kitchen board (Kjøkkenmodus).
Record their entry points in this table when they merge. Community and iCloud sharing are
hidden behind `FeatureFlags`.

## Colors

All UI uses the semantic tokens. Each adapts to light and dark; never hard-code a colour in a
view.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `background` | 0.97 0.95 0.90 | 0.07 0.08 0.07 | Screen ground (`.appBackground()`). |
| `surface` | 1.00 1.00 1.00 | 0.12 0.13 0.12 | Cards. |
| `raised` | 1.00 1.00 1.00 | 0.17 0.19 0.17 | Chips and icon buttons that sit on a card. |
| `accent` | 0.12 0.42 0.28 | 0.44 0.78 0.58 | The one green: primary actions, selection, eyebrows. |
| `accentSoft` | 0.82 0.90 0.80 | 0.16 0.25 0.19 | Secondary buttons, soft fills. |
| `onAccent` | 1.00 1.00 1.00 | 0.05 0.10 0.07 | Text on `accent`. Not white in dark mode, for contrast. |
| `ink` | 0.12 0.16 0.12 | 0.91 0.94 0.91 | Body text. |
| `muted` | 0.39 0.42 0.36 | 0.63 0.68 0.62 | Secondary text. |
| `warning` | 0.62 0.27 0.10 | 0.92 0.58 0.38 | Something is wrong: conflicts, broken rules. |
| `destructive` | 0.78 0.22 0.20 | 0.95 0.48 0.44 | Delete and discard. |
| `artworkPaper` | #F7F2E6 | same | Fixed paper behind illustrations, like a photo. |

Category colours (`categoryFish`, `categoryChicken`, `categoryMeat`, `categoryVegetarian`,
`categoryOther`) are only for "what kind of food is this", such as the week composition bar.
They are not status colours, and colour is never the only cue.

Exported assets: `AppTheme.background/accent → ci/sync-theme-colors.py →
LaunchBackground/AccentColor.colorset`. Regenerate with `python3 ci/sync-theme-colors.py`;
`--check` runs in `ci/bootstrap-ios.sh`. Do not edit the colour sets by hand.

## Typography

System fonts through Dynamic Type; headings use the rounded design. Four roles in
`AppTheme.Typography`, nothing else for headings:

| Role | Font | Use |
| --- | --- | --- |
| `display` | largeTitle, rounded, bold | The one big heading on a screen without a navigation large title. |
| `title` | title2, rounded, bold | A card's main line: tonight's dinner, a sheet heading. |
| `section` | title3, rounded, bold | Section headings inside a screen. |
| `eyebrow` | caption, bold | Small capitals above a value ("I KVELD", "MAN 6"); use `.eyebrowStyle()`. |

Body text uses the standard text styles (`.body`, `.subheadline`, `.footnote`). Never use
raster lettering from the brand board for product text. Norwegian strings run longer than
English; let text wrap rather than truncate.

## Spacing and layout

`AppTheme.Space`: `xxs` 2, `xs` 4, `s` 8, `m` 12, `l` 16, `xl` 24, `xxl` 32, and `screen` 16
for the side margin of a scrolling screen. Use the scale rather than literals.

Keep native navigation, safe areas and existing scroll ownership. Artwork takes its size from
its container. A remote image must not change the frame or move actions as it loads.

## Shapes and sizes

| Token | Value | Use |
| --- | --- | --- |
| `cardRadius` | 24 | Cards: day plans, list groups, sheets. |
| `controlRadius` | 16 | Buttons, banners, inline panels on a card. |
| `chipRadius` | 12 | Small tiles and tokens. (Chips themselves are capsules.) |
| `heroRadius` | 28 | The one large image on a screen. |
| `tapTarget` | 44 | Minimum size of anything tappable. |
| `primaryAction` | 54 | The one prominent circular action on a screen. |
| `emojiTile` / `emojiTileCompact` | 56 / 44 | Emoji tiles on full and compact rows. |
| `rowThumbnail` | 40 | Picture on a compact row (week list, shopping hints). |

All radii use `.continuous` corners.

## Components

### Buttons

Three styles, by role. Pick by how much the action matters, not by looks.

- **`PrimaryButtonStyle`** — `.primary` (full width) and `.primaryCompact`. Filled `accent`,
  `onAccent` text, `.headline`, min height 50, `controlRadius`. The one main action of a
  screen or card. At most one per card.
- **`SecondaryButtonStyle`** — `.secondary` (fits content) and `.secondaryFullWidth`.
  `accentSoft` fill, `accent` text, `.subheadline` semibold, min height 44. Alternatives to the
  primary action, or the main action of something less important.
- **`IconButtonStyle`** — `.icon`, or `IconButtonStyle(prominent: true)` for an `accent` fill.
  44 pt circle on `raised`. Icon-only actions on cards and headers; always give it an
  accessibility label.

`.plain` remains for rows and cards that are tappable as a whole. Avoid `.bordered` and
`.borderedProminent` in new code; a few remain and should move to the styles above.

### Modifiers

- **`.mealCard()`** — `surface` fill, `cardRadius`, soft shadow (black 7 %, radius 18, y 8).
  The standard card.
- **`.chipStyle(selected:)`** — capsule pill, `.subheadline` semibold, min height 44; `accent`
  with `onAccent` when selected, `raised` with `ink` otherwise. Filters, rule chips, choices.
- **`.eyebrowStyle(color:)`** — eyebrow font, 0.6 tracking, uppercase, `accent` by default.
- **`.iconButtonFrame()`** — 44 × 44 hit area for an icon that is not a `Button` style.
- **`.appBackground()`** — `background`, ignoring safe areas.

### Meal artwork

`MealArtwork` is the single artwork policy for every meal surface: week rows, library grid,
history, recipe hero, onboarding, import preview, widget and share card. `MealThumbnail` is the
square wrapper for rows. The order is:

1. **Photo** — the meal's own photo (imported, taken by the household, or added after cooking).
   Always authoritative.
2. **Per-dish asset override** — an asset catalog image named `Dish-<meal uuid>`, for a
   built-in dish that has a drawn picture of its own.
3. **Drawn `DishIllustration` by dish form** — a flat illustration chosen by what the dish
   looks like on the plate. Dish form wins over protein: a vegetarian pizza is drawn as pizza,
   fish gratin as a baking dish, chili con carne as a bowl with beans.
4. **Emoji** — only for non-cooking days (eating out, leftovers, takeaway, no dinner), where
   the symbol carries the meaning.

`DishForm` has one drawing per form: fish fillet, fish cakes, casserole, soup, pasta, lasagne,
pizza, taco, wrap, noodles, curry, stew, meatballs, burger, sausages, roast chicken, steak,
salad, grain bowl, rice, omelette, porridge, pancakes and a plain plate. The form comes from
the dish name (English and Norwegian keywords), then dish tags (pizza, pasta, soup, taco), then
telling ingredients, then protein tags; a meal with none of these gets the plain plate. Colours
come from the name and ingredients: tomato sauce red, cream sauce pale, salmon pink, cod white.

Drawing style: top-down, plate or bowl rim in a darker paper tone with an ink outline (about
2 % of the size), bold simple food shapes, one recognisable feature per form (layers for
lasagne, beans for chili, chopsticks for noodles), at most four food colours. The drawing is
vector and centred on the shortest side; fine detail (grains, seeds) is left out below
60 points so 32-point thumbnails stay readable. See
[Branding/FoodIllustrations](Branding/FoodIllustrations/README.md) for adding a hand-made
override for one dish.

Rules for artwork:

- Artwork is decorative and hidden from VoiceOver; the meal title says what it is.
- Illustrations sit on `artworkPaper` and keep their colours in dark mode, like photos.
  Surrounding cards and labels stay adaptive.
- Photos fill and clip; illustrations fit, so a whole dish shows in landscape heroes.
- Frame size is fixed by the container before the image loads.
- No shadows, gradients, texture or large decorative emoji behind or inside artwork.
- SF Symbols are for functional icons. Use `fork.knife` for generic food, not an unrelated
  symbol.

### Other shared pieces

- Like/dislike feedback sits on a solid adaptive surface so it reads over photos.
- `SlotReel` is the shuffle animation; it respects Reduce Motion.
- `Haptics` is kept to a few physical moments: shuffle, each day landing, ticking an item in
  the shop, finishing a meal. No haptics for passive updates.

## Workflow contract

Visual changes must keep these behaviours. They are owned by the store and the views named,
not by this document.

| Surface | Trigger and state | Result and recovery |
| --- | --- | --- |
| Taste onboarding (`OnboardingFlowView`) | Swipe or tap like/dislike; existing advancement guard | Records the preference and advances. Undo/back and Reduce Motion behaviour remain. |
| First week (`FirstWeekStepView`) | Shuffle runs the normal planner | Same plan and rule behaviour as the Week tab; artwork follows the chosen meal. Notification permission is asked here, once the first week is on screen. |
| Week (`WeekPlanView`) | Shuffle, swipe to lock/redraw, pick a dish, day plan | Locked days survive shuffles. Shuffle, swaps, day plans and pauses can be undone in one tap. Conflicts are explained, not hidden. |
| Rules (`RuleComposer`, `RulesView`) | Typing a rule | The reading is shown back with understood words highlighted and ignored words listed before anything is saved. Duplicates and contradictions are refused with the rule they clash with. |
| Meal rows and detail | Open a recipe | Existing navigation and cooking actions; artwork adds no interaction. |
| Recipe import and edit (`RecipeEditorView`) | Review the draft and save | Validation, drafts and failures stay in the editor. Guessed content is marked for checking. Image failures never block editing. |
| Shopping (`GroceryListView`) | Tick, mark at home, add item | Bought and at-home items fold away, recoverable. Sending to Bring! asks once before anything leaves the phone. |
| Async images | URL present; loading, success or failure | Frame stays stable. Success shows the photo; any other phase shows the fallback from the artwork policy. |
| Notifications | Tap or action | Opens the right tab through `AppRouter`; "We cooked this" works from a cold launch. |

### Accessibility and locale

- Native SwiftUI controls, Dynamic Type, scrollable content, 44 pt minimum hit areas.
- Every icon-only control has a localized accessibility label.
- Decorative images do not repeat the meal title to VoiceOver.
- Status overlays keep text and a solid background. Colour is never the only cue.
- Light and dark appearance are both supported; test both.

### Scope boundary

Visual changes do not define permissions, sharing, data retention, payments, deletion,
synchronisation or lifecycle rules. Those belong to the store, the services and
[docs/PRIVACY.md](docs/PRIVACY.md).

## Do's and don'ts

- Do use the tokens, the three button styles and the shared modifiers.
- Do use one artwork policy across meal surfaces, with stable geometry while loading.
- Do derive exported launch and accent colours from the theme.
- Don't change rules, persistence, import data or navigation for a visual fix.
- Don't treat generated mockups as evidence of native rendering. Check changed screens on a
  simulator or iPhone, in both appearances and in Norwegian, before release.
