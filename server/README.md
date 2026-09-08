# Recipe extraction service

One stateless Cloudflare Worker behind `POST /v1/recipes/extract`. No accounts, no database,
no stored user content.

It exists because the app's two import paths were its weakest code: link import broke on
character encoding, user-agent blocking and any page without schema.org markup, and photo
import turned a cookbook page into twelve junk shopping-list rows. The app keeps its
on-device schema.org parser as a fast path and only falls back to here, so an outage here
degrades import rather than breaking it.

## Why a server at all

The Anthropic API key cannot ship in the app. Anything inside an IPA is extractable, and a
leaked key is billed to you. The proxy also means the prompt can be fixed without an App
Store release, which matters for extraction quality far more than it sounds.

## What guards the model call

The model call is the only thing here that costs money, so two things stand in front of it.

**Rate limits, in order of how easy they are to dodge.** `X-Install-Id` is chosen by the
caller, so it is a courtesy limit — a fresh UUID per request walks straight past it. The
per-IP limiter is the one that holds. Both must pass.

**A fetch that will not go where it should not.** `POST {"url": ...}` makes this endpoint
fetch an address somebody else picked, from our account. So: https only, no credentials in
the URL, no private, loopback, link-local, carrier-NAT or multicast addresses, no raw IPv6
literals, no `.local`/`.internal`/`localhost`, and no cloud metadata host — **re-checked on
every redirect hop**, because a public host answering `302 -> http://169.254.169.254/` is the
entire trick. Redirects are followed manually and capped at four. The body is read through a
cap rather than buffered whole, the content type must be HTML or plain text, and the whole
fetch has a 10-second timeout.

Page text is fenced inside a `<SOURCE>` block and the system prompt says it is data, not
instructions. Structured output limits what a hostile page can do, but the extracted name and
steps land in somebody's meal library and their Reminders export, so the fence is worth having.

## Deploy

```bash
cd server
npm ci
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler deploy
```

Then point the app at the deployed URL by setting `RecipeServiceBaseURL` in
`MealShuffler/Info.plist`. Leave it empty and the app silently stays on the local
parser, which is the correct behaviour before the service exists.

## Checks

```bash
npm run check    # tsc --noEmit, then the unit tests
```

The tests cover the address rules, the redirect and size caps, the JSON-LD preference and the
source fence — the parts that can be got wrong quietly. They run on Node's built-in test
runner with runtime type stripping, so there is no build step and no test framework to
install. `tsconfig.json` covers `src/` only; the tests are checked by running them.

## Request

```jsonc
POST /v1/recipes/extract
X-Install-Id: <the app's DeviceIdentity UUID>

// exactly one of:
{ "url": "https://..." }
{ "text": "pasted recipe text" }
{ "imageBase64": "...", "imageMediaType": "image/jpeg" }
```

`X-Install-Id` is not authentication. It is an abuse key, and a weak one — see above.

## Response

```jsonc
{
  "name": "Fiskegrateng",
  "subtitle": "Med gulrotsalat",
  "emoji": "🐟",
  "prepMinutes": 40,
  "servings": 4,
  "ingredients": [
    { "name": "Torskefilet", "quantity": 600, "unit": "g", "aisle": "meatAndFish" }
  ],
  "instructions": ["Sett stekeovnen på 200 grader."],
  "tags": ["fish"],
  "confidence": "high",
  "heroImageURL": "https://..."
}
```

The shape is enforced by the model's structured output, so the client decodes a known type
rather than parsing prose. `tags` matters more than it looks: imported recipes previously
arrived untagged, so a rule like "fish on Tuesday" could never match one.

## Cost and tuning

Extraction runs `claude-opus-5` at `effort: "low"` — filling a fixed schema is not
reasoning-heavy, and this endpoint is the app's only per-call cost.

The largest lever is upstream of the model, not the model itself. Page text sent for
extraction is capped at 40,000 characters, down from 120,000: that was roughly 30k tokens of
stripped navigation, cookie notices and comment threads to read a recipe occupying two. When
the page carries a `Recipe` JSON-LD block, that block is sent instead of the page — a few
hundred tokens rather than tens of thousands.

Prompt caching is deliberately **not** used: the system prompt is a few hundred tokens, well
under the minimum cacheable prefix, so a breakpoint there would do nothing but look diligent.

If extraction quality disappoints, raise `effort` to `"medium"` in `src/index.ts` before
reaching for anything else.

A policy decline is handled explicitly (`stop_reason: "refusal"` becomes a 422 the app shows
in plain language, and `ChainedRecipeExtractor` then falls back to on-device OCR). Server-side
`fallbacks` would reroute such a request to another model instead; it is not wired up because
it requires the beta messages endpoint rather than the `messages.parse` helper this uses, and
recipe text rarely trips policy. Worth revisiting if refusals ever show up in practice.

## Dependency note

`@anthropic-ai/sdk` must be recent enough to have `messages.parse` and `helpers/zod`, and
`zod` must be v4 — the helper's types require it. The pins were `^0.71.0` and `^3.25.0`, which
predate both, so the committed source could not have compiled. Nothing in CI was running
`tsc`; there is now.

## Before real users

- Update `PrivacyInfo.xcprivacy` and the App Store data disclosure. Recipe text and photos
  leave the device the moment this is switched on.
- Anthropic is a data processor for anything sent here. For EU users that needs a processing
  agreement in place before launch, not after.
- Nothing is logged or stored today beyond Cloudflare's own request metrics, and the error
  path logs an error's name and status rather than its message, which can carry the request
  back out with it. Keep it that way unless there is a reason not to, and say so in the
  privacy policy.
- The per-IP limiter is a floor, not an identity. App Attest or DeviceCheck is the real
  answer if this ever gets popular enough to be worth abusing.
