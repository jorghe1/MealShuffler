// Scores the recipe service against eval/recipes-nb.json.
//
//   node eval/run-eval.mjs <base url> <label>
//
// Runs every recipe through POST /v1/recipes/extract on the given deployment (production or
// a preview version with another EXTRACTION_MODEL) and checks servings, the number of
// ingredients, time, and key ingredients' amount and unit against the expected answers.
// Spaced to stay under the per-install rate limit; each call counts against the day's budget.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const [base, label = "run"] = process.argv.slice(2);
if (!base) { console.error("usage: node eval/run-eval.mjs <base url> <label>"); process.exit(2); }
const recipes = JSON.parse(readFileSync(new URL("./recipes-nb.json", import.meta.url), "utf8"));

const UNIT = new Map(Object.entries({
  "": "", stk: "", "stk.": "", stykk: "", fedd: "", filet: "", fileter: "", stykker: "",
  pk: "pk", pakke: "pk", "pk.": "pk", pakning: "pk", pose: "pk",
  boks: "boks", bokser: "boks", skive: "skive", skiver: "skive",
  l: "l", liter: "l", dl: "dl", ml: "ml", g: "g", gram: "g", kg: "kg",
  ss: "ss", spiseskje: "ss", ts: "ts", teskje: "ts",
}));
const unit = u => UNIT.get((u ?? "").trim().toLowerCase()) ?? (u ?? "").trim().toLowerCase();
const close = (a, b) => a != null && b != null && Math.abs(a - b) < 0.011;

function score(recipe, out) {
  const notes = [];
  let points = 0, max = 0;
  const ingredients = out.ingredients ?? [];
  const haystack = i => `${i.name} ${i.originalText ?? ""}`.toLowerCase();

  if (recipe.servings !== null) {
    max++;
    if (out.servings != null && Math.abs(out.servings - recipe.servings) <= (recipe.servingsTolerance ?? 0)) points++;
    else notes.push(`servings ${out.servings} ≠ ${recipe.servings}`);
  }
  max++;
  const [lo, hi] = recipe.ingredientCount;
  if (ingredients.length >= lo && ingredients.length <= hi) points++;
  else notes.push(`${ingredients.length} ingredients, expected ${lo}–${hi}`);
  if (recipe.prepMinutes) {
    max++;
    const [a, b] = recipe.prepMinutes;
    if (out.prepMinutes != null && out.prepMinutes >= a && out.prepMinutes <= b) points++;
    else notes.push(`prepMinutes ${out.prepMinutes} not in ${a}–${b}`);
  }
  for (const [needle, quantity, expectedUnit, upper] of recipe.expect) {
    max++;
    const match = ingredients.find(i => haystack(i).includes(needle));
    if (!match) { notes.push(`missing ${needle}`); continue; }
    const qtyOK = quantity === null || close(match.quantity, quantity);
    const unitOK = quantity === null || unit(match.unit) === unit(expectedUnit);
    const upperOK = upper === undefined || close(match.upperQuantity, upper);
    if (qtyOK && unitOK && upperOK) points++;
    else notes.push(`${needle}: got ${match.quantity}${match.upperQuantity ? "–" + match.upperQuantity : ""} ${match.unit || "∅"}, want ${quantity}${upper ? "–" + upper : ""} ${expectedUnit || "∅"}`);
  }
  for (const word of recipe.notExpect ?? []) {
    if (ingredients.some(i => haystack(i).includes(word))) { points--; notes.push(`invented "${word}"`); }
  }
  max++;
  if ((out.instructions ?? []).length > 0 && out.name) points++; else notes.push("no name or steps");
  return { points: Math.max(points, 0), max, notes };
}

// Re-score a saved run against the current answers, without calling the service again:
//   node eval/run-eval.mjs --rescore <label>
if (base === "--rescore") {
  const saved = JSON.parse(readFileSync(new URL(`./results/${label}.json`, import.meta.url), "utf8"));
  let t = 0, m = 0;
  for (const recipe of recipes) {
    const row = saved.results.find(r => r.id === recipe.id);
    const s = row?.status === 200 ? score(recipe, row.output) : { points: 0, max: recipe.expect.length + 3, notes: ["no output"] };
    t += s.points; m += s.max;
    if (s.notes.length) console.log(`${s.points}/${s.max}  ${recipe.id}  — ${s.notes.join("; ")}`);
  }
  console.log(JSON.stringify({ label, score: t, max: m, percent: Math.round(1000 * t / m) / 10, meanMs: saved.summary.meanMs }));
  process.exit(0);
}

const sleep = ms => new Promise(r => setTimeout(r, ms));
const results = [];
let total = 0, totalMax = 0, failures = 0, ms = 0;
for (const recipe of recipes) {
  const started = Date.now();
  let status = 0, out = null;
  try {
    const response = await fetch(new URL("/v1/recipes/extract", base), {
      method: "POST",
      headers: { "content-type": "application/json", "x-install-id": `eval-${label}` },
      body: JSON.stringify({ text: recipe.text }),
    });
    status = response.status;
    out = await response.json();
  } catch (error) { out = { error: String(error) }; }
  const elapsed = Date.now() - started;
  ms += elapsed;
  let row;
  if (status === 200) {
    row = { id: recipe.id, status, elapsed, ...score(recipe, out) };
  } else {
    failures++;
    row = { id: recipe.id, status, elapsed, points: 0, max: recipe.expect.length + 3, notes: [`HTTP ${status} ${out?.code ?? out?.error ?? ""}`] };
  }
  total += row.points; totalMax += row.max;
  results.push({ ...row, output: out });
  console.log(`${row.points}/${row.max}  ${String(elapsed).padStart(5)} ms  ${recipe.id}${row.notes.length ? "  — " + row.notes.join("; ") : ""}`);
  await sleep(3500);
}
const summary = { label, base, score: total, max: totalMax, percent: Math.round(1000 * total / totalMax) / 10, failures, meanMs: Math.round(ms / recipes.length) };
console.log(JSON.stringify(summary));
mkdirSync(new URL("./results/", import.meta.url), { recursive: true });
writeFileSync(new URL(`./results/${label}.json`, import.meta.url), JSON.stringify({ summary, results }, null, 2));
