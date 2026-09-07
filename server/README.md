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

## Deploy

```bash
cd server
npm install
npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler deploy
```

Then point the app at the deployed URL by setting `RecipeServiceBaseURL` in
`MealShuffler/Info.plist`. Leave it empty and the app silently stays on the local
parser, which is the correct behaviour before the service exists.

## Request

```jsonc
POST /v1/recipes/extract
X-Install-Id: <the app's DeviceIdentity UUID>

// exactly one of:
{ "url": "https://..." }
{ "text": "pasted recipe text" }
{ "imageBase64": "...", "imageMediaType": "image/jpeg" }
```

`X-Install-Id` is not authentication. It is an abuse key, so one misbehaving client can be
capped without affecting anybody else.

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

Extraction runs at `effort: "low"` — filling a fixed schema is not reasoning-heavy, and this
endpoint is the app's only per-call cost. If extraction quality disappoints, raise it to
`"medium"` in `src/index.ts` before reaching for anything else.

Rate limiting is 20 requests per minute per install, in `wrangler.toml`.

## Before real users

- Update `PrivacyInfo.xcprivacy` and the App Store data disclosure. Recipe text and photos
  leave the device the moment this is switched on.
- Anthropic is a data processor for anything sent here. For EU users that needs a processing
  agreement in place before launch, not after.
- Nothing is logged or stored today beyond Cloudflare's own request metrics. Keep it that
  way unless there is a reason not to, and say so in the privacy policy.
