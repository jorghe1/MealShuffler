# Meal Shuffler

En native SwiftUI-app for enkel, regelstyrt middagsplanlegging.

## Dette er med

- Swipe-onboarding som lærer hvilke hverdagsretter familien liker, og som spør om
  varsler i det øyeblikket den første uka står ferdig på skjermen.
- Regelbygger som dekker det familier faktisk sier: dagregler, ukentlige
  minimum og maksimum, tidsgrenser, dagsplan (spise ute, rester, ingen middag),
  ingen gjentakelser innen N uker, hent tilbake og ikke to dager på rad — som
  harde eller myke regler.
- En lokal planmotor som respekterer låste dager og forklarer regelkonflikter.
- Ukevisning forankret i en ekte kalenderuke, med automatisk ukeskifte,
  arkivert historikk og planlegging av neste uke.
- **Velg middagen selv**: en rettvelger per dag, og «legg på en dag» fra
  rettbiblioteket og fra historikken. Dagen låses, så valget overlever neste stokking.
- **Angre**: stokking, bytte av dager, dagsplan og pauser kan tas tilbake i ett trykk.
- Dagskontekst for antall personer, tidsgrense, ekstra porsjoner, rester,
  takeaway og dager borte.
- Intensjonsbasert bytte: raskere, billigere, favoritt eller overraskelse.
- Fire veier inn i biblioteket: manuell registrering, lenke (JSON-LD med
  microdata som reserve), skanning av kokebokside eller skjermbilde, og innliming
  av fritekst. Alt som leses av seg selv havner i redigeringen med ingrediensene
  tolket, kategorier gjettet og et varsel om at det bør sjekkes.
- Automatisk, kategorisert handleliste med porsjonsskalering og
  enhetsnormalisering, og eksport til Apple Påminnelser eller iOS-deling.
- Middager hentet fra en lenke kan sendes rett til Bring!.
- Basisvarer: salt, olje og mel skjules fast fra handlelisten i stedet for å
  hukes av på nytt hver uke.
- Lokal historikk med rotasjonsvisning: hva dere har laget, og hva som er lengst
  siden sist.
- Ukesammensetning som viser fordelingen mellom fisk, kylling, kjøtt og vegetar.
- Lys og mørk modus, Dynamic Type og VoiceOver-merking.
- Lokal lagring bak `AppStateRepository`; ingen konto eller backend kreves.
- Engelsk som utviklings- og kildespråk, med komplett norsk Bokmål-lokalisering.

Biblioteket har 40 innebygde retter med fremgangsmåte, fordelt over fisk, kylling,
kjøtt, vegetar, pizza, pasta, suppe og taco — nok til at «fisk to dager i uka» og
«pizza på lørdag» kan oppfylles uten at uka gjentar seg selv.

Appen leveres med startregler som er ment å bli endret:

1. Fisk på tirsdag og torsdag.
2. Kylling maksimalt to ganger i uka.
3. Pizza på lørdag — som kategori, ikke én bestemt pizza.
4. Ingen gjentakelser innen tre uker, som en myk regel.

En regel kan handle om en kategori, én bestemt rett, en ingrediens (der allergier
hører hjemme), en egen merkelapp familien har funnet på, eller om hva ett
familiemedlem ikke liker. Dager kan navngis enkeltvis eller som «hverdager»,
«helgen» og «hver dag». Appen nekter å lagre en regel som sier det samme som en
regel som allerede finnes, eller som motsier den, og forteller hvilken.

Community-fanen er slått av bak `FeatureFlags.communityEnabled` til
innlogging og moderering er på plass. Invitasjonskoden er slått av bak
`FeatureFlags.householdSyncEnabled` til det finnes noe i andre enden av den.
Hva som er utelatt med vilje, og hva som skal til for å ta det inn, står i
[docs/ROADMAP.md](docs/ROADMAP.md).

## Varsler

Én daglig påminnelse om hva som er til middag, med knappene «Vi lagde denne» og
«Noe annet» rett i varselet. Valgfritt også en påminnelse om når det er på tide å
begynne å lage mat, og en ukentlig handledag. Når neste uke er tom, kommer én
påminnelse om å planlegge den — ellers ville appen blitt taus fra mandagen etter.

Alt dette settes opp under Innstillinger.

## Oppskriftsimport

Et bibliotek som må skrives inn for hånd blir aldri bygget, så det finnes fire veier inn,
og alle ender samme sted: i redigeringen, med det som ble lest fylt ut på forhånd.

- **Lenke.** Leser `Recipe`-blokker i JSON-LD — alle blokkene på siden, og velger den
  rikeste, slik at en side med «relaterte oppskrifter» ikke importerer teaseren.
  Ingredienser leses i alle formene sider faktisk bruker, og fremgangsmåten følges gjennom
  `HowToSection` ned til hvert steg. Sider uten JSON-LD leses som microdata.
- **Skann.** Flersidig dokumentskanning av en kokebokside. Linjene sorteres i leserekkefølge,
  ikke i den rekkefølgen Vision svarer, og tittelen er den største teksten øverst — ikke den
  øverste linjen, som på et skjermbilde er statuslinjen.
- **Lim inn.** En kopiert oppskrift fra en melding eller en nettside, uten at tjenesten må
  være satt opp.
- **Manuelt.** Som før, med ingrediensene tolket mens du skriver.

Alt som gjettes merkes «sjekk detaljene før du lagrer», ingrediensene vises slik
handlelisten vil lese dem, med avdeling per linje, og appen sier fra hvis navnet finnes
i biblioteket fra før. Importerte retter får kategorier, slik at de er synlige for reglene
med én gang — en laksemiddag hentet fra en lenke kan oppfylle «fisk på tirsdag».

Tjenesten i `server/` leser prosa bedre enn heuristikkene over og får første forsøk når den
er satt opp. Den er ikke satt opp som standard: `RECIPE_SERVICE_BASE_URL` i `project.yml` er
tom, og appen blir da værende på egne parsere. Se [server/README.md](server/README.md).

## Fanene

`Uke` · `Handle` · `Retter` · `Regler` · `Innstillinger`

Innstillinger samler familie, historikk, butikkrekkefølge, basisvarer, varsler og
onboarding-omstart. Regler beholder sin egen fane: de er det appen handler om.

## Kjøring

Prosjektet krever Xcode 26.4 eller nyere og iOS 17 eller nyere. Fra en Mac:

```sh
make open
```

Velg en iPhone-simulator og kjør `MealShuffler`-scheme. Testene ligger i
`MealShufflerTests`.

Oppskriftstjenesten er avslått som standard. Skal den brukes, settes
`RECIPE_SERVICE_BASE_URL` i `project.yml` — eller per build:

```sh
xcodebuild ... RECIPE_SERVICE_BASE_URL=https://your-worker.workers.dev
```

Prosjektet har også Codemagic-workflows for usignert simulator-test og signert
TestFlight-opplasting. Se [docs/IPHONE_TESTING.md](docs/IPHONE_TESTING.md) for
engangsoppsett og første test på en fysisk iPhone.

Appen følger språkinnstillingen i iOS. Engelsk innhold er kildetekst, mens norsk
Bokmål ligger i `nb.lproj`. Dynamisk tekst fra planmotor, eksport og feilmeldinger
går gjennom samme lokaliseringslag som SwiftUI-visningene.

## Arkitektur og videre backend

Planleggingen er domenelogikk uten UI- eller nettverksavhengigheter.
`MealPlanGenerator` tar en injisert `RandomSource`, slik at trekningen er
reproduserbar i tester.

Lagret tilstand har et `schemaVersion`-felt og bakoverkompatibel dekoding.
Entiteter bærer `updatedAt`/`updatedBy`, og slettede egne retter beholdes som
gravsteiner — begge deler er nødvendige for en senere synkronisering og kan
ikke rekonstrueres i ettertid. Smakspreferanser lagres per husstandsmedlem.

Tilstanden ligger i en fil i App Group-beholderen (`FileStateRepository`), ikke i
user defaults. Defaults leses inn i minnet i sin helhet og skrives i sin helhet, og
blobben vokser med 26 arkiverte uker, inntil 2000 tilbakemeldinger og et bibliotek
med fremgangsmåter — som begge utvidelsene også må dekode for å svare på «hva er til
middag». Eksisterende installasjoner flyttes over én gang, og den gamle kopien
fjernes først når filen er skrevet og lest tilbake.

Fem protokoller er sømmene mot en backend eller mot en test:

- `AppStateRepository` — hvor appens tilstand bor.
- `RecipeExtractor` — oppskriftsuttrekk, lokalt først og tjeneste som fallback.
- `CommunityRepository` — community.
- `WidgetRefreshing` — når hjemmeskjermen må tegnes på nytt.
- `ReminderScheduling` — varselplanen.

De to siste finnes fordi widgeten og varslene tidligere ble oppdatert fra hvilken
som helst metode som husket å gjøre det. Widgeten ble aldri oppdatert i det hele
tatt, og bytte av to dager hoppet over varslene — begge annonserte retter som var
byttet ut. Nå går begge gjennom én skrivetrakt i `AppStore`.

## Sjekker

`ci/` inneholder fire rene Python-sjekker som kjører før xcodegen, og som også
kjører gratis på Linux i GitHub Actions:

```sh
python3 ci/validate-localizations.py    # norsk lokalisering mot kildetekst
python3 ci/check-localized-format.py    # argumenter mot formatstrenger
python3 ci/check-swift-structure.py     # klammebalanse, døde symboler, duplikater
python3 ci/check-store-api.py           # visningenes bruk av AppStore
```

Tjenesten i `server/` har sine egne:

```sh
cd server && npm ci && npm run check    # tsc --noEmit, så enhetstestene
```

> Dette arbeidsområdet ble opprettet på Windows, så selve Xcode-builden må gjøres
> på macOS. Prosjektbeskrivelsen og kildekoden er uten tredjepartsavhengigheter.
