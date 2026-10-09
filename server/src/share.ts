/**
 * Public, stateless pages: share links opened by someone without the app, and the week's
 * shopping list served in a shape Bring! can import.
 *
 * Neither writes anything down. A share link carries its payload after the `#`, which a
 * browser never sends to a server: this Worker serves the same static page for every share,
 * and the page decodes the fragment itself. The Bring! list does pass through here, because
 * Bring's servers must fetch it from a URL -- it is decoded, echoed back as recipe markup and
 * forgotten, with `no-store` so no cache keeps it either.
 */

/** Payload format shared with the app: `1.` + base64url(raw DEFLATE(JSON)). */
const PAYLOAD = /^1\.[A-Za-z0-9_-]{2,60000}$/;
const MAX_DECODED_BYTES = 1_000_000;

/**
 * Decodes a payload. Self-contained on purpose: the landing page's script is this very
 * function's source, so browser and tests run the same code.
 */
export async function decodeSharePayload(fragment: string, limit = 1_000_000): Promise<unknown> {
  if (!/^1\.[A-Za-z0-9_-]{2,60000}$/.test(fragment)) throw new Error("unreadable");
  const base64 = fragment.slice(2).replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    // A decompression bomb stops here rather than filling memory.
    if (total > limit) { await reader.cancel(); throw new Error("too large"); }
    chunks.push(value);
  }
  const joined = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { joined.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder().decode(joined));
}

const SECURITY_HEADERS = {
  "cache-control": "no-store",
  "x-robots-tag": "noindex, nofollow",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
};

export function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;",
  })[character] as string);
}

export const PAGE_STYLE = `
:root { color-scheme: light dark; --paper: #f7f2e6; --ink: #1f291f; --muted: #636b5c; --green: #1f6b47; --soft: #d1e6cc; --card: #fff; }
@media (prefers-color-scheme: dark) { :root { --paper: #121412; --ink: #e8f0e8; --muted: #a1ad9e; --green: #70c794; --soft: #29402f; --card: #1f211f; } }
* { box-sizing: border-box; }
[hidden] { display: none !important; }
h1, h2, li { overflow-wrap: anywhere; }
body { margin: 0; background: var(--paper); color: var(--ink); font: 17px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
main { max-width: 560px; margin: 0 auto; padding: 28px 16px 48px; }
.brand { display: flex; align-items: center; gap: 8px; color: var(--green); font-weight: 700; font-size: 13px; letter-spacing: .08em; text-transform: uppercase; }
.brand span { display: inline-grid; place-items: center; width: 26px; height: 26px; border-radius: 50%; background: var(--green); color: var(--paper); }
h1 { font-size: 30px; line-height: 1.15; margin: 10px 0 6px; }
p { color: var(--muted); margin: 0 0 18px; }
.card { background: var(--card); border-radius: 22px; padding: 16px 18px; margin: 12px 0; box-shadow: 0 8px 24px rgba(0,0,0,.06); }
.card h2 { font-size: 19px; margin: 0 0 4px; }
.card ul, .card ol { margin: 8px 0 0; padding-left: 20px; }
.rule { font-weight: 600; }
.actions { display: grid; gap: 10px; margin-top: 22px; }
a.button { display: block; text-align: center; padding: 15px; border-radius: 16px; font-weight: 700; text-decoration: none; }
a.primary { background: var(--green); color: var(--paper); }
a.secondary { background: var(--soft); color: var(--green); }
small { color: var(--muted); display: block; margin-top: 18px; }
`;

const COPY = {
  en: {
    loading: "Opening…", unreadable: "This link could not be read. Ask for a new one.",
    rules: "House rules", recipes: "Recipes", from: "From", open: "Open in Meal Shuffler",
    get: "Get Meal Shuffler", minutes: "min", servings: "servings", ingredients: "Ingredients", steps: "Method",
    rulesIntro: "Add these rules and shuffle a week that follows them.",
    recipesIntro: "Add these to your meals, or cook straight from this page.",
    privacy: "Everything on this page travelled inside the link. Nothing was uploaded or stored.",
  },
  nb: {
    loading: "Åpner …", unreadable: "Denne lenken kunne ikke leses. Be om en ny.",
    rules: "Husregler", recipes: "Oppskrifter", from: "Fra", open: "Åpne i Meal Shuffler",
    get: "Last ned Meal Shuffler", minutes: "min", servings: "porsjoner", ingredients: "Ingredienser", steps: "Fremgangsmåte",
    rulesIntro: "Legg til reglene og stokk en uke som følger dem.",
    recipesIntro: "Legg dem til i rettene dine, eller lag mat rett fra denne siden.",
    privacy: "Alt på denne siden lå i selve lenken. Ingenting ble lastet opp eller lagret.",
  },
};

/** Builds the page from decoded data with `textContent` only: the payload is untrusted. */
function renderShare(kind: string, data: any, copy: typeof COPY.en): void {
  // Reached through globalThis because the Worker's own types have no DOM; this only ever
  // runs in the browser, as part of the landing page's script.
  const doc = (globalThis as any).document;
  const root = doc.getElementById("content");
  const heading = doc.getElementById("heading");
  const intro = doc.getElementById("intro");
  root.textContent = "";
  const element = (tag: string, text?: string, className?: string) => {
    const node = doc.createElement(tag);
    if (text !== undefined) node.textContent = text;
    if (className) node.className = className;
    return node;
  };
  const from = typeof data?.f === "string" && data.f ? `${copy.from} ${data.f}` : "";
  if (kind === "rules") {
    if (!Array.isArray(data?.l) || !data.l.length || data.l.length > 30
        || data.l.some((line: unknown) => typeof line !== "string" || !line.trim())) throw new Error("unreadable");
    heading.textContent = from ? `${copy.rules} · ${data.f}` : copy.rules;
    intro.textContent = copy.rulesIntro;
    const card = element("div", undefined, "card");
    const list = element("ul");
    for (const line of Array.isArray(data?.l) ? data.l.slice(0, 30) : []) {
      if (typeof line === "string") list.appendChild(element("li", line, "rule"));
    }
    card.appendChild(list);
    root.appendChild(card);
  } else {
    if (!Array.isArray(data?.r) || !data.r.length || data.r.length > 24
        || data.r.some((recipe: any) => typeof recipe?.n !== "string" || !recipe.n.trim()
          || (recipe.i !== undefined && (!Array.isArray(recipe.i) || recipe.i.length > 200))
          || (recipe.x !== undefined && (!Array.isArray(recipe.x) || recipe.x.length > 200)))) throw new Error("unreadable");
    heading.textContent = from || copy.recipes;
    intro.textContent = copy.recipesIntro;
    for (const recipe of Array.isArray(data?.r) ? data.r.slice(0, 24) : []) {
      if (typeof recipe?.n !== "string") continue;
      const card = element("div", undefined, "card");
      card.appendChild(element("h2", `${typeof recipe.e === "string" ? recipe.e + " " : ""}${recipe.n}`));
      if (typeof recipe.p === "number" && recipe.p > 0) card.appendChild(element("p", `${recipe.p} ${copy.minutes}`));
      if (Number.isInteger(recipe.v) && recipe.v > 0 && recipe.v <= 100) card.appendChild(element("p", `${recipe.v} ${copy.servings}`));
      const ingredients = element("ul");
      for (const item of Array.isArray(recipe.i) ? recipe.i.slice(0, 200) : []) {
        const text = typeof item?.o === "string" && item.o
          ? item.o
          : [item?.q > 0 ? String(item.q) + (item.r > item.q ? "–" + item.r : "") : (typeof item?.an === "string" ? item.an : ""),
              typeof item?.u === "string" ? item.u : "",
              item?.pq > 0 && typeof item.pu === "string" ? `× ${item.pq} ${item.pu}` : "",
              typeof item?.n === "string" ? item.n : ""].filter(Boolean).join(" ");
        if (text) ingredients.appendChild(element("li", text));
      }
      if (ingredients.childElementCount) {
        card.appendChild(element("strong", copy.ingredients));
        card.appendChild(ingredients);
      }
      const steps = element("ol");
      for (const step of Array.isArray(recipe.x) ? recipe.x.slice(0, 200) : []) {
        if (typeof step === "string") steps.appendChild(element("li", step));
      }
      if (steps.childElementCount) {
        card.appendChild(element("strong", copy.steps));
        card.appendChild(steps);
      }
      root.appendChild(card);
    }
  }
}

/** The landing page's script: the decoder and renderer above, then a few lines of wiring. */
export function shareScript(): string {
  return `"use strict";
const COPY = ${JSON.stringify(COPY)};
const decodeSharePayload = ${decodeSharePayload.toString()};
const renderShare = ${renderShare.toString()};
(() => {
  const language = /^(nb|no|nn)\\b/i.test(navigator.language || "") ? "nb" : "en";
  const copy = COPY[language];
  document.documentElement.lang = language;
  const kind = location.pathname.split("/").pop() === "rules" ? "rules" : "recipes";
  for (const [id, key] of [["open", "open"], ["get", "get"], ["privacy", "privacy"]]) {
    const node = document.getElementById(id);
    if (node) node.textContent = copy[key];
  }
  let revision = 0;
  async function update() {
    const current = ++revision;
    const fragment = location.hash.slice(1);
    const open = document.getElementById("open");
    open.hidden = true;
    open.removeAttribute("href");
    document.getElementById("content").textContent = "";
    document.getElementById("heading").textContent = "Meal Shuffler";
    document.getElementById("intro").textContent = copy.loading;
    try {
      const data = await decodeSharePayload(fragment, ${MAX_DECODED_BYTES});
      if (current !== revision) return;
      renderShare(kind, data, copy);
      open.setAttribute("href", "mealshuffler://share/" + kind + "#" + fragment);
      open.hidden = false;
    } catch {
      if (current !== revision) return;
      document.getElementById("content").textContent = "";
      document.getElementById("intro").textContent = copy.unreadable;
    }
  }
  globalThis.addEventListener("hashchange", update);
  void update();
})();
`;
}

export function sharePage(appStoreURL?: string): string {
  const store = appStoreURL && /^https:\/\/apps\.apple\.com\//.test(appStoreURL)
    ? `<a class="button secondary" id="get" href="${escapeHTML(appStoreURL)}">Get Meal Shuffler</a>`
    : "";
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Meal Shuffler</title>
<style>${PAGE_STYLE}</style>
</head><body><main>
<div class="brand"><span>⇄</span> Meal Shuffler</div>
<h1 id="heading">Meal Shuffler</h1>
<p id="intro" role="status">Opening…</p>
<div id="content"></div>
<div class="actions">
<a class="button primary" id="open" hidden>Open in Meal Shuffler</a>
${store}
</div>
<small id="privacy"></small>
</main><script src="/s/app.js?v=2"></script></body></html>`;
}

// MARK: - Bring!

/**
 * The shopping list as a page Bring! can import.
 *
 * Bring only imports from a URL its own servers fetch; there is no way to hand it a list. So
 * the app puts the list in this URL's query, Bring fetches it, and this answers with the list
 * as schema.org recipe markup -- the same shape its button reads on any recipe site.
 */
export async function bringListPage(payload: string): Promise<string> {
  if (!PAYLOAD.test(payload)) throw new Error("unreadable");
  const data = await decodeSharePayload(payload, 200_000) as { n?: unknown; i?: unknown };
  const name = typeof data?.n === "string" && data.n.trim() ? data.n.trim().slice(0, 120) : "Shopping list";
  if (!Array.isArray(data?.i) || !data.i.length || data.i.length > 250
      || data.i.some(item => typeof item !== "string" || !item.trim() || item.trim().length > 200)) throw new Error("unreadable");
  const items = (data.i as string[]).map(item => item.trim());
  const recipe = {
    "@context": "https://schema.org",
    "@type": "Recipe",
    name,
    recipeYield: "1",
    recipeIngredient: items,
  };
  // `<` escaped so an item can never close the script element.
  const jsonLD = JSON.stringify(recipe).replace(/</g, "\\u003c");
  const list = items.map(item => `<li>${escapeHTML(item)}</li>`).join("");
  return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="robots" content="noindex, nofollow">
<title>${escapeHTML(name)}</title>
<script type="application/ld+json">${jsonLD}</script>
</head><body><h1>${escapeHTML(name)}</h1><ul>${list}</ul></body></html>`;
}

/** Routes the public GET pages, or returns null for anything else. */
export async function handlePublicPage(request: Request, appStoreURL?: string): Promise<Response | null> {
  if (request.method !== "GET" && request.method !== "HEAD") return null;
  const url = new URL(request.url);
  if (url.pathname === "/s/rules" || url.pathname === "/s/recipes") {
    return new Response(sharePage(appStoreURL), {
      headers: {
        ...SECURITY_HEADERS,
        "content-type": "text/html; charset=utf-8",
        "content-security-policy": "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      },
    });
  }
  if (url.pathname === "/s/app.js") {
    return new Response(shareScript(), {
      headers: { "content-type": "text/javascript; charset=utf-8", "cache-control": "public, max-age=3600", "x-content-type-options": "nosniff" },
    });
  }
  if (url.pathname === "/v1/bring/list") {
    try {
      const page = await bringListPage(url.searchParams.get("d") ?? "");
      return new Response(page, { headers: { ...SECURITY_HEADERS, "content-type": "text/html; charset=utf-8" } });
    } catch {
      return new Response("This list could not be read.", { status: 400, headers: { ...SECURITY_HEADERS, "content-type": "text/plain; charset=utf-8" } });
    }
  }
  return null;
}
