# Meal Shuffler privacy policy

<!--
This file is the source of truth for the privacy policy. The recipe service Worker serves the
same text at /privacy (and /privacy?lang=en, /privacy?lang=nb) from constants in
server/src/info.ts. Change both together.

The contact line below is the fallback. When the Worker's SUPPORT_EMAIL variable is set, the
served page shows that address instead.

OPERATOR REQUIREMENTS. This policy is only true while the Worker is run this way:

1. Request URLs must never be logged for /v1/bring/list. The shopping list travels in that
   URL's query string (`/v1/bring/list?d=...`), not in a fragment, so anything that records
   full request URLs records the list. The Worker's own log line uses a fixed route label, and
   server/wrangler.toml sets `observability.redact_query_string = true` and
   `observability.logs.invocation_logs = false`. Keep both. Do not turn on Logpush, a Tail
   Worker, or zone HTTP request logs (if the Worker moves to a custom domain) for this route
   without stripping the query, and do not save `wrangler tail` output. If that ever has to
   change, change this policy first.
2. Never log request headers. `X-Install-Id` (the random install ID) and `CF-Connecting-IP`
   are read only as rate-limit keys (server/src/index.ts, withinRateLimits). The IPv6 key is
   cut to its /64 (rateLimitAddressKey). The Cloudflare rate-limit bindings keep counters for
   their 60-second window; nothing else stores either value.
3. Anthropic receives only the recipe content, never the install ID or the IP address.
4. Keep MealShuffler/PrivacyInfo.xcprivacy and the label in docs/APP_STORE.md in step with
   this file.
-->

Effective date: 12 October 2026

Meal Shuffler is a dinner planner for families. It keeps your meal planning on your phone:
there is no account, no advertising, no analytics and no tracking. A few optional features send
specific content off your phone when you use them. This policy describes each of them.

## What stays on your phone

Your meals, recipes, recipe photos, house rules, weekly plans, shopping lists and history are
stored on your device. You do not create an account, and the developer of Meal Shuffler does
not receive a copy. The app contains no advertising, no analytics and no tracking SDKs.

Reminders are local notifications, scheduled on your phone. They are not sent through any
server.

If you turn on quick dinners on busy evenings, the app reads your calendar on the phone;
nothing is changed or sent. Exporting the shopping list to Reminders writes it to Apple's
Reminders app on your phone.

## iCloud sharing with your household

If you use iCloud sharing, the data you share is stored in your own iCloud account using
Apple's CloudKit (private and shared databases), and only the people you invite can see it.
The developer cannot read it. Apple handles it under Apple's privacy policy.

Inside your data, each recipe you add or change is marked with your phone's random install ID
(described below), so the app can tell which phone made a change. When you share through
iCloud, that random code travels with the shared data. It is not your name or anything else
about you.

## Reading recipes online (optional, off by default)

Online recipe reading is off until you turn it on in Settings in the app. While it is off,
recipes are read on your phone.

When it is on and you import a recipe, the app sends the recipe link, the text you pasted or
the recipe photos you chose to the Meal Shuffler recipe service, which runs on Cloudflare
Workers. For a link, the service downloads that page from the website. It forwards the content
to Anthropic's Claude API, which reads the recipe and returns it in a structured form, and the
service sends the result back to the app.

- The service does not store what you send or the recipe it returns.
- Anthropic processes the content to return the result and does not use it to train its
  models. The service sends Anthropic only the recipe content, never the random ID or your IP
  address.
- **A random install ID.** The first time the app starts, it creates a random ID for this
  installation. It is not made from anything about you or your phone — not your name, your
  Apple ID or your phone's hardware — and it stays the same until you delete the app. The app
  sends it with every online recipe request (in a header named `X-Install-Id`), and with
  nothing else.
- **Your IP address.** Like any web service, the recipe service sees the IP address a request
  comes from. For IPv6 addresses it uses only the network part (the first half, known as the
  /64), which points to a home connection or mobile network rather than one device.
- The ID and the address are used only to count requests, so that one phone or one
  connection cannot overload the service (rate limiting). Cloudflare keeps those counts for
  about a minute. Neither value is stored, logged, combined with the recipe or anything else,
  or used to identify you.
- The service's own logs record only the kind of request, the result status and how long it
  took. They never contain the recipe, the link, your IP address or the random ID.
- The service runs on Cloudflare, which carries the network traffic to it under Cloudflare's
  own privacy policy.

## Importing a recipe from a website

When you import a recipe from a link, the app contacts that website directly from your phone,
as a browser would, and loads the recipe's picture from the publisher. The website receives an
ordinary request from your phone, including your IP address, and handles it under its own
privacy policy.

## Sharing with friends

When you share a recipe, your house rules or a week, the content travels inside the link
itself, in the part after "#". Browsers do not send that part to any server. If someone opens
the link without the app, the Meal Shuffler service shows a page that reads the content from
the link in their browser. Nothing is uploaded or stored. Anyone who has the link can read
what is in it, so share it only with the people you mean to.

## Sending your shopping list to Bring!

If you choose "Send the list to Bring!", the app puts the shopping list — its title and each
item with its amount — into a web address on the Meal Shuffler service, and opens Bring! with
that address. The list sits in the part of the address after "?". Unlike the part after "#"
used for sharing with friends, that part is sent to servers:

- Bring! receives the address, with the list in it, from your phone.
- Bring!'s servers then fetch the address from the Meal Shuffler service, which reads the list
  from it and returns it as a page Bring! can import.

The Meal Shuffler service does not store the list, tells browsers and caches not to keep the
page, and its logs record only that a list page was served — never the address or the list.
The random install ID is not sent. From then on, Bring! processes the list under its own
privacy policy.

## Deleting your data

Deleting the app deletes the data stored on your phone. Data kept in iCloud can be removed in
the iOS Settings app under your name (Apple ID) → iCloud → Manage Account Storage. The recipe service
keeps nothing, so there is nothing to delete there.

## Children

Meal Shuffler is a family tool used by parents. It has no accounts and does not knowingly
collect personal information from children.

## Changes to this policy

If this policy changes, the new version will be published here with a new effective date.

## Contact

Contact us through the App Store page for Meal Shuffler.

---

# Personvernerklæring for Meal Shuffler

Gjelder fra: 12. oktober 2026

Meal Shuffler er en middagsplanlegger for familier. Planleggingen holdes på telefonen din: Det
finnes ingen konto, ingen reklame, ingen analyse og ingen sporing. Noen valgfrie funksjoner
sender bestemt innhold fra telefonen når du bruker dem. Denne erklæringen beskriver hver av
dem.

## Dette blir på telefonen

Rettene, oppskriftene, oppskriftsbildene, husreglene, ukeplanene, handlelistene og historikken
din lagres på enheten. Du oppretter ingen konto, og utvikleren av Meal Shuffler får ingen
kopi. Appen inneholder ingen reklame, ingen analyseverktøy og ingen sporings-SDK-er.

Påminnelser er lokale varsler som planlegges på telefonen. De sendes ikke via noen server.

Slår du på raske middager på travle kvelder, leser appen kalenderen på telefonen; ingenting
endres eller sendes. Eksporterer du handlelisten til Påminnelser, skrives den til Apples
Påminnelser-app på telefonen.

## iCloud-deling i husstanden

Hvis du bruker iCloud-deling, lagres det du deler i din egen iCloud-konto med Apples CloudKit
(private og delte databaser), og bare de du inviterer, kan se det. Utvikleren kan ikke lese
det. Apple behandler det etter Apples personvernerklæring.

I dataene dine merkes hver oppskrift du legger til eller endrer, med den tilfeldige installasjons-ID-en til
telefonen (beskrevet nedenfor), slik at appen vet hvilken telefon som gjorde endringen. Når du
deler via iCloud, følger denne tilfeldige koden med de delte dataene. Den er ikke navnet ditt
eller noe annet om deg.

## Lese oppskrifter på nett (valgfritt, av som standard)

Lesing av oppskrifter på nett er av til du slår det på under Innstillinger i appen. Så lenge
det er av, leses oppskriftene på telefonen.

Når det er på og du importerer en oppskrift, sender appen oppskriftslenken, teksten du limte
inn eller oppskriftsbildene du valgte, til Meal Shufflers oppskriftstjeneste, som kjører på
Cloudflare Workers. For en lenke laster tjenesten ned siden fra nettstedet. Den sender
innholdet videre til Anthropics Claude-API, som leser oppskriften og returnerer den i
strukturert form, og tjenesten sender resultatet tilbake til appen.

- Tjenesten lagrer ikke det du sender, eller oppskriften den returnerer.
- Anthropic behandler innholdet for å returnere resultatet og bruker det ikke til å trene
  modellene sine. Tjenesten sender bare oppskriftsinnholdet til Anthropic, aldri den
  tilfeldige ID-en eller IP-adressen din.
- **En tilfeldig installasjons-ID.** Første gang appen starter, lager den en tilfeldig ID for
  denne installasjonen. Den lages ikke av noe om deg eller telefonen din – ikke navnet ditt,
  Apple-ID-en din eller maskinvaren i telefonen – og den er den samme til du sletter appen.
  Appen sender den med hver forespørsel om å lese en oppskrift på nett (i en header som heter
  `X-Install-Id`), og ikke med noe annet.
- **IP-adressen din.** Som enhver nettjeneste ser oppskriftstjenesten IP-adressen en
  forespørsel kommer fra. For IPv6-adresser bruker den bare nettverksdelen (den første
  halvdelen, kalt /64), som peker på en hjemmeforbindelse eller et mobilnett i stedet for én enkelt
  enhet.
- ID-en og adressen brukes bare til å telle forespørsler, slik at én telefon eller én
  forbindelse ikke kan overbelaste tjenesten (begrensning av antall forespørsler). Cloudflare
  tar vare på disse tellerne i omtrent ett minutt. Ingen av verdiene lagres, logges, kobles
  til oppskriften eller noe annet, eller brukes til å identifisere deg.
- Tjenestens egne logger registrerer bare hva slags forespørsel det var, resultatstatusen og
  hvor lang tid den tok. De inneholder aldri oppskriften, lenken, IP-adressen din eller den
  tilfeldige ID-en.
- Tjenesten kjører hos Cloudflare, som frakter nettrafikken til den etter Cloudflares egen
  personvernerklæring.

## Importere en oppskrift fra et nettsted

Når du importerer en oppskrift fra en lenke, kontakter appen nettstedet direkte fra telefonen,
slik en nettleser gjør, og henter oppskriftsbildet fra utgiveren. Nettstedet mottar en vanlig
forespørsel fra telefonen, inkludert IP-adressen din, og behandler den etter sin egen
personvernerklæring.

## Deling med venner

Når du deler en oppskrift, husreglene eller en uke, ligger innholdet i selve lenken, i delen
etter «#». Nettlesere sender ikke den delen til noen server. Hvis noen åpner lenken uten appen,
viser Meal Shuffler-tjenesten en side som leser innholdet fra lenken i nettleseren deres.
Ingenting lastes opp eller lagres. Alle som har lenken, kan lese innholdet, så del den bare med
dem du mener å dele med.

## Sende handlelisten til Bring!

Hvis du velger «Send listen til Bring!», legger appen handlelisten – tittelen og hver vare med
mengde – inn i en nettadresse hos Meal Shuffler-tjenesten, og åpner Bring! med den adressen.
Listen ligger i delen av adressen etter «?». I motsetning til delen etter «#» som brukes ved
deling med venner, sendes denne delen til servere:

- Bring! mottar adressen, med listen i, fra telefonen din.
- Serverne til Bring! henter deretter adressen fra Meal Shuffler-tjenesten, som leser listen
  fra den og returnerer den som en side Bring! kan importere.

Meal Shuffler-tjenesten lagrer ikke listen, ber nettlesere og mellomlagre om ikke å beholde
siden, og loggene registrerer bare at en listeside ble levert – aldri adressen eller listen.
Den tilfeldige installasjons-ID-en sendes ikke. Deretter behandler Bring! listen etter sin egen
personvernerklæring.

## Slette dataene dine

Når du sletter appen, slettes dataene som er lagret på telefonen. Data i iCloud kan fjernes i
Innstillinger-appen under navnet ditt (Apple-ID) → iCloud → Administrer kontolagring.
Oppskriftstjenesten lagrer ingenting, så der er det ingenting å slette.

## Barn

Meal Shuffler er et familieverktøy som brukes av foreldre. Appen har ingen kontoer og samler
ikke bevisst inn personopplysninger fra barn.

## Endringer i erklæringen

Hvis erklæringen endres, publiseres den nye versjonen her med ny dato.

## Kontakt

Kontakt oss via App Store-siden for Meal Shuffler.
