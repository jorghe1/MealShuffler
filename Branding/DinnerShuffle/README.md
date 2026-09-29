# Meal Shuffler — DinnerShuffle

29 September 2026 · active app icon, v6

![DinnerShuffle logo](Icon-180.png)

An intact dinner plate holds two crossing shuffle arrows. A simple fork and knife make the meal context immediate. Forest green and warm cream keep continuity with the app; the mark has no lettering or tiny food details. The plate stays whole, avoiding the broken-plate reading of the archived v4 exploration.

## Files

- `Logo-Master.png`: untouched generated artwork, 1254 × 1254.
- `Icon-1024.png`: opaque RGB production export, copied into the app catalog as `AppIcon-DinnerShuffle-v6.png`.
- `Icon-180.png`, `Icon-60.png`, `Icon-32.png`: size proofs.
- `Generation-Prompt.md`: exact prompt and provenance.
- `Export-Icons.ps1`: repeatable size/format export using System.Drawing on Windows.

Use the square image without pre-rounded outer corners; iOS supplies the mask. Preserve the full composition and spacing. Keep SF Symbols for functional shuffle controls; this mark is identity artwork. Existing adaptive interface colors remain owned by `AppTheme`.

## Review

The generated master and the 60/32-pixel exports were visually inspected. At 60 pixels, dining and shuffle are clear. At 32 pixels, the plate and arrows remain recognizable; the rim and fork tines become secondary detail. The catalog filename, 1024-square dimensions, 8-bit RGB encoding without alpha, and file hash against the production export were checked.

This is generated raster artwork, not an editable vector master. Generated colors have slight tonal variation around the requested forest/cream palette. The installed iOS mask, asset compilation, and home-screen appearance still need an Xcode/device check.

The previous v5 icon remains intact in `Branding/LogoArchive`, and all earlier explorations are preserved. [App review](../../docs/APP_REVIEW_2026-09-29.md).
