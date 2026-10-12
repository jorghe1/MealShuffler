# Food artwork

## Runtime today: drawn dish forms

The app no longer ships category photographs. When a meal has no photo, `MealArtwork` shows a flat drawing from `DishIllustration` (`MealShuffler/Views/Components/DishIllustration.swift`): one picture per kind of dish (`DishForm` — fish fillet, soup, lasagne, taco, curry, stew and so on), chosen from the dish name in English or Norwegian, then its tags and ingredients. The drawings are code, so they stay sharp from 32-point thumbnails to the 220-point hero and keep their colours in dark mode. See [DESIGN.md](../../DESIGN.md#meal-artwork) for the full order and style rules.

Order for a meal: the household's own photo → the imported recipe photo → a per-dish asset override → the drawn dish form. The emoji is used only for non-cooking days.

## Adding a hand-made drawing for one dish

No code change is needed:

1. Export the drawing as a square image (PNG or JPEG, at least 660 × 660 px, opaque, on `#F7F2E6` paper so it matches the drawn set).
2. In `MealShuffler/Resources/Assets.xcassets`, add an image set named `Dish-` followed by the meal's id in upper case, for example `Dish-00000000-0000-0000-0000-000000000019` for Chili con carne. Built-in ids are in `MealShuffler/Data/SampleMeals.swift`.
3. Build. `MealArtwork` finds the asset with `UIImage(named:)` and fits it (whole dish visible) whenever that meal has no photo.

## Retired: eight category illustrations

Until this change, eight generated category JPEGs (`MealArtFish`, `MealArtChicken`, `MealArtMeat`, `MealArtVegetarian`, `MealArtPizza`, `MealArtPasta`, `MealArtSoup`, `MealArtTaco`) stood in for every dish. They were realistic but often wrong for the dish (every fish dish showed the same salmon fillet, chili con carne showed meatballs and mash), so they were removed from the asset catalog. The exact prompts are kept in [Generation-Prompts.md](Generation-Prompts.md); its "Runtime" paths are historical, and the images can be recovered from git history (commit `a5c4fe8`).
