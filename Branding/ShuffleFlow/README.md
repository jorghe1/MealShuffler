# Meal Shuffler — shuffle flow

Identity redesign and visual review · 15 September 2026

Superseded on 29 September 2026 by [DinnerShuffle](../DinnerShuffle/README.md), which adds a clear dining cue. These files and the v5 icon in LogoArchive are preserved as historical references; the active catalog now points to v6.

## Direction

Two broad paths cross and exchange positions. A cream rising arrow passes over a sage descending arrow, making shuffle the first reading. Rounded tails and flowing curves give the familiar action a warmer, more substantial silhouette.

The personality stays warm, calm and familiar: a useful family kitchen companion. Forest green connects the icon to the app's primary actions; cream connects it to the existing background. The existing “Dinner plans itself.” line carries the promise.

## Deliverables

- [Brand overview](Brand-Overview.png): nine-panel identity direction, including illustrative UI, typography, palette and photography applications.
- [Logo master](Logo-Master.png): original generated 1254 × 1254 RGB artwork.
- [Archived v5 iOS icon](../LogoArchive/AppIcon-ShuffleFlow-v5.png): 1024 × 1024 opaque RGB PNG, formerly connected in the app-icon asset catalog.
- Native-size proofs: [60 pixels](Icon-60.png) and [32 pixels](Icon-32.png).
- [Visual review](Visual-Review.md): source-backed findings and recommended next steps.
- [Generation prompts](Generation-Prompts.md): exact prompts, reference input and export details.

The previous v3 icon is preserved in [LogoArchive](../LogoArchive/AppIcon-GraphicDinner-v3.png). The rejected split-plate exploration is also archived there; it read as a broken plate and is not the current identity.

## Use of the identity

- Keep the full square artwork for the app-icon catalog; let the platform apply its mask.
- Preserve the arrows' proportions, direction, broad curves and over-under separation. Do not add food details to the crossing.
- Give the mark at least one ribbon-width of clear space outside its silhouette. The supplied icon already has generous margins.
- Use the logo for identity: launch materials, welcome and about surfaces. Keep the familiar shuffle action symbol on shuffle buttons.
- Use the existing rounded system headings and standard system body text in the app. The generated board's lettering is a visual reference, not a font asset.
- Use the existing adaptive `AppTheme` tokens for UI colors. The board palette targets are Forest `#1F6B47`, Cream `#F7F2E6`, Sage `#D1E6CC`, Ink `#1F291F`; generated pixels have subtle variation and should not be sampled as exact color definitions.
- Favor natural daylight, neutral plates, simple backgrounds and recognizable weeknight portions for future food photography.

## Implementation and validation

The initial identity change updated the app-icon asset and its catalog reference. A subsequent implementation pass fixed the main review findings: bundled meal artwork, shared image presentation, category symbols and dark launch/accent assets. See [the review update](Visual-Review.md) and [food artwork](../FoodIllustrations/README.md).

The production PNG was checked for 1024 × 1024 dimensions, RGB encoding without alpha, readable shape after reduction, and an existing filename matching the catalog entry. The previous icon's archived copy was verified against its Git version. `git diff --check` passed.

This Windows workspace cannot render the native SwiftUI app or run Xcode's asset compiler. The review uses source inspection and direct inspection of the image assets. An iPhone/simulator check of the installed icon, both appearances and larger text remains necessary before release. The board's product surfaces are concepts, not validation screenshots.
