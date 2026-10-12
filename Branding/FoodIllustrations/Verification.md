# Visual fixes — implementation evidence

15 September 2026

## Changes

- Added eight category illustrations as asset-catalog image sets; all 40 built-in meals have category coverage.
- Introduced `MealArtwork` for imported photos, category fallback and stable image geometry. Thumbnails, onboarding, first-week rows, recipe detail and the editor's imported-photo preview use it.
- Kept uncategorized custom emoji and non-cooking day symbols as fallbacks. No persisted recipe data changed.
- Set the onboarding artwork area to 230 points while allowing the text/card to grow in the existing scroll view. Like/dislike badges have a solid adaptive background.
- Replaced unrelated pizza/pasta/soup/taco symbols with `fork.knife`, retaining their localized labels.
- Generated dark launch/accent variants from `AppTheme`; added an export/check script and wired the check into iOS bootstrap.

## Checks run on Windows

Using the bundled Python runtime:

- `ci/check-swift-structure.py`: 91 Swift files, no structural problems.
- `ci/check-swift-call-labels.py`: 91 files, no argument-label drift.
- `ci/check-store-api.py`: all 109 referenced store members exist.
- `ci/check-localized-format.py`: 891 literal-key calls matched.
- `ci/validate-localizations.py`: passed, 990 source keys and 1107 Norwegian entries.
- `ci/sync-theme-colors.py --check`: both exported light/dark color assets match the canonical theme.
- Asset inspection: eight valid opaque RGB JPEGs at 768 × 768; 778 KiB combined. Every asset name used by `MealArtwork` exists. All 40 built-in tag sets resolve to supported artwork categories.
- Frontend-design-premium strict audit: no findings; [JSON result](Static-Audit.json). Its web-oriented scan is supplemental and does not validate SwiftUI compilation.
- `npx --yes --package @google/design.md designmd lint DESIGN.md`: zero errors and warnings.
- `git diff --check`: passed.

The generated food artwork was visually inspected. No native application screenshots were produced.

## Native verification remaining

This host has neither Swift/Xcode nor an iOS simulator. Run `make test` on a configured Mac, then inspect onboarding with long English/Norwegian names and large Dynamic Type, light/dark launch continuity, planner/detail crops, remote photo loading/failure and custom uncategorized meal fallbacks. Confirm VoiceOver skips decorative imagery and the taste buttons remain reachable.

Widget artwork and the disabled community surfaces were not part of the three main findings fixed in this pass.
