> Status 2026-09-09: The follow-up implementation now includes multi-page import, source drafts,
> recipe versions/variants, library backup/restore, attendance, recurring weeks and safer rule
> enforcement. See [the implementation status](IMPLEMENTATION_STATUS_2026-09-09.md) for precise
> coverage, validation and remaining work. The service is still unconfigured in the app.

# Left out on purpose

Six things the app has been built up to and stopped short of. None of them is unfinished work
that got abandoned — each was left out for a reason, and each has the seams for it already cut.
They are in the order I would do them: the first is an afternoon and changes what the app can
do today, the last is a product in its own right.

Every entry says what it does for a household, what already exists, the steps, and how you
know it worked.

---

## 1. Deploy the recipe service

**What it does.** Import stops guessing. The on-device parsers read structured markup well and
prose badly; the service reads prose, photographs of cookbook pages, and pages that carry no
markup at all. It is the difference between "most recipe sites work" and "recipes work".

**Why it is not on.** It needs your Cloudflare account and an Anthropic API key, neither of
which can live in a repository. The Worker in `server/` is written, hardened and tested — it
has simply never been deployed, and `RECIPE_SERVICE_BASE_URL` is empty, so the app has always
fallen back to on-device parsing. That empty setting is why import used to look like it only
ever extracted the name.

**Steps.**

1. `cd server && npm ci`
2. `npx wrangler login` — opens a browser, authorises the CLI against your Cloudflare account.
3. `npx wrangler secret put ANTHROPIC_API_KEY` — paste the key; it is stored by Cloudflare, not
   in the repo.
4. `npx wrangler deploy` — prints the deployed URL, e.g. `https://recipe-service.<you>.workers.dev`.
5. Put that URL in `project.yml` under `settings.base.RECIPE_SERVICE_BASE_URL`, then
   `make open` to regenerate the project.
6. Optional but worth it: `npx wrangler tail` while you import a recipe, to watch the first
   real request go through.

**How you know it worked.** Import a link from a site with no schema.org markup — one that
reported "Fant ingen strukturert oppskrift" before. It should now come back with ingredients.
`ChainedRecipeExtractor` still falls back to on-device parsing if the service is down, so a bad
deploy degrades import rather than breaking it.

**Cost.** One `claude-opus-5` call at `effort: "low"` per import, plus Cloudflare's free tier.
A household importing a few recipes a week will not notice it.

---

## 2. The whole shopping list to Bring!

**What it does.** Sends the week's actual shopping list — aggregated across seven dinners,
scaled to the number of diners, minus pantry staples and minus what is already at home — into
Bring! in one tap. Today the app can only send a single recipe that came from a link, because
that is the only thing Bring's API accepts.

**The constraint.** Bring never takes a list of items. Both of its documented integrations —
the recipe-site button and the app-to-app deeplink — pass a **URL that Bring's own servers
fetch and parse**. It accepts a page with schema.org markup, or a file ending in `.json` in
Bring's import format. There is no inline payload, no POST of items, no URL scheme that takes a
list. (There is an unofficial API that takes Bring account credentials. That is not an option:
the app must never handle someone's password for another service.)

**So the only way through is to publish the list at a URL Bring can fetch**, which is a real
decision, not a detail. Today the app's whole privacy story is "everything stays on this
device". This would put a household's shopping list on the public internet, briefly, behind an
unguessable address.

**The design that makes that as small as possible.** Do not store the list. Let the Worker echo
it back:

1. Add `GET /v1/bring/list.json` to `server/src/`. It takes one query parameter, `d`: the
   list, compressed and base64url-encoded by the app.
2. The Worker decodes `d`, validates it against a small schema (name, quantity, unit — nothing
   else), and returns Bring's import JSON with `Cache-Control: no-store` and
   `X-Robots-Tag: noindex`. It writes nothing down and keeps nothing.
3. The app builds that URL from `store.groceryItems`, then opens
   `https://api.getbring.com/rest/bringrecipes/deeplink?url=<encoded>&source=web`.
4. Add the item to the export menu in `GroceryListView`, next to Apple Reminders.
5. Say plainly, once, in the confirmation: the list is sent to Bring to be read.

**What to check before building it.** URL length. Query strings are safe to a few kilobytes; a
week's list compresses well under that, but the app must count and refuse gracefully rather than
producing a truncated list. Test with a 7-dinner week for eight people.

**How you know it worked.** Tap it with Bring installed: Bring opens with the week's items
staged for confirmation, and the quantities match the app's list.

**The honest alternative, which costs nothing.** "Del som tekst" already puts the whole list on
the share sheet, and Bring's own share extension appears there. It is two taps rather than one,
needs no server, and nothing leaves the device except through the share sheet the user chose.

---

## 3. Prices, if a household actually wants them

**What it does.** Answers "what does this week cost" and lets a household cap it.

**Why it came out.** It was in, and it was removed on 2026-09-09, because none of the 40
built-in meals carries a price. Every figure came from four hardcoded guesses in
`planningCost` — 95, 120, 145 or 170 by tag — so "Cirka 900 kr i mat denne uken" was an invented
number presented as an estimate of real spend. A household compares that to one receipt and
stops trusting everything else the app says.

**What still exists.** `Meal.estimatedCost` is still on the model and still decodes, and
`planningCost` still orders the "Noe billigere" swap — relative ordering does not need a number
anyone sees. Nothing shows a price.

**Steps, if you want it back honestly.**

1. Put a real price on the built-in library, or accept that built-ins never show one.
2. Bring back the price field in `RecipeEditorView` (removed in the same change; see git
   history for the exact block).
3. Show the weekly total **only** when every cooked dinner that week has a price a person
   typed — never a total that mixes real figures with guesses.
4. Reintroduce `RuleConstraint.maximumCostPerWeek` and its generator arms, gated the same way.
   `LenientRule` in `AppStateRepository` means adding a case back is safe.
5. Consider whether it should be per-portion rather than per-meal; a household cooking for six
   compares badly against one cooking for three.

---

## 4. Community

**What it does.** Recipes from other households, with ratings, in a fifth tab.

**Why it is off.** `FeatureFlags.communityEnabled = false`. What exists is three seeded local
families, a rating that syncs nowhere, and a share sheet whose invitation link opens an alert
saying sync is not built. As a primary tab that costs more trust than leaving it out, and
polishing it would only make the wrong impression better executed. Publishing, rating and
reporting are all unsafe while anyone can act as anyone.

**Steps, in the order they have to happen.**

1. **Identity first.** Sign in with Apple, so a post has an author who can be held to it. Until
   this exists, nothing else on this list is safe to turn on.
2. **A backend for `CommunityRepository`.** The protocol is already the seam; the local
   implementation becomes a fixture for tests.
3. **Moderation before publication, not after.** The report flow exists in the UI and writes
   nowhere. It needs a queue, someone reading it, and a way to take a recipe down.
4. **Attribution.** `CommunityRepository` already carries the source URL through as
   `attribution`. Keep it visible on the published card — a recipe copied out of a magazine is
   somebody's work.
5. **Then** flip `communityEnabled`.

**Do not** flip the flag to demo it. A tab that looks real and does nothing is the single
clearest way to make the rest of the app look like a prototype.

---

## 5. Household sync

The September 10 implementation uses **Apple iCloud sharing**, selected by the user.
`CloudHouseholdSync` shares household snapshots and source-photo assets through a private
CloudKit zone and standard `CKShare` invitations. Local persistence remains available offline.
The old local invitation-code feature remains disabled.

Concurrent changes use a saved baseline and CloudKit server change tags. Both-sided edits
require an explicit version choice, with recovery packages preserving the losing data. This
is a whole-household conflict policy; automatic per-field merging remains a possible later
improvement. Sync currently runs while the app is active, not through background pushes.

Source implementation is present. Apple container provisioning, a signed build, two-account
acceptance and production schema validation remain release requirements. See
[ICLOUD_SHARING.md](ICLOUD_SHARING.md) and the current
[implementation status](IMPLEMENTATION_STATUS_2026-09-10.md).


## 6. Before real users

Small, unglamorous, and each one blocks a public release rather than a TestFlight build.

1. **`PrivacyInfo.xcprivacy` and the App Store data disclosure.** The moment the recipe service
   is switched on, recipe text and photos leave the device. Both files have to say so.
2. **A data processing agreement with Anthropic**, if there are EU users. Anthropic is a
   processor for anything sent to the service. This has to be in place before launch, not after.
3. **Keep the logs empty.** Nothing is stored today beyond Cloudflare's own request metrics, and
   the error path logs an error's name and status rather than its message — a message can carry
   the request back out with it. Keep it that way, and say so in the privacy policy.
4. **App Attest or DeviceCheck** on the recipe service. `X-Install-Id` is chosen by the caller,
   so it is a courtesy limit; the per-IP limiter is the real floor. That is fine until the app is
   popular enough to be worth abusing, and useless afterwards.
5. **A real privacy policy and support URL.** App Review asks for both.
