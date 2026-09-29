---
version: alpha
name: Meal Shuffler
description: A calm native iPhone companion for family dinner planning.
colors:
  primary: "rgb(12%, 42%, 28%)"
  background: "rgb(97%, 95%, 90%)"
  ink: "rgb(12%, 16%, 12%)"
  artwork-paper: "#F7F2E6"
typography:
  body:
    fontFamily: "system-ui, sans-serif"
rounded:
  card: "24px"
  control: "16px"
  chip: "12px"
  hero: "28px"
omitted:
  - section: spacing
    reason: SwiftUI layout remains context-specific; shared control sizes are owned by AppTheme.
  - section: components
    reason: Native component contracts and runtime mapping are documented below.
---

# Meal Shuffler design

## Overview

A familiar family recipe book with a useful weekly planner. This is a native product interface: food imagery carries warmth; controls stay familiar and quiet. The identity is the intact dinner plate with crossing shuffle arrows and simple cutlery in [Branding/DinnerShuffle](Branding/DinnerShuffle/README.md). This connects the planning action to dinner. The earlier ShuffleFlow mark is retained as a reference; the rejected split-plate direction remains archived.

Product facts and workflows come from [README.md](README.md), model/store implementation and [UX-CONTRACT.md](UX-CONTRACT.md). English and Norwegian Bokmål are supported; locale support does not imply a new market requirement.

## Colors

**Canonical owner: [AppTheme.swift](MealShuffler/Theme/AppTheme.swift).** This document mirrors its accepted light values; all UI components consume its semantic tokens. Preserve its adaptive dark values and on-accent foreground. Category and status colors retain their separate meaning.

Mapping: `AppTheme.background/accent → ci/sync-theme-colors.py → LaunchBackground/AccentColor.colorset → launch screen/native controls`. Generate with `python3 ci/sync-theme-colors.py`; check with `--check` during bootstrap. Do not edit exported assets independently.

`AppTheme.artworkPaper → MealArtwork` supplies the fixed cream illustration material. Like recipe photos, the artwork keeps its natural colors in both appearances; surrounding labels, cards and controls remain adaptive. Generated illustration pixels are not theme tokens.

## Typography

Use rounded system headings and standard system body text through Dynamic Type styles. Preserve English/Norwegian labels and readable line wrapping. Do not replace product type with raster lettering from the brand board.

## Layout

Keep native navigation, safe areas and existing scroll ownership. Artwork receives its size from its container: 44/56-point square thumbnails, a 230-point onboarding image and a 220-point detail hero. Onboarding text grows below the image and remains scrollable. A remote image must not change the frame or move actions as it loads.

## Elevation & Depth

Retain the existing card shadows and tonal surfaces. Food illustrations use restrained paper texture. Do not add shadows, gradients or large decorative emoji behind meal artwork.

## Shapes

Radius values above mirror native SwiftUI points: card 24, control 16, chip 12 and hero 28. `AppTheme` owns those runtime constants. Keep interactive hit areas at least the existing 44-point minimum.

## Components

- `MealArtwork`: imported photo first, bundled category illustration while missing/loading/failed, existing emoji for uncategorized custom meals or non-cooking states. Artwork is decorative and hidden from VoiceOver.
- `MealThumbnail`: the shared square wrapper for rows; delegates to `MealArtwork`.
- Onboarding, first-week rows, planner, library/history rows, recipe detail and import preview share that policy. Widgets and disabled community are separate follow-up work.
- Category artwork follows dish form before protein: pizza, pasta, soup, taco, fish, chicken, meat, vegetarian. This does not change planning/category data or the week-composition calculation.
- The eight bundled illustrations are category cues, not depictions of every recipe's exact ingredients. User/imported photos remain authoritative.
- Native SF Symbols remain functional icons. Keep labels for categories; use `fork.knife` for pizza/pasta/soup/taco rather than unrelated symbols.
- Like/dislike feedback sits on an adaptive solid surface so it stays readable over photos and illustrations.
- Preserve native buttons, alternate tap actions for swiping, existing Reduce Motion handling and localized accessibility labels.

## Do's and Don'ts

- Do use one artwork policy across meal surfaces and stable geometry during loading.
- Do derive exported launch/accent colors from the theme.
- Don't change household rules, persistence, import data or navigation for a visual fix.
- Don't treat generated mockups as evidence of native rendering. Verify changed surfaces in Xcode/iPhone before release.
