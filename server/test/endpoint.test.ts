import { test } from "node:test";
import assert from "node:assert/strict";
import { clampRecipe, handleRequest, isJSONContentType, ModelBudget, OUTPUT_CAPS, rateLimitAddressKey } from "../src/index.ts";

const env = {
  MODEL_BUDGET: { idFromName: (name: string) => name as never, get: () => ({ fetch: async () => new Response(null, { status: 204 }) }) as never },
  ANTHROPIC_API_KEY: "unused-in-tests",
  RATE_LIMITER: { limit: async () => ({ success: true }) },
  IP_RATE_LIMITER: { limit: async () => ({ success: true }) },
};
const recipe = {
  name: "Soup", subtitle: "", emoji: "🍲", prepMinutes: null, activeMinutes: null, servings: null,
  ingredients: [{ name: "Salt", quantity: null, unit: "", aisle: "pantry", originalText: "Salt to taste",
    upperQuantity: null, section: null, packageQuantity: null, packageUnit: null }],
  instructions: ["Stir."], tags: ["soup"], confidence: "low",
};
function request(body: unknown, headers: Record<string, string> = { "content-type": "application/json" }) {
  return new Request("https://example.com/v1/recipes/extract", { method: "POST", body: JSON.stringify(body), headers });
}

test("only application/json reaches the limiters, the budget or the model", async () => {
  for (const contentType of [undefined, "text/plain", "text/plain;charset=UTF-8", "application/x-www-form-urlencoded",
    "multipart/form-data; boundary=x", "application/jsonp", "application/json-patch+json", "text/json"]) {
    let touched = 0;
    const counting = {
      ...env,
      RATE_LIMITER: { limit: async () => { touched++; return { success: true }; } },
      IP_RATE_LIMITER: { limit: async () => { touched++; return { success: true }; } },
      MODEL_BUDGET: { ...env.MODEL_BUDGET, get: () => ({ fetch: async () => { touched++; return new Response(null, { status: 204 }); } }) as never },
    };
    // A Request with a string body and no header gets `text/plain;charset=UTF-8`, which is
    // exactly the CORS-simple request a hostile page can send; delete it to test "missing".
    const unsent = request({ text: "Soup" }, contentType === undefined ? {} : { "content-type": contentType });
    if (contentType === undefined) unsent.headers.delete("content-type");
    const response = await handleRequest(unsent, counting, async () => { touched++; return recipe; });
    assert.equal(response.status, 415, String(contentType));
    assert.deepEqual(await response.json(), { error: "Unsupported media type.", code: "unsupported_media_type" });
    assert.equal(touched, 0, String(contentType));
  }
  for (const contentType of ["application/json", "application/json; charset=utf-8", "Application/JSON;charset=UTF-8", " application/json "]) {
    assert.equal(isJSONContentType(contentType), true, contentType);
    const response = await handleRequest(request({ text: "Soup" }, { "content-type": contentType }), env, async () => recipe);
    assert.equal(response.status, 200, contentType);
  }
  assert.equal(isJSONContentType(null), false);
});

test("IPv6 callers are keyed by their /64, IPv4 callers by address", () => {
  const sameNetwork = ["2001:db8:1:2:aaaa::1", "2001:db8:1:2:bbbb::9", "2001:0DB8:0001:0002:ffff:ffff:ffff:ffff",
    "[2001:db8:1:2::]", "2001:db8:1:2::1%eth0", "2001:db8:1:2:0:0:0:1"];
  for (const address of sameNetwork) assert.equal(rateLimitAddressKey(address), "2001:db8:1:2::/64", address);
  assert.notEqual(rateLimitAddressKey("2001:db8:1:3::1"), rateLimitAddressKey("2001:db8:1:2::1"));
  assert.equal(rateLimitAddressKey("2001:db8::1"), "2001:db8:0:0::/64");
  assert.equal(rateLimitAddressKey("::1"), "0:0:0:0::/64");
  assert.equal(rateLimitAddressKey("fe80::1:2:3:4"), "fe80:0:0:0::/64");
  assert.equal(rateLimitAddressKey("1:2:3:4:5:6:1.2.3.4"), "1:2:3:4::/64", "embedded IPv4 tail");
  // IPv4-mapped is an IPv4 caller and shares its bucket.
  assert.equal(rateLimitAddressKey("::ffff:1.2.3.4"), "1.2.3.4");
  assert.equal(rateLimitAddressKey("::FFFF:0102:0304"), "1.2.3.4");
  assert.equal(rateLimitAddressKey("0:0:0:0:0:ffff:1.2.3.4"), "1.2.3.4");
  assert.equal(rateLimitAddressKey("203.0.113.7"), "203.0.113.7");
  assert.equal(rateLimitAddressKey("unknown"), "unknown");
  // Not addresses: passed through rather than collapsed into somebody else's bucket.
  for (const odd of ["1::2::3", "2001:db8:1:2:3:4:5:6:7", "12345::1", "::ffff:1.2.3.999", "1:2:3:4:5:6:7"]) {
    assert.equal(rateLimitAddressKey(odd), odd.toLowerCase(), odd);
  }
});

test("the per-IP limiter receives the /64, not the full address", async () => {
  const keys: string[] = [];
  const recording = { ...env, IP_RATE_LIMITER: { limit: async ({ key }: { key: string }) => { keys.push(key); return { success: true }; } } };
  for (const address of ["2001:db8:1:2:aaaa::1", "2001:db8:1:2:bbbb::9", "198.51.100.4"]) {
    await handleRequest(request({ text: "Soup" }, { "content-type": "application/json", "cf-connecting-ip": address }), recording, async () => recipe);
  }
  assert.deepEqual(keys, ["2001:db8:1:2::/64", "2001:db8:1:2::/64", "198.51.100.4"]);
});

test("overlong cosmetic fields are clipped, not turned into a failed import", async () => {
  const chatty = {
    ...recipe,
    subtitle: "A".repeat(1000),
    emoji: "🍲 a hearty soup for cold evenings",
    tags: ["soup", "soup", "quick"],
    ingredients: [{ ...recipe.ingredients[0], unit: "u".repeat(100), originalText: "o".repeat(2000),
      section: "s".repeat(500), packageQuantity: 400, packageUnit: "p".repeat(100) }],
  };
  const response = await handleRequest(request({ text: "Soup" }), env, async () => chatty);
  assert.equal(response.status, 200);
  const output = await response.json() as typeof chatty;
  assert.equal(output.subtitle.length, OUTPUT_CAPS.subtitle);
  assert.equal(output.emoji, "🍲");
  assert.deepEqual(output.tags, ["soup", "quick"]);
  const [item] = output.ingredients;
  assert.equal(item.unit.length, OUTPUT_CAPS.unit);
  assert.equal(item.originalText.length, OUTPUT_CAPS.originalText);
  assert.equal(item.section!.length, OUTPUT_CAPS.section);
  assert.equal(item.packageUnit!.length, OUTPUT_CAPS.packageUnit);
});

test("clipping never splits an emoji and leaves short values alone", () => {
  const family = "👨‍👩‍👧‍👦"; // 11 UTF-16 units, one grapheme
  const clamped = clampRecipe({ ...recipe, subtitle: "x".repeat(199) + "🍲", emoji: family + family } as never);
  assert.equal(clamped.subtitle, "x".repeat(199), "A surrogate pair straddling the cap is dropped whole");
  assert.equal(clamped.emoji, family);
  assert.equal(clampRecipe({ ...recipe, emoji: "x".repeat(40) } as never).emoji, "", "A word is not an emoji");
  assert.deepEqual(clampRecipe(recipe as never), recipe);
});

test("malformed and ambiguous inputs never call the model", async () => {
  for (const body of [null, [], {}, { text: 42 }, { text: "" }, { images: [] },
    { url: "https://example.com", images: [{ data: "AAAA", mediaType: "image/jpeg" }] }]) {
    let calls = 0;
    const response = await handleRequest(request(body), env, async () => { calls++; return recipe; });
    assert.equal(response.status, 400);
    assert.equal(calls, 0);
  }
});

test("multiple pages and user context are passed together, unknown fields survive", async () => {
  let content: unknown;
  const response = await handleRequest(request({ text: "These pages are one recipe", images: [
    { data: "AAAA", mediaType: "image/jpeg" }, { data: "BBBB", mediaType: "image/png" },
  ] }), env, async input => { content = input; return recipe; });
  assert.equal(response.status, 200);
  assert.equal((content as unknown[]).length, 3);
  const output = await response.json() as typeof recipe;
  assert.equal(output.servings, null);
  assert.equal(output.ingredients[0].quantity, null);
});

test("actual body size is bounded without a Content-Length header", async () => {
  const response = await handleRequest(request({ text: "x".repeat(15_000_001) }), env,
    async () => { throw new Error("must not call model"); });
  assert.equal(response.status, 413);
});

test("rate limits reject before model calls", async () => {
  const response = await handleRequest(request({ text: "Soup" }), {
    ...env, IP_RATE_LIMITER: { limit: async () => ({ success: false }) },
  }, async () => { throw new Error("must not call model"); });
  assert.equal(response.status, 429);
});

test("empty recipes and negative amounts do not become successful imports", async () => {
  for (const invalid of [{ ...recipe, ingredients: [] }, { ...recipe, servings: -1 }]) {
    const response = await handleRequest(request({ text: "Soup" }), env, async () => invalid);
    assert.equal(response.status, 502);
  }
});


test("inverted ranges and incomplete package amounts are rejected", async () => {
  for (const ingredient of [
    { ...recipe.ingredients[0], quantity: 4, upperQuantity: 2 },
    { ...recipe.ingredients[0], quantity: 2, packageQuantity: 400 },
  ]) {
    const response = await handleRequest(request({ text: "Soup" }), env,
      async () => ({ ...recipe, ingredients: [ingredient] }));
    assert.equal(response.status, 502);
  }
});

test("global budget rejects before the model call", async () => {
  const response = await handleRequest(request({ text: "Soup" }), { ...env,
    MODEL_BUDGET: { ...env.MODEL_BUDGET, get: () => ({ fetch: async () => new Response(null, { status: 429 }) }) as never },
  }, async () => { throw new Error("must not call model"); });
  assert.equal(response.status, 429);
  assert.equal((await response.json() as { code: string }).code, "rate_limited");
});


test("global budget is shared, capped, resets on a new UTC day, and fails closed", async () => {
  let stored: { day: string; calls: number } | undefined;
  let tail = Promise.resolve();
  const state = { storage: { transaction: (operation: (tx: unknown) => Promise<boolean>) => {
    const result = tail.then(() => operation({ get: async () => stored, put: async (_key: string, value: typeof stored) => { stored = value; } }));
    tail = result.then(() => undefined);
    return result;
  } } };
  const budget = new ModelBudget(state as never, { ...env, DAILY_MODEL_CALL_LIMIT: "2" });
  const reserve = () => budget.fetch(new Request("https://budget/reserve", { method: "POST" }));
  const responses = await Promise.all([reserve(), reserve(), reserve()]);
  assert.deepEqual(responses.map(response => response.status), [204, 204, 429]);
  stored = { day: "2000-01-01", calls: 999 };
  assert.equal((await reserve()).status, 204);
  assert.equal(stored.calls, 1);
  const invalid = new ModelBudget(state as never, { ...env, DAILY_MODEL_CALL_LIMIT: "invalid" });
  assert.equal((await invalid.fetch(new Request("https://budget/reserve", { method: "POST" }))).status, 503);
});

test("budget service failures are availability errors, not daily-limit claims", async () => {
  const response = await handleRequest(request({ text: "Soup" }), { ...env,
    MODEL_BUDGET: { ...env.MODEL_BUDGET, get: () => ({ fetch: async () => new Response(null, { status: 503 }) }) as never },
  }, async () => { throw new Error("must not call model"); });
  assert.equal(response.status, 503);
  assert.equal((await response.json() as { code: string }).code, "unavailable");
});
