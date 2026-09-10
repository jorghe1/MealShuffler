# iCloud household sharing

The implementation uses the user's iCloud account and private CloudKit invitations. It does not introduce a separate sign-in service. It is implemented in source but has not been provisioned or tested with two Apple accounts in this environment.

## Unsigned simulator builds

The smoke workflow runs with `CODE_SIGNING_ALLOWED=NO`. That value is expanded into the
app's `CloudKitSigningAllowed` Info.plist entry. An unsigned build keeps household data local
and blocks CloudKit operations, even if its saved preferences previously enabled sharing.
The sync service creates its `CKContainer` lazily: observing the service during app launch
does not contact CloudKit or require CloudKit entitlements. Missing or unexpanded signing
configuration also leaves CloudKit unavailable.

Signed device builds use the normal `YES` signing setting and still require the iCloud
entitlements described below. This runtime setting does not replace Apple's provisioning.
The share sheet reuses the sync service's container. XCTest regressions cover unsigned
entry points and startup with sharing both enabled and disabled.

## Apple setup

1. In the Apple Developer account, associate the `no.mealshuffler.app` app ID with CloudKit container `iCloud.no.mealshuffler`. Keep the existing `group.no.mealshuffler.shared` App Group on the app and both extensions.
2. Enable iCloud/CloudKit for the app target and regenerate signing profiles. The checked-in app entitlement lists the container and CloudKit service; `Info.plist` includes `CKSharingSupported`.
3. Generate the project with `xcodegen generate`, choose the development team, and build the app, widget and share extension. The optional manual **iOS validation** GitHub workflow builds unsigned simulator targets and runs XCTest; it does not validate device entitlements.
4. Exercise sharing in the development CloudKit environment. The app creates a private custom zone named `MealShufflerHousehold`. The root is record type `Household`, record name `household`, field `state` (Asset). Source images are `RecipeImage` records with field `image` (Asset), a parent reference to the root and content-derived record names. A standard `CKShare` grants invited participants read/write access. No public permission is enabled.
5. Verify the schema in CloudKit Console and deploy the record schema to production before testing through TestFlight. Do not add public database access or a custom account/token service. TestFlight uses production CloudKit.

Apple references: [sharing CloudKit data](https://developer.apple.com/documentation/CloudKit/sharing-cloudkit-data-with-other-icloud-users), [sharing workflow walkthrough](https://developer.apple.com/videos/play/tech-talks/10874/), [cold-launch share metadata](https://developer.apple.com/documentation/uikit/uiscene/connectionoptions/cloudkitsharemetadata).

## Behavior and conflict policy

- Recipes and their source photos, current/next plans, archives, rules, members, preferences, favorites, shopping progress, shopping periods, collections, freezer inventory and household dinner time are shared.
- Cooking-step progress and notification settings stay on each device. Notification fields are neutralized in the uploaded transport and ignored on shared restores. Drafts, the capture inbox and recipe revision files remain local; full backups include them.
- Sync runs while the app is active, approximately every 30 seconds, and through **Sync now**. It is not background push sync. Offline edits remain on the device until sync succeeds. Opening the app refreshes its widget and notifications from locally persisted state.
- A local baseline plus CloudKit server change tags detect concurrent changes. If both sides changed, neither silently wins. The app shows both plan/shopping previews and requires choosing the household version to retain. This is a whole-household choice, not a per-field merge. Recovery packages retain the local version and, when replacing the shared version, the remote version and photos too.
- Accepting an invitation saves a recovery copy and presents the shared household for review before replacing local household data. **Pause on this device** stops its sync; it does not delete the household or revoke other participants. Manage invitations through Apple's sharing sheet.
- One household is connected per device. Existing local drafts and captures remain local when joining or restoring. A missing existing root is not silently recreated.

## Required two-account acceptance run

Use two signed-in physical iPhones and distinct Apple accounts. Record OS/build numbers and results.

1. Owner enables sharing, invites a participant, and participant accepts from both a terminated and an already-open app. Confirm the review screen and local recovery package.
2. Edit recipes, source photos, both weeks, preferences, collections and shopping checks in each direction. Confirm IDs, fractional quantities and photos survive and that personal timers/reminder preferences do not change on the other phone.
3. Disconnect both phones, change different data, reconnect, and verify a conflict is shown. Exercise both version choices, restore the losing version from a recovery package, and retry after a network interruption.
4. Consume a freezer batch, verify cross-week reservations, undo completion and check inventory on both phones.
5. Revoke a participant, pause/resume, sign out/switch iCloud accounts, and remove a shared root. Verify errors remain visible and unsynced local data is retained. Confirm a revoked participant cannot modify shared data.
6. Repeat with production schema through TestFlight. Check invitation links, quota/account errors and large photo libraries.

None of these device acceptance results is claimed as passed here.
