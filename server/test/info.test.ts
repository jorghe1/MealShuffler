import assert from "node:assert/strict";
import test from "node:test";

import { handleRequest } from "../src/index.ts";
import { contactHTML, handleInfoPage, pickLanguage } from "../src/info.ts";

const env = {
  MODEL_BUDGET: { idFromName: (name: string) => name as never, get: () => ({ fetch: async () => new Response(null, { status: 204 }) }) as never },
  ANTHROPIC_API_KEY: "unused-in-tests",
  RATE_LIMITER: { limit: async () => ({ success: true }) },
  IP_RATE_LIMITER: { limit: async () => ({ success: true }) },
};

function get(path: string, acceptLanguage?: string, extra: Record<string, string> = {}) {
  return handleRequest(new Request(`https://svc.example${path}`, {
    headers: acceptLanguage ? { "accept-language": acceptLanguage } : {},
  }), { ...env, ...extra } as never);
}

test("privacy and support pages are public HTML in the requested language", async () => {
  const cases: [string, string | undefined, "en" | "nb", RegExp][] = [
    ["/privacy", undefined, "en", /<h1>Privacy policy<\/h1>/],
    ["/privacy?lang=nb", "en-GB", "nb", /<h1>Personvernerklæring<\/h1>/],
    ["/privacy?lang=en", "nb-NO", "en", /<h1>Privacy policy<\/h1>/],
    ["/privacy", "nb-NO,nb;q=0.9,en;q=0.8", "nb", /Gjelder fra: 9\. oktober 2026/],
    ["/support", "no", "nb", /<h1>Hjelp for Meal Shuffler<\/h1>/],
    ["/support", "nn-NO", "nb", /Påminnelsene kommer ikke/],
    ["/support", "en-US,en;q=0.9", "en", /<h1>Meal Shuffler support<\/h1>/],
    ["/support?lang=klingon", "de-DE", "en", /My reminders don&#39;t arrive/],
  ];
  for (const [path, acceptLanguage, language, heading] of cases) {
    const response = await get(path, acceptLanguage);
    const label = `${path} ${acceptLanguage}`;
    assert.equal(response.status, 200, label);
    assert.match(response.headers.get("content-type") ?? "", /^text\/html; charset=utf-8$/, label);
    assert.equal(response.headers.get("content-language"), language, label);
    assert.match(response.headers.get("vary") ?? "", /accept-language/i, label);
    assert.match(response.headers.get("content-security-policy") ?? "", /default-src 'none'/, label);
    const html = await response.text();
    assert.match(html, new RegExp(`<html lang="${language}">`), label);
    assert.match(html, heading, label);
    assert.doesNotMatch(html, /<script|<img|<link|https?:\/\/(?!apps\.apple\.com)/, `${label}: no scripts or external resources`);
  }
});

test("the privacy page states the facts App Review and users ask about", async () => {
  const html = await (await get("/privacy?lang=en")).text();
  for (const fact of [/Effective date: 9 October 2026/, /no advertising, no analytics and no tracking/,
    /does not use it to train its models/, /Anthropic's Claude/, /off until you turn it on in Settings/,
    /Bring!'s servers fetch/, /Manage\s+Storage/, /does not knowingly\s+collect personal information from children/]) {
    assert.match(html, fact);
  }
});

test("unknown paths still 404 and the info pages answer only GET", async () => {
  for (const path of ["/privacy/", "/privacy.html", "/supportx", "/nope"]) {
    // Unchanged routing: a GET to an unknown path is the extractor's 405 ("Use POST."), and a
    // POST to one is the 404.
    const response = await handleRequest(new Request(`https://svc.example${path}`, {
      method: "POST", headers: { "content-type": "application/json" }, body: "{}",
    }), env as never);
    assert.equal(response.status, 404, path);
  }
  assert.equal(handleInfoPage(new Request("https://svc.example/nope")), null);
  assert.equal(handleInfoPage(new Request("https://svc.example/privacy", { method: "POST" })), null);
  const head = handleInfoPage(new Request("https://svc.example/support", { method: "HEAD" }));
  assert.equal(head?.status, 200);
});

test("the contact line uses SUPPORT_EMAIL when set, the App Store otherwise, never an invention", async () => {
  const fallback = await (await get("/support?lang=en")).text();
  assert.match(fallback, /Contact us through the App Store page for Meal Shuffler\./);
  assert.doesNotMatch(fallback, /mailto:/);
  const norwegian = await (await get("/privacy?lang=nb", undefined, { SUPPORT_EMAIL: "" })).text();
  assert.match(norwegian, /Kontakt oss via App Store-siden for Meal Shuffler\./);

  const configured = await (await get("/privacy?lang=en", undefined, { SUPPORT_EMAIL: " help@example.org " })).text();
  assert.match(configured, /Email us at <a href="mailto:help@example\.org">help@example\.org<\/a>\./);

  assert.match(contactHTML("en", { appStoreURL: "https://apps.apple.com/app/id123" }),
    /<a href="https:\/\/apps\.apple\.com\/app\/id123">the App Store page for Meal Shuffler<\/a>/);
  for (const hostile of ["\"><script>alert(1)</script>@x.no", "not-an-address", "a@b", "javascript:alert(1)//@x.com"]) {
    const html = contactHTML("en", { supportEmail: hostile, appStoreURL: "javascript:alert(1)" });
    assert.equal(html, "Contact us through the App Store page for Meal Shuffler.", hostile);
  }
});

test("language negotiation follows q-values and falls back to English", () => {
  assert.equal(pickLanguage(null, null), "en");
  assert.equal(pickLanguage(null, ""), "en");
  assert.equal(pickLanguage(null, "de-DE, nb;q=0.8, en;q=0.5"), "nb", "first language we can serve");
  assert.equal(pickLanguage(null, "en;q=0.4, nb;q=0.9"), "nb");
  assert.equal(pickLanguage(null, "nb;q=0, en"), "en", "q=0 means not acceptable");
  assert.equal(pickLanguage(null, "fr, de"), "en");
  assert.equal(pickLanguage("NB", "en"), "nb");
  assert.equal(pickLanguage("no", "en"), "nb");
  assert.equal(pickLanguage("xx", "nb"), "nb", "an unknown ?lang= falls back to the header");
});
