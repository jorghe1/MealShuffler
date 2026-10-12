# Codemagic

Two workflows. Neither has a `triggering` block: Codemagic never starts a build on its own.

| Workflow | Started by | Signs? | Needs Apple setup? | Answers |
|---|---|---|---|---|
| `ios-smoke` | Hand, in the Codemagic UI | No | **No** | Does it compile on Codemagic's Xcode image, and do the tests pass? |
| `ios-testflight` | Pushing a tag `ios-X.Y.Z` (through GitHub Actions), or by hand | Yes | Yes — App IDs, App Group, profiles | Can it go on a phone? |

`ios-smoke` builds with `CODE_SIGNING_ALLOWED=NO`, so it needs nothing from Apple Developer.
It is manual-only because GitHub Actions already answers the same question on every push:
`ios-validation.yml` builds and runs the unit tests for `main` and every `claude/**` branch,
and `checks.yml` runs the Python checks and server tests everywhere. Running `ios-smoke` on
every push as well only spent Codemagic minutes on the same answer.

## How a release starts

```
git push origin ios-0.6.1
        |
        v
GitHub Actions: .github/workflows/release-testflight.yml
  1. checks out the tag
  2. ci/check-release-tag.sh: ios-0.6.1 must equal MARKETING_VERSION in project.yml
  3. POST https://api.codemagic.io/builds  {appId, workflowId: "ios-testflight", tag}
  4. polls the build until Codemagic has picked it up (up to 10 minutes)
        |
        v
Codemagic: ios-testflight on the tag
  tag check again -> bootstrap -> unit tests -> build number from App Store Connect
  -> signing -> IPA -> upload to App Store Connect (TestFlight)
```

The Actions run prints the Codemagic build id and a link
`https://codemagic.io/app/<app id>/build/<build id>`, and puts both in the job summary. If the
tag does not match the version, Codemagic is not connected, or Codemagic rejects the request,
the run goes red on the tag's commit. A release can no longer disappear without a trace.

If Codemagic marks the build failed or canceled while the job is still watching (for example
its own tag check), the Actions run fails too. A build still queued after ten minutes (no free
Mac, concurrency limit) is reported as a warning; it stays queued and runs later.

### Why not a webhook

Codemagic's own tag trigger only fires when GitHub sends it a webhook. There is no webhook
between this repository and Codemagic (none under GitHub → Settings → Webhooks, none in the
Codemagic app), which is why pushing `ios-0.5.0` and `ios-0.6.1` built nothing. Earlier builds
were started by hand, or by a webhook that has since gone.

Adding the webhook back would work (see the alternative below), but it fails the same way
again: if it is deleted, loses access, or a delivery is dropped, nothing happens and nothing
says so. The API call runs in GitHub Actions, where it is visible on the tag, re-runnable with
one click, and checks the version before any Mac minutes are spent. The cost is one Codemagic
API token stored as a GitHub secret.

### One-time setup (needed before the next tag builds)

1. **Codemagic API token.** Codemagic → Team settings (or User settings for a personal
   account) → **Integrations** → **Codemagic API** → **Show**. Copy the token.
2. **App id.** Open Meal Shuffler in Codemagic. The address is
   `https://codemagic.io/app/<app id>/...`; copy the `<app id>` part (24 hex characters).
3. **GitHub.** Repository → Settings → **Secrets and variables** → **Actions**:
   - *Secrets* tab → New repository secret `CODEMAGIC_API_TOKEN` = the token.
   - *Variables* tab → New repository variable `CODEMAGIC_APP_ID` = the app id.
4. Build the tag that never built: Actions → **Release to TestFlight** → **Run workflow** →
   tag `ios-0.6.1`.

If either value is missing, the workflow fails and repeats these steps in its summary.

Optional: add `APP_STORE_APPLE_ID` (the numeric Apple ID under App Store Connect → App
Information) to the `ios_signing` group. `ci/set-build-number.sh` then skips looking the app
up by bundle id. It works without it.

### Alternative: the Codemagic webhook

If you would rather have Codemagic listen for tags itself:

1. Codemagic → the app → **Webhooks**: copy the webhook URL.
2. GitHub → Settings → **Webhooks** → Add webhook: paste the URL, content type
   `application/json`, and choose the events Codemagic lists (tags arrive as *push* events).
3. Put a `triggering` block (`events: [tag]`, `tag_patterns: ios-*`) back on `ios-testflight`
   **and** delete `.github/workflows/release-testflight.yml`. Keeping both builds every
   release twice, and the second upload is rejected as a duplicate build number.

### Releasing

1. Bump `MARKETING_VERSION` in `project.yml` and commit.
2. Tag that commit and push the tag:

   ```sh
   git tag ios-0.6.2
   git push origin ios-0.6.2
   ```

3. Follow the link in the Actions run (Actions → Release to TestFlight) to the Codemagic build.

To rebuild a tag — after fixing the secret, or after Codemagic failed for an unrelated reason
— use **Run workflow** with the tag name. Starting `iOS · TestFlight` by hand in the Codemagic
UI still works: on a tag it runs the same tag check; on a branch it skips the check with a
warning.

### Build numbers

`ci/set-build-number.sh` sets `CFBundleVersion` to

    max(latest TestFlight build number in App Store Connect + 1, PROJECT_BUILD_NUMBER)

`PROJECT_BUILD_NUMBER` is Codemagic's own counter for the app. It knows nothing about App Store
Connect: if the app is removed and re-added in Codemagic, or a build is uploaded from Xcode,
the counter lands on a number Apple already has and the upload is rejected — after a full
signed build. The script asks App Store Connect first (`app-store-connect apps list
--bundle-id-identifier no.mealshuffler.app --strict-match-identifier --json`, then
`app-store-connect get-latest-testflight-build-number <apple id> --all-versions`) with the API
key from the `fiks_app_store_connect` integration. If that lookup fails it warns and falls back
to `PROJECT_BUILD_NUMBER`, which is what every build used before. Keeping
`PROJECT_BUILD_NUMBER` as the floor means a stale answer can never move the number backwards.

## First run

1. In Codemagic, add the repository if it is not already there, and let it detect
   `codemagic.yaml`. You do not need the webhook it offers (see "Why not a webhook").
2. Start `iOS · Simulator smoke test` manually on the branch you want.

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

Then do the one-time setup under "How a release starts" and tag a release (see "Releasing").
The workflow regenerates the project, runs the tests, signs, builds the IPA and uploads it.
Beta review is deliberately off; add the build to an internal TestFlight group yourself.

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
