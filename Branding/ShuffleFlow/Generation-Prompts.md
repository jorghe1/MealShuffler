# Image generation record

Generated on 2026-09-15 using the built-in image_gen tool with the brandkit and imagegen skills. No CLI fallback.

## Initial shuffle direction

```text
Use case: logo-brand.
Design a distinctive finished app icon for "Meal Shuffler", a friendly, thoughtful dinner-planning app. The central idea MUST read immediately as SHUFFLE: two options exchanging places. No plate or circle metaphor.
Create a bold custom interwoven shuffle symbol from TWO broad flowing ribbons crossing in an X. Both travel left-to-right: one starts at upper left, curves smoothly down across the center and ends in a prominent arrowhead at lower right; the other starts at lower left, curves smoothly up across the center and ends in a prominent arrowhead at upper right. Each ribbon has confident smooth bends, substantial consistent visual weight, a blunt softly rounded starting tail, and a clear bold arrowhead integrated into its destination. The arrowheads point right, one at the upper-right and one at the lower-right. A small precise green separation at the crossing gives one path an over-under weave. The overall shape feels like dinner options swapping places, joyful controlled movement, and can hint at a compact monogram without sacrificing instant shuffle recognition. Not a recycling symbol and not a loop. No fragmented circular shapes.
Palette: solid forest green #1F6B47 background. Rising ribbon warm ivory #F7F2E6, descending ribbon light sage #D1E6CC. High contrast, only these three colors. A perfectly flat 2D graphic; no simulated 3D folding, shading, gloss, grain, gradient or shadow.
Composition: single centered symbol occupies roughly 66% of full square width and 58% of height; generous optical margins on all sides, balanced mass, equally weighted arrows. Icon must remain legible at 32 pixels. Pure opaque square full-bleed artwork, no pre-rounded corners, no border, no text or wordmark. Request 1024x1024.
Style: sophisticated Scandinavian consumer brand, precision geometry and generous negative space, approachable sculptural curves translated into crisp flat design. Be creative with the custom ribbon silhouette, avoid a thin generic toolbar glyph. No plates, dishes, food illustration, utensils, letters, dots, decorative sparkles, infinity symbols, circular arrows, mockup or background scene.
```

## Final icon refinement

The initial shuffle output had an unwanted transparent background. It was used as the edit reference for this refinement:

```text
Edit this shuffle-logo reference into a finished opaque app icon. Preserve the two broad crossing arrows, their smooth curves, cream upper-right arrow and sage lower-right arrow. Put the entire mark on a completely opaque solid forest-green #1F6B47 square background, fully filled all the way to all four edges. Absolutely no transparency anywhere: every pixel must be opaque, including the background and crossover gaps. The last output incorrectly lost its green background; restore it. Re-render the silhouette cleanly with smooth crisp edges and solid color fills, remove stray edge artifacts, grain and shadows. Keep the two arrows strongly legible with a clean narrow green over-under separation at their crossing. Center the mark at 66% canvas width with generous margins. Ivory #F7F2E6 and sage #D1E6CC arrows. No text, no rounded-square outer mask, no mockup, no plates. Deliver a full opaque green square icon.
```

Output: `Logo-Master.png`, the unchanged generated master. Production export: `../../MealShuffler/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-ShuffleFlow-v5.png`, proportionally resampled to 1024 × 1024 RGB using bicubic interpolation. `Icon-60.png` and `Icon-32.png` are size proofs. No geometry or colors were edited during export.

## Brand overview

Reference: the final shuffle logo master.

```text
Use case: logo-brand.
Create one premium brand-kit overview for "Meal Shuffler", a calm native family dinner planner. Use supplied image as the EXACT FINAL LOGO reference: two broad crossing shuffle arrows, cream rising from bottom-left to top-right, pale sage falling from top-left to bottom-right with a clear over-under separation, on forest green. Repeat this precise mark consistently; do not introduce any plate-shaped logos, circles, broken discs, infinity shapes, utensils or alternative identity.
4:3 aspect ratio, nine panels in a pristine 3 by 3 editorial grid on dark charcoal outer canvas, even wide gutters and calm negative space.
1 Logo cover: exact two-arrow reference mark and large wordmark "Meal Shuffler" on green.
2 Symbol logic: same exact crossing paths with very subtle construction lines, small label "A fresh mix". Emphasize swapping directions.
3 Digital concept application: cropped iPhone, warm cream native-looking app, small exact shuffle logo, large title "This week", two photo dinner rows titled "Salmon" and "Pasta". Extremely spare.
4 Quiet typographic panel: verbatim "Dinner plans itself." in large rounded humanist sans, forest on cream.
5 Palette: four broad swatches, forest #1F6B47, cream #F7F2E6, sage #D1E6CC, charcoal #1F291F. Only labels "Forest", "Cream", "Sage", "Ink".
6 Typography: rounded bold system-like sans "A thoughtful week." and regular sans "Simple, familiar, flexible."
7 Realistic minimal ivory meal-plan card on linen, exact shuffle logo printed in green and muted green. Brand name only; no invented extra slogan.
8 Editorial food photo: overhead simple weeknight meal of roasted salmon, potatoes, broccoli, natural light, cream ceramic dish, linen tabletop, authentic portions. Food photo may contain plates, but the logo never does.
9 Icon and utility: exact green app icon in a small home-screen-like application, quiet native-style calendar/cart/fork-and-knife symbols beneath. No extra text.
Warm practical Scandinavian food-brand world, precise restraint, crisp flat logos, gentle material texture only in photo/physical panels. Hierarchical, sparse, readable. No tiny fake UI text, generic glow, dense dashboard, random motifs, ornamental embellishments or glossy 3D logos. All product surfaces are illustrative identity applications.
```

Output: `Brand-Overview.png`. This is an identity direction board. Its product applications are illustrative, not screenshots of the running app. Generated typography, UI drawings and construction guides are not production assets or exact geometry specifications. Use the standalone logo master and existing SwiftUI typography/SF Symbols for implementation.

