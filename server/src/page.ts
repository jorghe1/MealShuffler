/**
 * Fetching and reading a page the caller chose.
 *
 * Split out from the endpoint so the parts that decide *what we are willing to fetch* can be
 * tested without an API key or a model call. They are the security-relevant half of this
 * service: the endpoint takes a URL from anyone and fetches it from our account.
 */

export class HttpError extends Error {
  // Written out rather than declared as a constructor parameter property: the tests run
  // under Node's strip-only TypeScript mode, which cannot compile that shorthand away.
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export const MAX_PAGE_BYTES = 3_000_000;
/**
 * How much page text reaches the model.
 *
 * Was 120,000 characters -- roughly 30k tokens of stripped navigation, cookie notices and
 * comment threads to read a recipe that occupies two. A recipe that has not appeared in the
 * first 40k characters of a page is not going to.
 */
export const MAX_MODEL_CHARS = 40_000;
export const MAX_REDIRECTS = 4;
export const FETCH_TIMEOUT_MS = 10_000;

/**
 * Rejects hosts that only exist inside a network.
 *
 * The endpoint fetches a URL the caller chooses, which without this is a general-purpose
 * proxy attached to our account. Checked on every redirect hop as well as the first request:
 * a public host answering with `302 -> http://169.254.169.254/` is the whole trick.
 */
export function isBlockedHost(hostname: string): boolean {
  const host = hostname.toLowerCase().replace(/^\[/, "").replace(/\]$/, "");

  if (host.length === 0) return true;
  if (host === "localhost" || host.endsWith(".localhost")) return true;
  if (host.endsWith(".local") || host.endsWith(".internal") || host.endsWith(".home.arpa")) return true;
  if (host === "metadata.google.internal") return true;

  const v4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (v4) {
    const parts = v4.slice(1, 5).map(Number);
    if (parts.some((part) => part > 255)) return true;
    const [a, b] = parts;
    if (a === 0 || a === 10 || a === 127) return true;
    if (a === 169 && b === 254) return true; // link-local, incl. cloud metadata
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 192 && b === 0) return true; // IETF protocol assignments
    if (a === 100 && b >= 64 && b <= 127) return true; // carrier NAT
    if (a >= 224) return true; // multicast and reserved
    return false;
  }

  // Any raw IPv6 literal. Recipe publishers are reached by name; allowing literals here
  // buys nothing and costs an entire class of bypass.
  if (host.includes(":")) return true;

  return false;
}

export function assertFetchable(url: URL): void {
  if (url.protocol !== "https:") throw new HttpError(400, "Only https links are supported.");
  if (url.username || url.password) throw new HttpError(400, "That link is not supported.");
  if (isBlockedHost(url.hostname)) throw new HttpError(400, "That address cannot be opened.");
}

/** Reads at most `limit` bytes, cancelling the body rather than buffering the rest. */
export async function readCapped(response: Response, limit: number): Promise<Uint8Array> {
  const reader = response.body?.getReader();
  if (!reader) return new Uint8Array(0);

  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel();
      throw new HttpError(413, "That page is too large to read.");
    }
    chunks.push(value);
  }

  const buffer = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    buffer.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return buffer;
}

/** Strips scripts, styles and tags. The model reads far fewer tokens from text than markup,
 *  and the parts of a page that matter survive the strip. */
export function htmlToText(html: string): string {
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

/**
 * The page's own recipe markup, when it has some.
 *
 * A Recipe JSON-LD block is a few hundred tokens against tens of thousands for the page it
 * sits in, and it is already the shape we want. The app's on-device parser reads the clean
 * cases before we are ever called, so what reaches here is usually markup it choked on --
 * which the model reads perfectly well.
 */
export function recipeJSONLD(html: string): string | null {
  const blocks = [
    ...html.matchAll(
      /<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi,
    ),
  ]
    .map((match) => match[1].trim())
    .filter((text) => /"@type"\s*:\s*("?\[?[^\]}]{0,120}?)Recipe/i.test(text));

  if (blocks.length === 0) return null;
  return blocks.join("\n").slice(0, MAX_MODEL_CHARS);
}

/** The page's own hero image, so imported meals arrive with real photography and the app
 *  needs no picker, upload or storage of its own. */
export function ogImage(html: string, pageURL: string): string | null {
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
      if (resolved.protocol === "https:" && !isBlockedHost(resolved.hostname)) {
        return resolved.toString();
      }
    } catch {
      // Malformed URL in the markup; try the next pattern.
    }
  }
  return null;
}

/** Marks where untrusted material starts and stops, so the system prompt can name it. */
export function sourceBlock(label: string, body: string): string {
  return `${label}\n\n<SOURCE>\n${body}\n</SOURCE>`;
}

export async function fetchPage(target: string): Promise<{ text: string; image: string | null }> {
  let current: URL;
  try {
    current = new URL(target);
  } catch {
    throw new HttpError(400, "That link is not valid.");
  }

  let response: Response | null = null;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop += 1) {
    assertFetchable(current);

    let attempt: Response;
    try {
      attempt = await fetch(current.toString(), {
        // Manual, so every hop is validated. `follow` would let a public host bounce us
        // onto a private address without another look.
        redirect: "manual",
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
        headers: {
          // Several publishers reject the default agent outright, which used to surface in
          // the app as "no recipe found" for a page that had one.
          "user-agent": "MealShuffler/1.0 (+https://mealshuffler.no)",
          accept: "text/html,application/xhtml+xml",
        },
      });
    } catch {
      throw new HttpError(504, "That page took too long to answer.");
    }

    if ([301, 302, 303, 307, 308].includes(attempt.status)) {
      const location = attempt.headers.get("location");
      if (!location) throw new HttpError(502, "That page could not be opened.");
      try {
        current = new URL(location, current);
      } catch {
        throw new HttpError(502, "That page could not be opened.");
      }
      continue;
    }

    response = attempt;
    break;
  }

  if (!response) throw new HttpError(502, "That link redirects too many times.");
  if (!response.ok) throw new HttpError(502, "That page could not be opened.");

  const contentType = response.headers.get("content-type") ?? "";
  if (!/^\s*(text\/html|application\/xhtml\+xml|text\/plain)/i.test(contentType)) {
    throw new HttpError(415, "That link is not a web page.");
  }

  const declared = Number(response.headers.get("content-length") ?? "0");
  if (declared > MAX_PAGE_BYTES) throw new HttpError(413, "That page is too large to read.");

  const bytes = await readCapped(response, MAX_PAGE_BYTES);

  // Honour the declared charset: Norwegian food sites still serve ISO-8859-1, where a
  // UTF-8 decode silently produces replacement characters.
  const charset = /charset=([^;]+)/i.exec(contentType)?.[1]?.trim() ?? "utf-8";
  let html: string;
  try {
    html = new TextDecoder(charset).decode(bytes);
  } catch {
    html = new TextDecoder("utf-8").decode(bytes);
  }

  const structured = recipeJSONLD(html);
  return {
    text: structured ?? htmlToText(html).slice(0, MAX_MODEL_CHARS),
    image: ogImage(html, current.toString()),
  };
}
