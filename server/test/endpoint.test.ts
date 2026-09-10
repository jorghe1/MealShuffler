import { test } from "node:test";
import assert from "node:assert/strict";
import { handleRequest, ModelBudget } from "../src/index.ts";

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
function request(body: unknown) {
  return new Request("https://example.com/v1/recipes/extract", { method: "POST", body: JSON.stringify(body) });
}

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
