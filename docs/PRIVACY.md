# Meal Shuffler privacy policy

<!--
This file is the source of truth for the privacy policy. The recipe service Worker serves the
same text at /privacy (and /privacy?lang=en, /privacy?lang=nb) from constants in
server/src/info.ts. Change both together.

The contact line below is the fallback. When the Worker's SUPPORT_EMAIL variable is set, the
served page shows that address instead.
-->

Effective date: 9 October 2026

Meal Shuffler is a dinner planner for families. It keeps your meal planning on your phone:
there is no account, no advertising, no analytics and no tracking. A few optional features send
specific content off your phone when you use them. This policy describes each of them.

## What stays on your phone

Your meals, recipes, recipe photos, house rules, weekly plans, shopping lists and history are
stored on your device. You do not create an account, and the developer of Meal Shuffler does
not receive a copy. The app contains no advertising, no analytics and no tracking SDKs.

Reminders are local notifications, scheduled on your phone. They are not sent through any
server.

## iCloud sharing with your household

If you use iCloud sharing, the data you share is stored in your own iCloud account using
Apple's CloudKit (private and shared databases), and only the people you invite can see it.
The developer cannot read it. Apple handles it under Apple's privacy policy.

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
  models.
- The app sends a random ID created on your phone, which is not linked to your name, your
  Apple ID or anything else about you, and the service sees your IP address. Both are used
  only for rate limiting, to protect the service from abuse.
- The service's own logs record only the kind of request, the result status and how long it
  took. They never contain the recipe, the link, your IP address or the random ID.

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

If you choose "Send the list to Bring!", the app puts the shopping list in a link and passes
it to Bring!. Bring!'s servers fetch that link from the Meal Shuffler service, which reads the
list from the link and returns it as a page Bring! can import, without storing it. From then
on, Bring! processes the list under its own privacy policy.

## Deleting your data

Deleting the app deletes the data stored on your phone. Data kept in iCloud can be removed in
the iOS Settings app under your name (Apple ID) → iCloud → Manage Storage. The recipe service
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

Gjelder fra: 9. oktober 2026

Meal Shuffler er en middagsplanlegger for familier. Planleggingen holdes på telefonen din: Det
finnes ingen konto, ingen reklame, ingen analyse og ingen sporing. Noen valgfrie funksjoner
sender bestemt innhold fra telefonen når du bruker dem. Denne erklæringen beskriver hver av
dem.

## Dette blir på telefonen

Rettene, oppskriftene, oppskriftsbildene, husreglene, ukeplanene, handlelistene og historikken
din lagres på enheten. Du oppretter ingen konto, og utvikleren av Meal Shuffler får ingen
kopi. Appen inneholder ingen reklame, ingen analyseverktøy og ingen sporings-SDK-er.

Påminnelser er lokale varsler som planlegges på telefonen. De sendes ikke via noen server.

## iCloud-deling i husstanden

Hvis du bruker iCloud-deling, lagres det du deler i din egen iCloud-konto med Apples CloudKit
(private og delte databaser), og bare de du inviterer, kan se det. Utvikleren kan ikke lese
det. Apple behandler det etter Apples personvernerklæring.

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
  modellene sine.
- Appen sender en tilfeldig ID som lages på telefonen og ikke er knyttet til navnet ditt,
  Apple-ID-en din eller noe annet om deg, og tjenesten ser IP-adressen din. Begge brukes bare
  til å begrense antall forespørsler, for å beskytte tjenesten mot misbruk.
- Tjenestens egne logger registrerer bare hva slags forespørsel det var, resultatstatusen og
  hvor lang tid den tok. De inneholder aldri oppskriften, lenken, IP-adressen din eller den
  tilfeldige ID-en.

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

Hvis du velger «Send listen til Bring!», legger appen handlelisten i en lenke og gir den til
Bring!. Serverne til Bring! henter lenken fra Meal Shuffler-tjenesten, som leser listen fra
lenken og returnerer den som en side Bring! kan importere, uten å lagre den. Deretter behandler
Bring! listen etter sin egen personvernerklæring.

## Slette dataene dine

Når du sletter appen, slettes dataene som er lagret på telefonen. Data i iCloud kan fjernes i
Innstillinger-appen under navnet ditt (Apple-ID) → iCloud → Administrer lagring.
Oppskriftstjenesten lagrer ingenting, så der er det ingenting å slette.

## Barn

Meal Shuffler er et familieverktøy som brukes av foreldre. Appen har ingen kontoer og samler
ikke bevisst inn personopplysninger om barn.

## Endringer i erklæringen

Hvis erklæringen endres, publiseres den nye versjonen her med ny dato.

## Kontakt

Kontakt oss via App Store-siden for Meal Shuffler.
