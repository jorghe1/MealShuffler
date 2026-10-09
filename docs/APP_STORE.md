# App Store Connect metadata (proposal)

Proposed listing for Meal Shuffler 0.6.0, in Norwegian Bokmål (primary) and English (UK/US).
Nothing here is submitted yet. Character counts were checked against Apple's limits; recount
after any edit. The primary market is Norway, so set **Norwegian (Bokmål)** as the primary
language and add **English (U.K.)** and **English (U.S.)** with the English text.

Every claim below must be true of the build that is submitted. Lines that depend on phase 4–5
work are listed in [Check before submission](#check-before-submission); remove them if that
feature does not ship.

---

## Name and subtitle

| Field | Limit | Norsk (Bokmål) | English |
| --- | --- | --- | --- |
| App name | 30 | `Meal Shuffler` (13) | `Meal Shuffler` (13) |
| Subtitle | 30 | `Middagsplan for familien` (24) | `Family dinner planner` (21) |

Keep the same name in both languages: it matches the icon, the share pages and the bundle
display name. If a Norwegian name is wanted for search, `Meal Shuffler: Middagsplan` (26)
fits, and the subtitle then becomes `Ukemeny og handleliste` (22) so words are not repeated.
Apple indexes the name and subtitle as keywords, so do not repeat their words in the keyword
field.

## Promotional text (≤ 170, can change without a new build)

**Norsk** (117):

> Skriv reglene slik dere sier dem – «fredagstaco», «fisk to ganger i uka» – og stokk uka.
> Handlelisten lager seg selv.

**English** (131):

> Write your rules the way you say them – "taco Friday", "fish twice a week" – and shuffle
> the week. The shopping list writes itself.

## Description (≤ 4000)

### Norsk (1,974 characters)

```
Middagen er bestemt før noen rekker å spørre.

Meal Shuffler planlegger ukas middager etter familiens egne regler. Skriv reglene slik dere sier dem – «fredagstaco», «fisk to ganger i uka», «laks på torsdag», «maks 30 minutter på hverdager» – og stokk uka. Handlelisten lager seg selv.

UKA PÅ ETT TRYKK
• Stokk hele uka, eller bare én dag. Lås dagene som allerede er bestemt.
• Velg retten selv når du vil, eller be om noe raskere, billigere eller en favoritt.
• Angre en stokking med ett trykk.
• Planlegg neste uke mens denne pågår.

REGLER MED EGNE ORD
• Skriv på norsk eller engelsk. Appen viser hvordan den forsto regelen før den lagres.
• En regel kan være fast («pizza på lørdag») eller bare et ønske.
• Ingen gjentakelser på tre uker, ikke pasta to dager på rad, kjøttfri mandag.
• Appen sier fra når to regler krasjer, og hvilke.

HANDLELISTEN ER KLAR
• Ingrediensene fra hele uka samles, skaleres til antall som spiser og sorteres etter avdeling i butikken.
• Salt, olje og andre basisvarer holdes utenfor. Det dere har hjemme, legges til side.
• Del listen, eller legg den i Påminnelser.

VARSLER SOM IKKE MASER
• Høyst ett varsel om dagen: kveldens middag, når det er på tide å begynne, handledag, og når noe må tas ut av fryseren.
• Trykk «Vi lagde den» rett fra varselet.

FOR HELE FAMILIEN
• Hvem som spiser, hva hver enkelt liker, og hvem som lager maten.
• Barnevisning: barna ser ukas middager og kan ønske seg en rett.
• Kjøkkenmodus på iPad: uka og oppskriften synlig på benken.
• Widgeter på Hjem-skjermen og låseskjermen viser kveldens middag.

OPPSKRIFTENE DERES
• 40 hverdagsretter med fremgangsmåte følger med, fra ovnsbakt laks til taco.
• Legg til egne fra en lenke, et bilde av en kokebokside, kopiert tekst eller for hånd.
• Matlagingsmodus med steg for steg og tidtaker.
• Send husreglene eller en oppskrift til en venn som en lenke.

PRIVAT SOM STANDARD
Ingen konto, ingen reklame og ingen sporing. Planene og oppskriftene ligger på telefonen.
```

### English (2,027 characters)

```
Dinner is decided before anyone asks.

Meal Shuffler plans the week's dinners around your family's own rules. Write them the way you say them – "taco Friday", "fish twice a week", "salmon on Thursday", "max 30 minutes on weekdays" – and shuffle the week. The shopping list writes itself.

THE WEEK IN ONE TAP
• Shuffle the whole week, or just one day. Lock the days that are already decided.
• Pick a dish yourself whenever you want, or ask for something quicker, cheaper or a favourite.
• Undo a shuffle with one tap.
• Plan next week while this one is still going.

RULES IN YOUR OWN WORDS
• Write in English or Norwegian. The app shows how it read the rule before saving it.
• A rule can be fixed ("pizza on Saturday") or just a preference.
• No repeats within three weeks, no pasta two days in a row, meatless Monday.
• The app tells you when two rules clash, and which ones.

THE SHOPPING LIST IS READY
• Ingredients from the whole week are combined, scaled to how many are eating and sorted by aisle.
• Salt, oil and other staples stay off the list. What you already have is set aside.
• Share the list, or send it to Reminders.

REMINDERS THAT DON'T NAG
• At most one notification a day: tonight's dinner, when to start cooking, shopping day, and when something needs to come out of the freezer.
• Tap "We cooked this" right from the notification.

FOR THE WHOLE FAMILY
• Who is eating, what each person likes, and who is cooking.
• Kids view: children see the week's dinners and can wish for a dish.
• Kitchen mode on iPad: the week and the recipe in view on the counter.
• Home Screen and Lock Screen widgets show tonight's dinner.

YOUR RECIPES
• 40 everyday dinners with instructions included, from baked salmon to tacos.
• Add your own from a link, a photo of a cookbook page, copied text, or by hand.
• Cook mode with step-by-step instructions and a timer.
• Send your house rules or a recipe to a friend as a link.

PRIVATE BY DEFAULT
No account, no ads and no tracking. Your plans and recipes stay on your phone.
```

Not mentioned on purpose: online recipe reading (off by default and needs the service),
Send to Bring! (needs the service), iCloud household sharing (hidden), community (hidden).
Add them to the listing only in the release that turns them on.

## Keywords (≤ 100, comma-separated, no spaces after commas)

Words already in the name or subtitle are left out.

**Norsk** (98):

```
middag,ukemeny,handleliste,middagsplanlegger,oppskrifter,ukeplan,matplan,handlelapp,barn,taco,fisk
```

**English** (97):

```
meal plan,weekly menu,grocery list,shopping list,recipes,kids,cook,week,organizer,supper,rotation
```

Do not add competitor or partner brand names (for example "Bring") to keywords.

## Category and age rating

- **Primary category:** Food & Drink. **Secondary:** Lifestyle.
- **Age rating:** answer "None" to every content question. The app has no user-generated
  content shown to strangers (friend links are private), no web browser, no chat, no
  gambling, no purchases. Built-in recipes contain no alcohol. Expected result: **4+**.
- **Made for Kids:** no. The kids view is a mode inside a parent's app, not an app for
  children; opting into the Kids category would add restrictions (no external links, parental
  gates) the app is not built for.

## Screenshot plan

Required sizes: iPhone 6.9" (1320 × 2868), and iPad 13" (2064 × 2752) if the iPad build ships.
Take them in Norwegian for the Norwegian listing and English for the English one, light mode,
with the built-in meals and a realistic family. One caption per frame, short, above the
device.

| # | Screen | Caption (nb) | Caption (en) |
| --- | --- | --- | --- |
| 1 | Week tab mid-shuffle, rows landing, rule chip popping onto Friday | Stokk uka. Ferdig. | Shuffle the week. Done. |
| 2 | Rule composer with «laks på torsdag» typed, words highlighted, "laks: laksretter eller all fisk?" | Skriv regler slik dere sier dem | Write rules the way you say them |
| 3 | Week list: tonight card, seven days, active rules as chips | Hele uka på ett blikk | The whole week at a glance |
| 4 | Handle tab: progress, aisle sections, staples hidden | Handlelisten lager seg selv | The shopping list writes itself |
| 5 | Familie tab with members and tastes, or the kids view with a wish | Hele familien er med | The whole family has a say |
| 6 | Home Screen and Lock Screen widgets with tonight's dinner | Kveldens middag, rett på skjermen | Tonight's dinner, right on your screen |
| 7 | Notification "I kveld: Taco" with "Vi lagde den" | Ett varsel om dagen, ikke mer | One reminder a day, no more |
| 8 (iPad) | Kitchen board on iPad, week and recipe side by side | Kjøkkenmodus på iPad | Kitchen mode on iPad |

Frames 5, 6 and 8 depend on phase 4–5 work; see below. Use real rendered screens from a
simulator or device, not mockups.

## App Review notes

Paste into App Review Information → Notes:

```
Meal Shuffler needs no account and no login. Everything can be tried on a fresh install:

1. Onboarding: swipe a few dinners left/right, then tap Shuffle to get the first week. Allow notifications when asked to see reminders.
2. Week tab: tap Shuffle, swipe a day to lock it, tap a day to pick a dish.
3. Rules: Family tab → "Write your first rule" / "All rules". Type "fish on Tuesday" or "max 30 minutes on weekdays" (English or Norwegian). The app shows how it read the rule before saving.
4. Shop tab: the shopping list is built from the week.
5. Meals tab: "+" adds a recipe from a link, pasted text, a photo or by hand. Recipes are read on the device.

Online recipe reading (sending an imported recipe to our server, which uses Anthropic's Claude) is OFF by default and is not configured in this build, so no recipe content leaves the device. When it is configured, Family tab → gear (Settings) → Recipe imports shows a switch that asks for consent before anything is sent.

iCloud household sharing and the community feature are disabled in this build and not visible.

Background App Refresh is used only to turn the week over and reschedule local reminders. Notifications are local; there is no push server.

Privacy policy: <privacy URL>. Support: <support URL>.
```

If the Worker is deployed and `RECIPE_SERVICE_BASE_URL` is set for the submitted build,
replace the "not configured" sentence with: "To test it, open Family → gear (Settings) → Recipe imports,
turn on Read recipes online, accept the prompt, then import any recipe link."

Add a line for each permission the submitted build asks for (camera for scanning, photo
library for saving the week image, Reminders for exporting the list, and Calendar if busy
evenings ship), saying when the prompt appears.

## Privacy nutrition label

Consistent with [PRIVACY.md](PRIVACY.md) and `MealShuffler/PrivacyInfo.xcprivacy` (the
widget and share extension manifests declare no collection).

**Tracking:** No. No data is used to track users. No tracking domains.

**Data collected:** declare the three types the manifest declares, all with the same answers.
They are collected only when online recipe reading is on (opt-in) or a share/Bring! page is
served, but the label describes the app's capability, and declaring it keeps the label, the
manifest and the policy in step.

| Data type (App Store Connect) | Collected | Linked to the user | Used for tracking | Purpose |
| --- | --- | --- | --- | --- |
| User Content → Other User Content (recipe links and text) | Yes | No | No | App Functionality |
| User Content → Photos or Videos (recipe photos) | Yes | No | No | App Functionality |
| Identifiers → Device ID (random per-install id, rate limiting only) | Yes | No | No | App Functionality |

Not collected, so not declared: contact info, health, financial info, location (the IP address
is used only for rate limiting and not stored), contacts, browsing or search history, usage
data, diagnostics, purchases. Data in the user's own iCloud is not accessible to the developer
and is not "collected".

If online recipe reading is removed from a build entirely, "Data Not Collected" becomes
accurate, but only after the manifest and PRIVACY.md are changed to match.

**Privacy policy URL:** the Worker's `/privacy` (served from [PRIVACY.md](PRIVACY.md) via
`server/src/info.ts`), or another host if the Worker is not deployed for 0.6.0.

## Business model

**Decision for the owner — not decided.**

- **Free core, no ads, no tracking.** Planning, rules, shopping list, reminders, widgets, kids
  view and on-device import stay free. This matches the privacy promise and is what 0.6.0
  ships as.
- **Paid tier later for features that cost money per use.** Online recipe reading and the AI
  rule fallback both make a model call; a subscription or one-time unlock could cover them
  once they ship in the network release. Needs StoreKit, a paywall that does not block the
  free core, a restore-purchases path, and receipt or entitlement checks on the Worker
  (pairs naturally with App Attest).
- **Alternatives:** one-time "supporter" purchase with no feature gate; or keep everything
  free and cap AI use with the daily budget.

Whatever is chosen, the App Store listing must say which features need a purchase.

## Check before submission

Remove a line, screenshot or keyword if its feature is not in the submitted build.

All of these are in 0.6.0 (see [ROADMAP.md](ROADMAP.md#added-in-060)); the table stays as the list
to re-check on a device before each submission.

| Depends on | Description line (nb / en) | Screenshot |
| --- | --- | --- |
| Who cooks (phase 5) | «…og hvem som lager maten» / "…and who is cooking" | — |
| Kids view (phase 5) | «Barnevisning…» / "Kids view…" | 5 (optional) |
| iPad kitchen board (phase 5) | «Kjøkkenmodus på iPad…» / "Kitchen mode on iPad…" | 8 |
| Lock-screen widgets (phase 4) | «…og låseskjermen» / "…and Lock Screen" | 6 |
| Calendar busy evenings (phase 5) | not in the description; add a line if it ships | — |
| iPad support (`TARGETED_DEVICE_FAMILY`) | iPad screenshots required | 8 |
