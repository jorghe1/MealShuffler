# Produktretning: import, lansering og videre arbeid

Skrevet 12. oktober 2026, etter 0.7.1. Dette er beslutningene og vurderingene fra
gjennomgangen av 0.6.0–0.7.1, samlet for videre arbeid. Status og detaljert backlog står i
[ROADMAP.md](ROADMAP.md), navigasjonsprinsippene i [NAVIGATION.md](NAVIGATION.md) og
synkdesignet i [ADR 0001](adr/0001-entity-sync-and-store-split.md).

## 1. Oppskriftsimport: hvorfor KI, og hvor

### Slik gjorde apper det før KI

Paprika, Recipe Keeper, Mela, Whisk og lignende brukte tre teknikker:

1. **schema.org `Recipe` på nettsider.** De fleste store oppskriftssider (Matprat, Tine,
   Godt.no) legger oppskriften inn i siden som strukturert JSON: ingredienser, mengder,
   porsjoner og tid. Gratis, øyeblikkelig og nesten feilfritt. Fortsatt den beste løsningen for
   lenker.
2. **Egne lesere per nettsted** for sider uten strukturerte data. Skjørt; brekker når siden
   endres.
3. **Tekstgjenkjenning (OCR) pluss regler** for bilder og innlimt tekst. Bokstavene ble lest
   godt, men strukturen («ingrediens, overskrift eller serveringsforslag?», «2–3 fedd»,
   «1 boks (400 g)») ble lest dårlig. Paprika lot derfor brukeren merke feltene selv.

### Slik gjør Meal Shuffler det (`MealShuffler/Services/RecipeCapture.swift`)

- **Lenker:** appens egen leser av strukturerte data først (lokalt, gratis, privat). KI bare
  når siden mangler slike data.
- **Tekst og bilder:** KI først, når husstanden har slått på «Les oppskrifter på nett».
  Appens egen OCR og regler er reserve uten nett.

KI brukes altså der de gamle metodene var svake, ikke der de allerede var gode.

### Modellvalg (testet 12. oktober 2026)

`server/eval/` scorer en utrulling mot 24 norske tekstoppskrifter (porsjoner, antall
ingredienser, tid og nøkkelmengder).

| Modell | Poeng | Tid per oppskrift | Pris (inn/ut per million tokens) |
|---|---|---|---|
| `claude-opus-5` | 98,8 % | 8,9 s | $5 / $25 |
| `claude-sonnet-5-5` | 98,8 % | 5,1 s | $2 / $10 |
| **`claude-haiku-5-5`** (i produksjon) | 97,7 % | 4,2 s | $0,10 / $0,50 |

Haikus eneste avvik var et tilbehør skrevet som «til servering», som systemprompten ber den
utelate. En import koster under én øre; full døgnkvote (200 kall) et par kroner.

**Åpent:** settet har ingen bilder av kokebøker. Legg til 5–10 fotograferte sider og kjør
`node eval/run-eval.mjs <adresse> <navn>` før KI-import av bilder markedsføres. Leser Haiku
bilder dårligere, byttes modellen med `EXTRACTION_MODEL` i `server/wrangler.toml`.

### Alternativer vurdert

| Alternativ | Fordel | Ulempe |
|---|---|---|
| **Haiku via serveren (nå)** | Best kvalitet per krone, alle iPhoner | Krever nett og samtykke; data går til Anthropic |
| Apples KI på telefonen (Foundation Models, iOS 26) | Gratis, privat, uten nett | Bare nyere iPhoner (15 Pro og nyere), svakere modell; norsk-støtte må sjekkes |
| Bare OCR og regler | Helt lokalt | Det dårlige utgangspunktet fra før KI |

**Beslutning:** behold Haiku via serveren. Apples modell kan senere bli et ekstra første trinn
for støttede telefoner, av personvernhensyn.

## 2. Beslutninger tatt 12. oktober 2026

| # | Spørsmål | Beslutning |
|---|---|---|
| 1 | Familiedeling mellom telefoner i 1.0? | **Vent.** Lanser for én enhet først. Krever ny datamodell (ADR 0001). |
| 2 | KI-modell for import | **Haiku 5.5**, valgt med testsettet over. |
| 3 | Døgnkvote for KI-kall | **200 per døgn**, beholdt. Billig med Haiku, og beskytter mot misbruk. |
| 4 | Cloudflare-logger | **Beholdt**: uten query string (Bring-listen) og uten logg per kall. |
| 5 | Kontakt-e-post på support-siden | **Ikke ennå.** Sidene viser til App Store-siden. |
| 6 | Eget domene | **workers.dev foreløpig.** Adressen inneholder eierens navn; flytt før offentlig lansering. |
| 7 | Installasjons-ID | **Delt i to** (0.7.1): tjenesten ser en egen nøkkel, ikke ID-en som merker oppskrifter. |
| 8 | «du» eller «dere» | **Etter husstand** (0.7.1): ett medlem og vanligvis én til middag gir «du/mine», ellers «dere/våre». `L10n.household`, `Solo.strings`. |
| 9 | TestFlight-distribusjon | **Manuelt** for nå (`submit_to_testflight: false`). |

## 3. Før offentlig App Store-lansering

TestFlight-testing kan skje nå. Før appen lanseres offentlig:

1. **Eget domene og kontakt-e-post.** Koble domenet til Workeren under Workers → Custom
   Domains, sett `SUPPORT_EMAIL` i `server/wrangler.toml`, oppdater
   `RECIPE_SERVICE_BASE_URL` i `project.yml` og adressene i App Store Connect.
2. **App Attest**, hvis KI-importen skal markedsføres (se under).
3. **Skjermbilder og App Store-tekst.** Utkastet ligger i [APP_STORE.md](APP_STORE.md).
4. **En runde med sjekklisten på ekte telefon** ([ROADMAP.md](ROADMAP.md), 0.7.0 og 0.7.1).
5. **Bilder av kokebøker i modelltesten** (se 1).
6. **Codemagic-utløser:** legg inn `CODEMAGIC_API_TOKEN` (secret) og `CODEMAGIC_APP_ID`
   (variabel) i GitHub, så starter en `ios-*`-tag bygget selv. Se [CODEMAGIC.md](CODEMAGIC.md).

### App Attest

- **Problemet:** døgnkvoten på 200 KI-kall deles av alle. Noen som roterer IP-adresser kan
  bruke den opp på minutter, og da virker import ikke for noen resten av døgnet. Det koster
  ikke penger (taket holder), men funksjonen blir utilgjengelig.
- **Løsningen:** appen lager en nøkkel med `DCAppAttestService`, Apple bekrefter den, og
  serveren lagrer nøkkelen i en Durable Object. Hvert kall signeres, og kvoten kan settes per
  enhet (for eksempel 20 i døgnet).
- **Innsats:** 2–4 dager, pluss å slå på App Attest for App ID-en i Apple Developer.
- **Billigere mellomsteg:** DeviceCheck (enklere, svakere).

## 4. Senere, rangert etter verdi for norske familier

1. **Ekte priser fra norske butikker.** Kassalapp har et gratis API med varer og priser fra
   Rema, Kiwi, Meny og andre. «Noe billigere» bruker i dag anslåtte priser; ekte priser og ukens
   tilbud ville skilt appen fra konkurrentene.
2. **Familiedeling mellom telefoner.** Krever ny datamodell: hver ting som egen post med ID og
   endringstid, synk per post med CKSyncEngine, konfliktregler, og at bare én enhet ruller over
   til ny uke. 4–6 uker i seks faser; planen står i
   [ADR 0001](adr/0001-entity-sync-and-store-split.md).
3. **Apples KI på telefonen** som første trinn i importen (se 1).
4. **Eksport til Oda** og lignende nettbutikker, ved siden av Bring.
5. **Opprydding fra korrekturen:** en samlet gjennomgang av «du/dere» i tekster utenfor de 16
   som nå følger husstanden.

## 5. Prinsipp for videre arbeid

**Lanser kjernen, og la bruk styre rekkefølgen.** Appen har allerede mer funksjonalitet enn de
fleste konkurrentene; det som mangler er bruk i ekte familier. Appen har ingen analyseverktøy
(et bevisst personvernvalg), så tilbakemeldinger fra familien og TestFlight-testerne er det som
bør prioritere listen over. Nye funksjoner skal følge regelen i
[NAVIGATION.md](NAVIGATION.md): ett sted per funksjon, i fanen som svarer på spørsmålet den
hører til.
