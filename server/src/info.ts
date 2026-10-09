/**
 * The privacy policy and support page, at /privacy and /support.
 *
 * App Store review needs both as public URLs, and this Worker is the one public host the app
 * already has. The text is `docs/PRIVACY.md`, embedded rather than read at runtime: change the
 * two together. Like the share pages, these are static, script-free and store nothing.
 *
 * Unlike the share pages they are cacheable and indexable -- they carry no user content, and
 * someone searching for help should be able to find them. `Vary: Accept-Language` keeps a
 * cache from handing a Norwegian page to an English browser.
 */

import { escapeHTML, PAGE_STYLE } from "./share.ts";

export type InfoLanguage = "en" | "nb";

export interface InfoOptions {
  /** `SUPPORT_EMAIL`. Shown only when it looks like an address. */
  supportEmail?: string;
  /** `APP_STORE_URL`. Linked from the fallback contact line when set. */
  appStoreURL?: string;
}

function languageOf(tag: string): InfoLanguage | null {
  const primary = tag.trim().toLowerCase().split("-")[0];
  if (primary === "nb" || primary === "no" || primary === "nn") return "nb";
  if (primary === "en") return "en";
  return null;
}

/**
 * `?lang=` wins when it names a language we have. Otherwise the browser's preferences in
 * q-value order, taking the first we can serve (`de, nb;q=0.8` is Norwegian). English when
 * nothing matches.
 */
export function pickLanguage(query: string | null, acceptLanguage: string | null): InfoLanguage {
  const explicit = query ? languageOf(query) : null;
  if (explicit) return explicit;
  const ranked = (acceptLanguage ?? "").split(",").map((part, index) => {
    const [tag, ...parameters] = part.split(";");
    const q = parameters.map(parameter => /^\s*q\s*=\s*([0-9.]+)\s*$/i.exec(parameter)).find(Boolean);
    return { tag: tag.trim(), q: q ? Number(q[1]) : 1, index };
  }).filter(entry => entry.tag && entry.q > 0).sort((a, b) => b.q - a.q || a.index - b.index);
  for (const entry of ranked) {
    const language = languageOf(entry.tag);
    if (language) return language;
  }
  return "en";
}

function supportEmail(value: string | undefined): string | null {
  const email = value?.trim() ?? "";
  return email.length <= 254 && /^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$/.test(email)
    ? email : null;
}

/** The contact line: the configured address, else the App Store listing. Never an invented one. */
export function contactHTML(language: InfoLanguage, options: InfoOptions): string {
  const email = supportEmail(options.supportEmail);
  if (email) {
    const link = `<a href="mailto:${escapeHTML(email)}">${escapeHTML(email)}</a>`;
    return language === "nb" ? `Send oss en e-post på ${link}.` : `Email us at ${link}.`;
  }
  const store = options.appStoreURL && /^https:\/\/apps\.apple\.com\//.test(options.appStoreURL)
    ? options.appStoreURL : null;
  const page = language === "nb" ? "App Store-siden for Meal Shuffler" : "the App Store page for Meal Shuffler";
  const linked = store ? `<a href="${escapeHTML(store)}">${page}</a>` : page;
  return language === "nb" ? `Kontakt oss via ${linked}.` : `Contact us through ${linked}.`;
}

/** A card: heading plus trusted HTML authored in this file. Only `{contact}` is substituted. */
interface Section { heading: string; body: string }

interface InfoPage { title: string; lead: string; sections: Section[] }

const NAV = {
  en: { privacy: "Privacy", support: "Support", other: "Norsk", otherLanguage: "nb" },
  nb: { privacy: "Personvern", support: "Hjelp", other: "English", otherLanguage: "en" },
} as const;

// MARK: - Privacy (docs/PRIVACY.md)

const PRIVACY: Record<InfoLanguage, InfoPage> = {
  en: {
    title: "Privacy policy",
    lead: `Effective date: 9 October 2026. Meal Shuffler is a dinner planner for families. It keeps
your meal planning on your phone: there is no account, no advertising, no analytics and no tracking.
A few optional features send specific content off your phone when you use them. This policy describes
each of them.`,
    sections: [
      { heading: "What stays on your phone", body: `<p>Your meals, recipes, recipe photos, house rules,
weekly plans, shopping lists and history are stored on your device. You do not create an account, and
the developer of Meal Shuffler does not receive a copy. The app contains no advertising, no analytics
and no tracking SDKs.</p>
<p>Reminders are local notifications, scheduled on your phone. They are not sent through any server.</p>` },
      { heading: "iCloud sharing with your household", body: `<p>If you use iCloud sharing, the data you
share is stored in your own iCloud account using Apple's CloudKit (private and shared databases), and
only the people you invite can see it. The developer cannot read it. Apple handles it under Apple's
privacy policy.</p>` },
      { heading: "Reading recipes online (optional, off by default)", body: `<p>Online recipe reading is
off until you turn it on in Settings in the app. While it is off, recipes are read on your phone.</p>
<p>When it is on and you import a recipe, the app sends the recipe link, the text you pasted or the
recipe photos you chose to the Meal Shuffler recipe service, which runs on Cloudflare Workers. For a
link, the service downloads that page from the website. It forwards the content to Anthropic's Claude
API, which reads the recipe and returns it in a structured form, and the service sends the result back
to the app.</p>
<ul>
<li>The service does not store what you send or the recipe it returns.</li>
<li>Anthropic processes the content to return the result and does not use it to train its models.</li>
<li>The app sends a random ID created on your phone, which is not linked to your name, your Apple ID or
anything else about you, and the service sees your IP address. Both are used only for rate limiting,
to protect the service from abuse.</li>
<li>The service's own logs record only the kind of request, the result status and how long it took.
They never contain the recipe, the link, your IP address or the random ID.</li>
</ul>` },
      { heading: "Importing a recipe from a website", body: `<p>When you import a recipe from a link, the
app contacts that website directly from your phone, as a browser would, and loads the recipe's picture
from the publisher. The website receives an ordinary request from your phone, including your IP
address, and handles it under its own privacy policy.</p>` },
      { heading: "Sharing with friends", body: `<p>When you share a recipe, your house rules or a week,
the content travels inside the link itself, in the part after "#". Browsers do not send that part to
any server. If someone opens the link without the app, the Meal Shuffler service shows a page that
reads the content from the link in their browser. Nothing is uploaded or stored. Anyone who has the
link can read what is in it, so share it only with the people you mean to.</p>` },
      { heading: "Sending your shopping list to Bring!", body: `<p>If you choose "Send the list to
Bring!", the app puts the shopping list in a link and passes it to Bring!. Bring!'s servers fetch that
link from the Meal Shuffler service, which reads the list from the link and returns it as a page Bring!
can import, without storing it. From then on, Bring! processes the list under its own privacy
policy.</p>` },
      { heading: "Deleting your data", body: `<p>Deleting the app deletes the data stored on your phone.
Data kept in iCloud can be removed in the iOS Settings app under your name (Apple ID) → iCloud → Manage
Storage. The recipe service keeps nothing, so there is nothing to delete there.</p>` },
      { heading: "Children", body: `<p>Meal Shuffler is a family tool used by parents. It has no accounts
and does not knowingly collect personal information from children.</p>` },
      { heading: "Changes to this policy", body: `<p>If this policy changes, the new version will be
published here with a new effective date.</p>` },
      { heading: "Contact", body: `<p>{contact}</p>` },
    ],
  },
  nb: {
    title: "Personvernerklæring",
    lead: `Gjelder fra: 9. oktober 2026. Meal Shuffler er en middagsplanlegger for familier.
Planleggingen holdes på telefonen din: Det finnes ingen konto, ingen reklame, ingen analyse og ingen
sporing. Noen valgfrie funksjoner sender bestemt innhold fra telefonen når du bruker dem. Denne
erklæringen beskriver hver av dem.`,
    sections: [
      { heading: "Dette blir på telefonen", body: `<p>Rettene, oppskriftene, oppskriftsbildene,
husreglene, ukeplanene, handlelistene og historikken din lagres på enheten. Du oppretter ingen konto,
og utvikleren av Meal Shuffler får ingen kopi. Appen inneholder ingen reklame, ingen analyseverktøy og
ingen sporings-SDK-er.</p>
<p>Påminnelser er lokale varsler som planlegges på telefonen. De sendes ikke via noen server.</p>` },
      { heading: "iCloud-deling i husstanden", body: `<p>Hvis du bruker iCloud-deling, lagres det du
deler i din egen iCloud-konto med Apples CloudKit (private og delte databaser), og bare de du
inviterer, kan se det. Utvikleren kan ikke lese det. Apple behandler det etter Apples
personvernerklæring.</p>` },
      { heading: "Lese oppskrifter på nett (valgfritt, av som standard)", body: `<p>Lesing av
oppskrifter på nett er av til du slår det på under Innstillinger i appen. Så lenge det er av, leses
oppskriftene på telefonen.</p>
<p>Når det er på og du importerer en oppskrift, sender appen oppskriftslenken, teksten du limte inn
eller oppskriftsbildene du valgte, til Meal Shufflers oppskriftstjeneste, som kjører på Cloudflare
Workers. For en lenke laster tjenesten ned siden fra nettstedet. Den sender innholdet videre til
Anthropics Claude-API, som leser oppskriften og returnerer den i strukturert form, og tjenesten sender
resultatet tilbake til appen.</p>
<ul>
<li>Tjenesten lagrer ikke det du sender, eller oppskriften den returnerer.</li>
<li>Anthropic behandler innholdet for å returnere resultatet og bruker det ikke til å trene modellene
sine.</li>
<li>Appen sender en tilfeldig ID som lages på telefonen og ikke er knyttet til navnet ditt, Apple-ID-en
din eller noe annet om deg, og tjenesten ser IP-adressen din. Begge brukes bare til å begrense antall
forespørsler, for å beskytte tjenesten mot misbruk.</li>
<li>Tjenestens egne logger registrerer bare hva slags forespørsel det var, resultatstatusen og hvor
lang tid den tok. De inneholder aldri oppskriften, lenken, IP-adressen din eller den tilfeldige
ID-en.</li>
</ul>` },
      { heading: "Importere en oppskrift fra et nettsted", body: `<p>Når du importerer en oppskrift fra
en lenke, kontakter appen nettstedet direkte fra telefonen, slik en nettleser gjør, og henter
oppskriftsbildet fra utgiveren. Nettstedet mottar en vanlig forespørsel fra telefonen, inkludert
IP-adressen din, og behandler den etter sin egen personvernerklæring.</p>` },
      { heading: "Deling med venner", body: `<p>Når du deler en oppskrift, husreglene eller en uke,
ligger innholdet i selve lenken, i delen etter «#». Nettlesere sender ikke den delen til noen server.
Hvis noen åpner lenken uten appen, viser Meal Shuffler-tjenesten en side som leser innholdet fra lenken
i nettleseren deres. Ingenting lastes opp eller lagres. Alle som har lenken, kan lese innholdet, så del
den bare med dem du mener å dele med.</p>` },
      { heading: "Sende handlelisten til Bring!", body: `<p>Hvis du velger «Send listen til Bring!»,
legger appen handlelisten i en lenke og gir den til Bring!. Serverne til Bring! henter lenken fra Meal
Shuffler-tjenesten, som leser listen fra lenken og returnerer den som en side Bring! kan importere,
uten å lagre den. Deretter behandler Bring! listen etter sin egen personvernerklæring.</p>` },
      { heading: "Slette dataene dine", body: `<p>Når du sletter appen, slettes dataene som er lagret på
telefonen. Data i iCloud kan fjernes i Innstillinger-appen under navnet ditt (Apple-ID) → iCloud →
Administrer lagring. Oppskriftstjenesten lagrer ingenting, så der er det ingenting å slette.</p>` },
      { heading: "Barn", body: `<p>Meal Shuffler er et familieverktøy som brukes av foreldre. Appen har
ingen kontoer og samler ikke bevisst inn personopplysninger om barn.</p>` },
      { heading: "Endringer i erklæringen", body: `<p>Hvis erklæringen endres, publiseres den nye
versjonen her med ny dato.</p>` },
      { heading: "Kontakt", body: `<p>{contact}</p>` },
    ],
  },
};

// MARK: - Support

const SUPPORT: Record<InfoLanguage, InfoPage> = {
  en: {
    title: "Meal Shuffler support",
    lead: `Meal Shuffler plans your family's dinners. It shuffles a week of meals that follows your
house rules and turns it into a shopping list. Everything is stored on your phone.`,
    sections: [
      { heading: "Get help", body: `<p>{contact}</p>` },
      { heading: "My reminders don't arrive", body: `<p>Reminders are scheduled on your phone, so they
work without a connection. Check that reminders are turned on in Settings in the app, that
notifications are allowed for Meal Shuffler in the iOS Settings app under Notifications, and that a
Focus mode is not silencing them.</p>` },
      { heading: "How do I turn on online recipe reading?", body: `<p>Open Settings in the app and turn
on "Read recipes online". It is off by default. While it is on, the links, text and photos you import
are sent to the Meal Shuffler recipe service and to Anthropic to be read; the
<a href="/privacy?lang=en">privacy policy</a> explains the details. If you don't see the switch, your
version of the app reads recipes on the phone only.</p>` },
      { heading: "How do I back up my meals?", body: `<p>Open Settings in the app, choose Full backups,
then Export full backup, and save the file somewhere safe, such as iCloud Drive. Use Restore full
backup to bring it back, for example on a new phone.</p>` },
      { heading: "How do I delete my data?", body: `<p>Delete the app to delete everything stored on
your phone. If you used iCloud sharing, remove its data in the iOS Settings app under your name
(Apple ID) → iCloud → Manage Storage. The recipe service keeps nothing about you.</p>` },
      { heading: "What happens to my data?", body: `<p>Read the <a href="/privacy?lang=en">privacy
policy</a>. The short version: it stays on your phone unless you use one of the optional features it
describes.</p>` },
    ],
  },
  nb: {
    title: "Hjelp for Meal Shuffler",
    lead: `Meal Shuffler planlegger familiens middager. Appen stokker en uke med retter som følger
husreglene deres, og lager handlelisten ut fra den. Alt lagres på telefonen din.`,
    sections: [
      { heading: "Få hjelp", body: `<p>{contact}</p>` },
      { heading: "Påminnelsene kommer ikke", body: `<p>Påminnelser planlegges på telefonen, så de
virker uten nettforbindelse. Sjekk at påminnelser er slått på under Innstillinger i appen, at varsler
er tillatt for Meal Shuffler i Innstillinger-appen under Varslinger, og at en fokusmodus ikke
demper dem.</p>` },
      { heading: "Hvordan slår jeg på lesing av oppskrifter på nett?", body: `<p>Åpne Innstillinger i
appen og slå på lesing av oppskrifter på nett. Det er av som standard. Så lenge det er på, sendes
lenkene, teksten og bildene du importerer, til Meal Shufflers oppskriftstjeneste og til Anthropic for
å bli lest; <a href="/privacy?lang=nb">personvernerklæringen</a> forklarer detaljene. Ser du ikke
bryteren, leser din versjon av appen oppskrifter bare på telefonen.</p>` },
      { heading: "Hvordan tar jeg sikkerhetskopi av rettene?", body: `<p>Åpne Innstillinger i appen,
velg Fullstendige sikkerhetskopier og deretter Eksporter full sikkerhetskopi, og lagre filen et trygt
sted, for eksempel i iCloud Drive. Bruk Gjenopprett full sikkerhetskopi for å hente den tilbake, for
eksempel på en ny telefon.</p>` },
      { heading: "Hvordan sletter jeg dataene mine?", body: `<p>Slett appen for å slette alt som er
lagret på telefonen. Hvis du har brukt iCloud-deling, fjerner du dataene i Innstillinger-appen under
navnet ditt (Apple-ID) → iCloud → Administrer lagring. Oppskriftstjenesten lagrer ingenting om
deg.</p>` },
      { heading: "Hva skjer med dataene mine?", body: `<p>Les
<a href="/privacy?lang=nb">personvernerklæringen</a>. Kort sagt: De blir på telefonen, med mindre du
bruker en av de valgfrie funksjonene den beskriver.</p>` },
    ],
  },
};

const INFO_STYLE = `
nav { display: flex; flex-wrap: wrap; gap: 4px 16px; margin: 12px 0 0; font-size: 15px; }
nav a[aria-current] { color: var(--ink); font-weight: 700; text-decoration: none; }
a { color: var(--green); }
.lead { color: var(--ink); }
.card { overflow-wrap: break-word; }
.card p, .card li { color: var(--ink); margin: 8px 0 0; }
`;

type InfoKind = "privacy" | "support";

export function infoPage(kind: InfoKind, language: InfoLanguage, options: InfoOptions = {}): string {
  const page = (kind === "privacy" ? PRIVACY : SUPPORT)[language];
  const nav = NAV[language];
  const contact = contactHTML(language, options);
  const link = (target: InfoKind, label: string) =>
    `<a href="/${target}?lang=${language}"${target === kind ? ` aria-current="page"` : ""}>${label}</a>`;
  const cards = page.sections.map(section =>
    `<section class="card"><h2>${escapeHTML(section.heading)}</h2>\n${section.body.replace("{contact}", () => contact)}</section>`,
  ).join("\n");
  return `<!doctype html>
<html lang="${language}"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHTML(page.title)} · Meal Shuffler</title>
<style>${PAGE_STYLE}${INFO_STYLE}</style>
</head><body><main>
<div class="brand"><span>⇄</span> Meal Shuffler</div>
<nav>${link("privacy", nav.privacy)}${link("support", nav.support)}<a href="/${kind}?lang=${nav.otherLanguage}" lang="${nav.otherLanguage}" hreflang="${nav.otherLanguage}">${nav.other}</a></nav>
<h1>${escapeHTML(page.title)}</h1>
<p class="lead">${page.lead}</p>
${cards}
</main></body></html>`;
}

/** Routes GET /privacy and GET /support, or returns null for anything else. */
export function handleInfoPage(request: Request, options: InfoOptions = {}): Response | null {
  if (request.method !== "GET" && request.method !== "HEAD") return null;
  const url = new URL(request.url);
  if (url.pathname !== "/privacy" && url.pathname !== "/support") return null;
  const language = pickLanguage(url.searchParams.get("lang"), request.headers.get("accept-language"));
  return new Response(infoPage(url.pathname === "/privacy" ? "privacy" : "support", language, options), {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "content-language": language,
      "cache-control": "public, max-age=3600",
      vary: "Accept-Language",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      // No script, no images, no external anything: styles inline, links only.
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    },
  });
}
