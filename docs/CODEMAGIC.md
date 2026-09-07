# Codemagic

Two workflows, and they are meant to be run in order.

| Workflow | Signs? | Needs Apple setup? | Answers |
|---|---|---|---|
| `ios-smoke` | No | **No** | Does it compile, and do the tests pass? |
| `ios-testflight` | Yes | Yes — App IDs, App Group, profiles | Can it go on a phone? |

`ios-smoke` builds with `CODE_SIGNING_ALLOWED=NO`. That matters more than it sounds: it means
you can find out whether ~5,700 lines of unbuilt Swift compiles **before** doing any work in
Apple Developer. Run it first, always.

## First run

1. In Codemagic, add the repository if it is not already there, and let it detect
   `codemagic.yaml`.
2. Enable the webhook when prompted. `ios-smoke` now triggers on push and pull request, so
   every branch builds on its own.
3. Start `iOS · Simulator smoke test` manually on the branch you want.

Nothing else is required for that first build. No certificates, no App IDs, no App Group.

### If it fails

Expect compile errors on the first run of a large unbuilt branch. The build log names the
file and line. The likely areas, in rough order:

- `Codable` conformances in `Meal` and `AppStateSnapshot`, which are hand-written.
- Concurrency annotations around `DinnerReminderService` and `RemoteRecipeExtractor`.
- `MealShufflerWidget` and `MealShufflerShare`, which XcodeGen has never generated before.
  A missing type in an extension usually means a source file needs adding to that target's
  list in `project.yml`, not that the code is wrong.

`ci/check-swift-structure.py` and `ci/check-store-api.py` run before XcodeGen and catch a
different class of problem — stale symbols, unbalanced braces, views calling store members
that no longer exist. They are not a type checker; the compiler is.

## Before the first TestFlight build

`ios-testflight` signs three bundles, so all three need to exist in Apple Developer:

| Bundle | Purpose |
|---|---|
| `no.mealshuffler.app` | The app |
| `no.mealshuffler.app.widget` | Home screen widget |
| `no.mealshuffler.app.share` | Share extension |

One-time setup:

1. Create the App Group `group.no.mealshuffler.shared` under Identifiers → App Groups.
2. Create all three App IDs, each with the **App Groups** capability enabled and that group
   selected.
3. Create the app record in App Store Connect for `no.mealshuffler.app`.
4. Regenerate provisioning profiles. The workflow fetches one per bundle id — see
   `BUNDLE_ID`, `WIDGET_BUNDLE_ID` and `SHARE_BUNDLE_ID` in `codemagic.yaml`.

Then tag a release:

```sh
git tag ios-0.2.0
git push origin ios-0.2.0
```

The tag triggers the workflow, which regenerates the project, runs the tests, signs, builds
the IPA and uploads it. Beta review is deliberately off; add the build to an internal
TestFlight group yourself.

### The failure that looks like a bug

If the App Groups capability is missing from any of the three App IDs, the app still runs and
still saves your week — it falls back to private storage. But the widget reads from the
shared container, finds nothing, and shows "No plan yet" forever regardless of what is
planned. There is no error anywhere. If the widget is stubbornly empty, check the capability
before you check the code.

## What the workflows do not cover

- **The v1 → v2 migration.** It only runs against real saved state, so it cannot be tested in
  CI. Install over an existing copy of the app on your own phone — not a clean install.
- **The extraction service.** `server/` deploys separately with `wrangler deploy`. With
  `RecipeServiceBaseURL` empty in `Info.plist` the app never calls it, which is the correct
  state until it is deployed.
