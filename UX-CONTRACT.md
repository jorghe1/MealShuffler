# Native UI consistency contract

This records existing behavior relevant to the visual system. It does not introduce domain policy.

## Evidence and authority

- [README.md](README.md): product scope, local-first planning, imports and supported languages.
- [AppStore.swift](MealShuffler/Store/AppStore.swift): current action/state behavior.
- [RecipeEditorView.swift](MealShuffler/Views/Meals/RecipeEditorView.swift): edit/review and save behavior.
- [OnboardingFlowView.swift](MealShuffler/Views/Onboarding/OnboardingFlowView.swift): onboarding progression and taste actions.
- [RootView.swift](MealShuffler/Views/RootView.swift): navigation, generation state and app-level feedback.

## Preserved workflow behavior

| Surface | Trigger and state | Result/recovery |
| --- | --- | --- |
| Taste onboarding | Swipe or tap like/dislike; existing advancement guard | Records preference and advances. Existing undo/back and Reduce Motion behavior remain. |
| First week | Shuffle action invokes the existing planner | Same plan and rules behavior; artwork updates from the selected meal. |
| Meal rows/detail | Open a recipe | Existing navigation and cooking actions; decorative imagery adds no new interaction. |
| Recipe import/edit | Review imported content and save | Existing validation, draft and failure behavior stay in the editor; image failures never block editing. |
| Async images | URL is present; loading, success or failure | Frame stays stable. Success uses the photo; other phases use bundled category art or the existing uncategorized fallback. |

## Accessibility and locale

Keep native SwiftUI controls, localized labels, Dynamic Type, minimum hit targets and scrollable content. Decorative food images do not duplicate the meal title in VoiceOver. Status overlays retain text and solid backgrounds. Color is not the sole category/status cue.

## Scope boundary

Visual changes do not define new permissions, sharing, data retention, payments, deletion, synchronization or lifecycle rules. Those remain owned by the sources above and their referenced domain contracts.
