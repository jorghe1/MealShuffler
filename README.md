# Meal Shuffler

En native SwiftUI-app for enkel, regelstyrt middagsplanlegging. Versjon 0.6.0.

Hva som er levert, hva som kommer i neste versjon og hva som venter, står samlet i
[docs/ROADMAP.md](docs/ROADMAP.md). Eldre gjennomganger og statusrapporter ligger i
[docs/history/](docs/history/).

## Dokumentasjon

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — mål, mappestruktur, tilstandsflyt, planmotor,
  varsler, utvidelser, import, deling, lokalisering og CI.
- [DESIGN.md](DESIGN.md) — designsystemet (`AppTheme`), fanene, knappestiler, bildepolicy og
  arbeidsflytkontrakten.
- [docs/ROADMAP.md](docs/ROADMAP.md) — status og backlog.
- [docs/APP_STORE.md](docs/APP_STORE.md) — forslag til App Store-tekster, skjermbilder,
  personvernsvar og notater til App Review.
- [docs/PRIVACY.md](docs/PRIVACY.md) — personvernerklæringen (norsk og engelsk).
- [docs/CODEMAGIC.md](docs/CODEMAGIC.md) — byggene i Codemagic og TestFlight.
- [docs/IPHONE_TESTING.md](docs/IPHONE_TESTING.md) — første test på fysisk iPhone.
- [docs/ICLOUD_SHARING.md](docs/ICLOUD_SHARING.md) — iCloud-deling (av i 0.6.0).
- [docs/history/](docs/history/) — daterte gjennomganger og statusrapporter.

## Dette er med

- Swipe-onboarding som lærer hvilke hverdagsretter familien liker, og som spør om
  varsler i det øyeblikket den første uka står ferdig på skjermen.
- Regelbygger som dekker det familier faktisk sier: dagregler, ukentlige
  minimum og maksimum, tidsgrenser, dagsplan (spise ute, rester, ingen middag),
  ingen gjentakelser innen N uker, hent tilbake og ikke to dager på rad — som
  regler som må følges, eller ønsker. Dagsplaner er faste avtaler med unntak per uke.
- En lokal planmotor som respekterer låste dager og forklarer regelkonflikter.
- Ukevisning forankret i en ekte kalenderuke, med automatisk ukeskifte,
  arkivert historikk og planlegging av neste uke.
- **Velg middagen selv**: en rettvelger per dag, og «velg dag» fra
  rettbiblioteket og fra historikken. Dagen låses, så valget overlever neste stokking.
- **Angre**: stokking, bytte av dager, dagsplan og pauser kan tas tilbake i ett trykk.
- Dagskontekst for antall personer, tidsgrense, ekstra porsjoner, rester,
  takeaway og dager borte.
- Intensjonsbasert bytte: raskere, billigere, favoritt eller overraskelse.
- Fire veier inn i biblioteket: manuell registrering, lenke (JSON-LD med
  avgrenset microdata som reserve), skanning av kokebokside eller skjermbilde, og innliming
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

En regel kan handle om en kategori, én bestemt rett, et ingrediensnavn (uten verifisering av allergener), en egen merkelapp familien har funnet på, eller om hva ett
familiemedlem ikke liker. Dager kan navngis enkeltvis eller som «hverdager»,
«helgen» og «hver dag». Appen nekter å lagre en regel som sier det samme som en
regel som allerede finnes, eller som motsier den, og forteller hvilken.

Community er slått av bak `FeatureFlags.communityEnabled` til innlogging og moderering er på
plass. iCloud-deling i husstanden er slått av bak `FeatureFlags.householdSyncEnabled` i 0.6.0
og erstattes av synkronisering per enhet i neste versjon; se
[docs/ICLOUD_SHARING.md](docs/ICLOUD_SHARING.md). Hva som er utelatt med vilje, og hva som
skal til for å ta det inn, står i [docs/ROADMAP.md](docs/ROADMAP.md).

## Nye arbeidsflyter

- Handleperioder på tvers av inneværende uke, neste uke og arkivet, med egen handlefremdrift.
- Porsjonsstørrelser, fryseporsjoner på tvers av uker, oppskriftssamlinger og kjøkkentimer.
- Full sikkerhetskopi med gjenopprettingskopi, utkast, bilder og tidligere oppskriftsversjoner.
- Redigering av regler, konflikthjelp og samme middagskort i begge ukevisninger.
- Venn-til-venn-deling uten konto: husregler, én oppskrift, en samling eller ukas oppskrifter
  sendes som en lenke som bærer innholdet selv etter `#`. Egne regler overstyres aldri.
- Uka som 9:16-bilde, med husstandens regler ved dagene de avgjorde.

## Varsler

Høyst ett varsel om dagen, men det som ellers ville blitt et nytt varsel samme dag, står i det:

- **I kveld: <rett>**, med «Vi lagde den» og «Noe annet» på dager det lages mat. Takeaway og
  rester har ingen knapper, siden det ikke er noe å registrere.
- **På tide å begynne å lage mat**, når det er slått på.
- **Handledag** sier hvor mange middager lista gjelder og hva som er til middag samme kveld.
- Kvelden før en middag fra fryseren står det at den må tas ut.
- Den siste dagen i uka står det om neste uke fortsatt er tom, med «Stokk neste uke».
- En uke ingen har planlagt, får ett varsel den første kvelden.

Bakgrunnsoppdatering snur uka og planlegger varslene på nytt når uka skifter, også om appen ikke
åpnes. Trykk på et varsel åpner riktig sted. Oppsettet ligger under Familie → Påminnelser.

## Oppskriftsimport

Et bibliotek som må skrives inn for hånd blir aldri bygget, så det finnes fire veier inn,
og alle ender samme sted: i redigeringen, med det som ble lest fylt ut på forhånd.

- **Lenke.** Leser `Recipe`-blokker i JSON-LD — alle blokkene på siden, med oppskriftens nettadresse som første valg
  før mengden innhold vurderes. Relaterte oppskrifter skal ikke fortrenge hovedoppskriften.
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

`Uke` · `Retter` · `Handle` · `Familie`

I rekkefølgen uka går: planlegge, velge retter, handle, og familien reglene hører til.

- **Uke** viser i kveld øverst, så sju kompakte dager (sveip for å låse eller trekke på nytt,
  trykk for alt annet), og én knapp som stokker det som kan endres. Neste uke er en bryter
  øverst, og de aktive reglene vises som merkelapper der de bestemmer uka.
- **Retter** er et bildegitter med kategorier, «Lengst siden sist» (historikken) og fryseren.
  «+» åpner fem kilder: lenke, lim inn tekst, skann sider, bilder og skriv selv.
- **Handle** begynner med fremdrift og et felt for å legge til en vare. Kjøpt og «har hjemme»
  legger seg sammenfoldet nederst; eksport, handleperiode, basisvarer og butikkrekkefølge
  ligger i ⋯-menyen.
- **Familie** samler husregler, hvem som spiser og hva hver enkelt liker, påminnelser og deling.
  Innstillinger (sikkerhetskopi, oppskriftsimport, personvern) ligger bak tannhjulet.

## Familien rundt uka (0.6.0)

- **Hvem lager** velges per dag i dagsarket og vises i kveld-kortet, på dagene, i widgeten,
  på kjøkkentavla og i påminnelsene.
- **Barnevisning** (Familie → Sammen): kveldens middag, noe barnet kan hjelpe til med, uka som
  bilder, tommel opp/ned på retter og ett ønske til neste uke. Ut krever telefonens kode.
  Ønskene dukker opp under Familie, der en voksen setter dem på en dag eller sier nei takk.
- **Kjøkkenmodus** på iPad: sju kolonner, handleliste og ønsker, skjermen sovner ikke.
- **Widgeter** i alle størrelser og på låseskjermen, med «Vi lagde den» rett fra widgeten, og
  en Live Activity for koketimeren.
- **Bilde etter middag**: etter «Vi lagde den» kan dere ta et bilde som erstatter tegningen.
- **Middagsåret**: året i tall med et kort som kan deles (Historikk eller Familie).
- **Travle kvelder** fra kalenderen, **«bruk opp rømme»** som regel for denne uka, regler som
  ikke kan holde avvises med forklaring, og **færre ting å kjøpe** som valg (Innstillinger →
  Planlegging).
- Rister du telefonen på Uke-fanen, stokkes uka.

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

Den fullstendige beskrivelsen står i [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Kort:

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

`ci/` inneholder fem rene Python-sjekker som kjører før xcodegen, og som også
kjører gratis på Linux i GitHub Actions:

```sh
python3 ci/validate-localizations.py    # norsk lokalisering mot kildetekst
python3 ci/check-localized-format.py    # argumenter mot formatstrenger
python3 ci/check-swift-structure.py     # klammebalanse, døde symboler, duplikater
python3 ci/check-store-api.py           # visningenes bruk av AppStore
python3 ci/check-swift-call-labels.py   # argumentnavn mot funksjonen som kalles
```

Den siste finnes fordi et endret parameternavn er en toleddet endring, og ledd
to er lett å glemme: to kall satt igjen med `context:` etter at parameteren het
`dayContext:`, noe ingen av de andre sjekkene kunne se, og som først falt på
byggemaskinen.

Tjenesten i `server/` har sine egne:

```sh
cd server && npm ci && npm run check    # tsc --noEmit, så enhetstestene
```

> Dette arbeidsområdet ble opprettet på Windows, så selve Xcode-builden må gjøres
> på macOS. Prosjektbeskrivelsen og kildekoden er uten tredjepartsavhengigheter.
