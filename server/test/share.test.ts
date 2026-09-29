import assert from "node:assert/strict";
import test from "node:test";
import { deflateRawSync } from "node:zlib";
import { readFileSync } from "node:fs";

import { handleRequest } from "../src/index.ts";
import { bringListPage, decodeSharePayload, handlePublicPage, shareScript } from "../src/share.ts";

/** Encodes exactly as the app does: raw DEFLATE, base64url, version prefix. */
function encode(value: unknown): string {
  return "1." + deflateRawSync(Buffer.from(JSON.stringify(value))).toString("base64url");
}

const env = {
  MODEL_BUDGET: { idFromName: (name: string) => name as never, get: () => ({ fetch: async () => new Response(null, { status: 204 }) }) as never },
  ANTHROPIC_API_KEY: "unused-in-tests",
  RATE_LIMITER: { limit: async () => ({ success: true }) },
  IP_RATE_LIMITER: { limit: async () => ({ success: true }) },
};

test("decodes what the app encodes", async () => {
  const rules = { f: "The Hansens", r: [], l: ["We cook taco on Fridays."] };
  assert.deepEqual(await decodeSharePayload(encode(rules)), rules);
});

test("refuses malformed payloads", async () => {
  for (const payload of ["", "1.", "2.AAAA", "1.<script>", "1." + "A".repeat(70_000), "1.AAAAAAAA"]) {
    await assert.rejects(decodeSharePayload(payload), payload.slice(0, 12));
  }
});

test("a decompression bomb stops at the limit", async () => {
  const bomb = "1." + deflateRawSync(Buffer.alloc(2_000_000, 0x20)).toString("base64url");
  assert.ok(bomb.length < 20_000);
  await assert.rejects(decodeSharePayload(bomb), /too large/);
});

test("share pages are static, uncached, unindexed and locked down", async () => {
  for (const path of ["/s/rules", "/s/recipes"]) {
    const response = await handlePublicPage(new Request(`https://svc.example${path}`));
    assert.ok(response);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.match(response.headers.get("x-robots-tag") ?? "", /noindex/);
    assert.match(response.headers.get("content-security-policy") ?? "", /script-src 'self'/);
    const html = await response.text();
    assert.match(html, /<script src="\/s\/app\.js\?v=2"><\/script>/);
    assert.doesNotMatch(html, /apps\.apple\.com/, "No store link unless one is configured");
  }
  const withStore = await handlePublicPage(new Request("https://svc.example/s/rules"), "https://apps.apple.com/app/id123");
  assert.match(await withStore!.text(), /apps\.apple\.com\/app\/id123/);
  const hostile = await handlePublicPage(new Request("https://svc.example/s/rules"), "javascript:alert(1)");
  assert.doesNotMatch(await hostile!.text(), /javascript:/);
});

test("other requests fall through to the extractor", async () => {
  assert.equal(await handlePublicPage(new Request("https://svc.example/s/rules", { method: "POST" })), null);
  assert.equal(await handlePublicPage(new Request("https://svc.example/nope")), null);
  const extract = await handleRequest(new Request("https://svc.example/v1/recipes/extract"), env as never);
  assert.equal(extract.status, 405, "The extractor still only answers POST");
});

/** Just enough DOM to run the landing page's script. */
function fakeDocument() {
  const byID = new Map<string, any>();
  const make = (tag: string): any => ({
    tag, value: "", hidden: false,
    get textContent() { return this.value; },
    set textContent(value: string) { this.value = value; this.children = []; },
    removeAttribute(name: string) { delete this.attributes[name]; },
    className: "", attributes: {} as Record<string, string>, children: [] as any[],
    appendChild(child: any) { this.children.push(child); return child; },
    setAttribute(name: string, value: string) { this.attributes[name] = value; },
    get childElementCount() { return this.children.length; },
  });
  for (const id of ["content", "heading", "intro", "open", "get", "privacy"]) byID.set(id, make("div"));
  return { byID, document: { documentElement: { lang: "en" }, getElementById: (id: string) => byID.get(id) ?? null, createElement: make } };
}

async function runScript(path: string, fragment: string, language = "en-GB", nextFragment?: string) {
  const { byID, document } = fakeDocument();
  const scope = globalThis as any;
  const saved = { document: scope.document, location: scope.location, navigator: scope.navigator, addEventListener: scope.addEventListener };
  let hashchange: (() => void) | undefined;
  scope.addEventListener = (_: string, callback: () => void) => { hashchange = callback; };
  scope.document = document;
  scope.location = { pathname: path, hash: "#" + fragment };
  Object.defineProperty(scope, "navigator", { value: { language }, configurable: true });
  try {
    new Function(process.env.SHARE_SCRIPT_PATH ? readFileSync(process.env.SHARE_SCRIPT_PATH, "utf8") : shareScript())();
    await new Promise(resolve => setTimeout(resolve, 50));
    if (nextFragment !== undefined) {
      scope.location.hash = "#" + nextFragment;
      hashchange?.();
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    byID.set("html", document.documentElement);
  } finally {
    scope.addEventListener = saved.addEventListener;
    scope.document = saved.document;
    scope.location = saved.location;
    Object.defineProperty(scope, "navigator", { value: saved.navigator, configurable: true });
  }
  return byID;
}

test("the landing page renders rules as text and hands the link to the app", async () => {
  const fragment = encode({ f: "The Hansens", r: [], l: ["We cook taco on Fridays.", "<img src=x onerror=alert(1)>"] });
  const page = await runScript("/s/rules", fragment);
  assert.equal(page.get("heading").textContent, "House rules · The Hansens");
  const items = page.get("content").children[0].children[0].children.map((node: any) => node.textContent);
  assert.deepEqual(items, ["We cook taco on Fridays.", "<img src=x onerror=alert(1)>"], "Markup stays text");
  assert.equal(page.get("open").attributes.href, "mealshuffler://share/rules#" + fragment);
});

test("the landing page renders recipes, in Norwegian for a Norwegian browser", async () => {
  const fragment = encode({ f: "Familien Hansen", r: [{ n: "Lasagne", e: "🍝", p: 60, v: 4, i: [{ n: "Kjøttdeig", q: 400, u: "g", a: "meatAndFish" }], x: ["Stek."] }] });
  const page = await runScript("/s/recipes", fragment, "nb-NO");
  assert.equal(page.get("heading").textContent, "Fra Familien Hansen");
  assert.equal(page.get("open").textContent, "Åpne i Meal Shuffler");
  assert.equal(page.get("html").lang, "nb");
  const card = page.get("content").children[0];
  assert.ok(card.children.some((node: any) => node.textContent === "4 porsjoner"));
  assert.equal(card.children[0].textContent, "🍝 Lasagne");
  assert.ok(card.children.some((node: any) => node.children?.some((item: any) => item.textContent === "400 g Kjøttdeig")));
});

test("an unreadable link says so instead of rendering nothing", async () => {
  const page = await runScript("/s/rules", "1.garbage");
  assert.equal(page.get("intro").textContent, "This link could not be read. Ask for a new one.");
  assert.equal(page.get("open").hidden, true);
  assert.equal(page.get("open").attributes.href, undefined);
});

test("the shopping list becomes recipe markup Bring! can read", async () => {
  const html = await bringListPage(encode({ n: "Uke 39", i: ["600 g Laks", "2 stk Sitron", "</script><script>alert(1)</script>"] }));
  const jsonLD = /<script type="application\/ld\+json">(.*?)<\/script>/s.exec(html)?.[1];
  assert.ok(jsonLD);
  const recipe = JSON.parse(jsonLD);
  assert.equal(recipe["@type"], "Recipe");
  assert.equal(recipe.name, "Uke 39");
  assert.deepEqual(recipe.recipeIngredient.slice(0, 2), ["600 g Laks", "2 stk Sitron"]);
  assert.doesNotMatch(jsonLD, /<\/script>/, "An item can never close the script element");
  assert.doesNotMatch(html, /<script>alert/);
  await assert.rejects(bringListPage(encode({ n: "Empty", i: [] })));
});

test("the Bring! list is served uncached through the worker", async () => {
  const d = encode({ n: "Week", i: ["1 l Milk"] });
  const response = await handleRequest(new Request(`https://svc.example/v1/bring/list?d=${d}`), env as never);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const bad = await handleRequest(new Request("https://svc.example/v1/bring/list?d=nope"), env as never);
  assert.equal(bad.status, 400);
});


test("changing the fragment replaces content and invalid links remove the previous handoff", async () => {
  const first = encode({ l: ["First rule"] });
  const second = encode({ l: ["Second rule"] });
  const changed = await runScript("/s/rules", first, "en", second);
  assert.equal(changed.get("content").children.length, 1);
  assert.equal(changed.get("content").children[0].children[0].children[0].textContent, "Second rule");
  assert.ok(changed.get("open").attributes.href.endsWith(second));
  const invalid = await runScript("/s/rules", first, "en", "invalid");
  assert.equal(invalid.get("content").children.length, 0);
  assert.equal(invalid.get("open").hidden, true);
  assert.equal(invalid.get("open").attributes.href, undefined);
});

test("empty or oversized shares cannot masquerade as successful imports", async () => {
  for (const data of [{}, { r: [] }, { r: [{ n: "" }] }, { r: Array(25).fill({ n: "Dish" }) }]) {
    const page = await runScript("/s/recipes", encode(data));
    assert.equal(page.get("open").hidden, true);
  }
});

test("Bring refuses excess items and overlong lines without truncating the list", async () => {
  for (const items of [Array(251).fill("Milk"), ["a".repeat(201)], ["Milk", 12]]) {
    await assert.rejects(bringListPage(encode({ i: items })));
  }
  const page = await bringListPage(encode({ i: Array(250).fill("Milk") }));
  assert.equal((page.match(/<li>/g) ?? []).length, 250);
});
