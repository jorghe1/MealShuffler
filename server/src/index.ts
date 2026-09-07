import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";

/**
 * Recipe extraction for Meal Shuffler.
 *
 * One stateless endpoint, no accounts. It exists because the two import paths in the app
 * were its weakest code: link import broke on encoding, user-agent and non-JSON-LD markup,
 * and photo import turned a cookbook page into twelve junk shopping-list rows. The app keeps
 * its on-device schema.org parser as a fast path and only falls back to here, so a service
 * outage degrades import rather than breaking it.
 */

export interface Env {
  ANTHROPIC_API_KEY: string;
  /** Cloudflare native rate limiter, keyed per install. */
  RATE_LIMITER: { limit: (options: { key: string }) => Promise<{ success: boolean }> };
}

/** Mirrors GroceryAisle in the app. */
const AISLES = ["produce", "bread", "meatAndFish", "dairy", "pantry", "frozen"] as const;

/** Mirrors MealTag. Imported recipes previously arrived untagged, so a rule like
 *  "fish on Tuesday" could never match one. */
const TAGS = [
  "fish", "chicken", "meat", "vegetarian", "pizza",
  "pasta", "soup", "taco", "quick", "weekend",
] as const;

const IngredientSchema = z.object({
  name: z.string().describe("Ingredient name only, no quantity, singular where natural"),
  quantity: z.number().nullable().describe("null when the recipe gives no amount"),
  unit: z.string().describe("Short unit as written: g, kg, dl, ss, ts, stk, pcs. Empty when none."),
  aisle: z.enum(AISLES).describe("Supermarket section this is bought from"),
});

const RecipeSchema = z.object({
  name: z.string(),
  subtitle: z.string().describe("One short line. Empty string if nothing suitable."),
  emoji: z.string().describe("A single emoji representing the dish"),
  prepMinutes: z.number().int().describe("Total active time; best estimate when unstated"),
  servings: z.number().int(),
  ingredients: z.array(IngredientSchema),
  instructions: z.array(z.string()).describe("One step per entry, no leading numbers"),
  tags: z.array(z.enum(TAGS)),
  confidence: z.enum(["high", "medium", "low"])
    .describe("low when the source was partial or hard to read"),
});

const SYSTEM = `You extract recipes into a fixed schema for a family meal planner.

Rules:
- Ingredients only. Never turn a heading, timing, yield, serving suggestion, photo credit,
  page number or instruction step into an ingredient.
- Instruction steps go in instructions, without their leading numbers.
- Aisle is where the item is bought, not what word it contains: coconut milk and egg noodles
  are pantry, butternut squash is produce, parmesan is dairy, chicken stock is pantry.
- Keep the source language. A Norwegian recipe stays Norwegian.
- Keep units as the source writes them; do not convert.
- Never invent ingredients or steps that are not present. Omit rather than guess.
- Set confidence to low when the text was partial, blurry or ambiguous.`;

const MAX_PAGE_BYTES = 5_000_000;
const MAX_IMAGE_BYTES = 5_000_000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

/** Strips scripts, styles and tags. The model reads far fewer tokens from text than markup,
 *  and the parts of a page that matter survive the strip. */
function htmlToText(html: string): string {
  return html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/[ \t\r\f\v]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/** The page's own hero image, so imported meals arrive with real photography and the app
 *  needs no picker, upload or storage of its own. */
function ogImage(html: string, pageURL: string): string | null {
  const patterns = [
    /<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i,
    /<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i,
    /<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i,
  ];
  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (!match) continue;
    try {
      const resolved = new URL(match[1], pageURL);
      if (resolved.protocol === "https:") return resolved.toString();
    } catch {
      // Malformed URL in the markup; try the next pattern.
    }
  }
  return null;
}

async function fetchPage(target: string): Promise<{ text: string; image: string | null }> {
  const url = new URL(target);
  if (url.protocol !== "https:") throw new HttpError(400, "Only https links are supported.");

  const response = await fetch(url.toString(), {
    headers: {
      // Several publishers reject the default agent outright, which used to surface in
      // the app as "no recipe found" for a page that had one.
      "user-agent": "MealShuffler/1.0 (+https://mealshuffler.no)",
      accept: "text/html,application/xhtml+xml",
    },
    redirect: "follow",
  });
  if (!response.ok) throw new HttpError(502, "That page could not be opened.");

  const buffer = await response.arrayBuffer();
  if (buffer.byteLength > MAX_PAGE_BYTES) throw new HttpError(413, "That page is too large to read.");

  // Honour the declared charset: Norwegian food sites still serve ISO-8859-1, where a
  // UTF-8 decode silently produces replacement characters.
  const contentType = response.headers.get("content-type") ?? "";
  const charset = /charset=([^;]+)/i.exec(contentType)?.[1]?.trim() ?? "utf-8";
  let html: string;
  try {
    html = new TextDecoder(charset).decode(buffer);
  } catch {
    html = new TextDecoder("utf-8").decode(buffer);
  }

  return { text: htmlToText(html).slice(0, 120_000), image: ogImage(html, url.toString()) };
}

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

async function extract(
  client: Anthropic,
  content: Anthropic.MessageParam["content"],
): Promise<z.infer<typeof RecipeSchema>> {
  const response = await client.messages.parse({
    model: "claude-opus-5",
    max_tokens: 8000,
    system: SYSTEM,
    // Extraction into a fixed schema is not a reasoning-heavy task, and this endpoint is
    // the app's only per-call cost. Raise to "medium" first if quality disappoints.
    output_config: {
      effort: "low",
      format: zodOutputFormat(RecipeSchema),
    },
    messages: [{ role: "user", content }],
  });

  // A policy decline returns HTTP 200 with no usable content, so check before reading.
  if (response.stop_reason === "refusal") {
    throw new HttpError(422, "That content could not be read as a recipe.");
  }
  if (!response.parsed_output) {
    throw new HttpError(502, "The recipe could not be read from that source.");
  }
  return response.parsed_output;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") return json({ error: "Use POST." }, 405);

    const url = new URL(request.url);
    if (url.pathname !== "/v1/recipes/extract") return json({ error: "Not found." }, 404);

    // Not authentication -- an install identifier so abuse can be attributed and capped
    // before there is anything worth abusing.
    const installID = request.headers.get("x-install-id") ?? "anonymous";
    const { success } = await env.RATE_LIMITER.limit({ key: installID });
    if (!success) return json({ error: "Too many imports just now. Try again shortly." }, 429);

    let body: { url?: string; text?: string; imageBase64?: string; imageMediaType?: string };
    try {
      body = await request.json();
    } catch {
      return json({ error: "Malformed request." }, 400);
    }

    const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });

    try {
      let content: Anthropic.MessageParam["content"];
      let heroImageURL: string | null = null;

      if (body.url) {
        const page = await fetchPage(body.url);
        heroImageURL = page.image;
        content = [{ type: "text", text: `Extract the recipe from this page.\n\n${page.text}` }];
      } else if (body.imageBase64) {
        const mediaType = body.imageMediaType ?? "image/jpeg";
        if (!/^image\/(jpeg|png|webp|gif)$/.test(mediaType)) {
          return json({ error: "Unsupported image type." }, 415);
        }
        // base64 is ~4/3 the byte size of the original.
        if (body.imageBase64.length > MAX_IMAGE_BYTES * 1.4) {
          return json({ error: "That image is too large." }, 413);
        }
        content = [
          {
            type: "image",
            source: { type: "base64", media_type: mediaType as "image/jpeg", data: body.imageBase64 },
          },
          { type: "text", text: "Extract the recipe shown in this photo." },
        ];
      } else if (body.text) {
        content = [
          { type: "text", text: `Extract the recipe from this text.\n\n${body.text.slice(0, 120_000)}` },
        ];
      } else {
        return json({ error: "Provide a url, text or image." }, 400);
      }

      const recipe = await extract(client, content);
      return json({ ...recipe, heroImageURL });
    } catch (error) {
      if (error instanceof HttpError) return json({ error: error.message }, error.status);
      if (error instanceof Anthropic.RateLimitError) {
        return json({ error: "Busy right now. Try again shortly." }, 429);
      }
      if (error instanceof Anthropic.APIConnectionError) {
        return json({ error: "Could not reach the extraction service." }, 503);
      }
      console.error("extract failed", error);
      return json({ error: "Extraction failed." }, 500);
    }
  },
};
