# Meal Shuffler

En native SwiftUI-app for enkel, regelstyrt middagsplanlegging.

## Dette er med

- Swipe-onboarding som lærer hvilke hverdagsretter familien liker, og som spør om
  varsler i det øyeblikket den første uka står ferdig på skjermen.
- Regelbygger med dagregler, ukentlige minimum og maksimum, som harde eller
  myke regler.
- En lokal planmotor som respekterer låste dager og forklarer regelkonflikter.
- Ukevisning forankret i en ekte kalenderuke, med automatisk ukeskifte,
  arkivert historikk og planlegging av neste uke.
- **Velg middagen selv**: en rettvelger per dag, og «legg på en dag» fra
  rettbiblioteket og fra historikken. Dagen låses, så valget overlever neste stokking.
- **Angre**: stokking, bytte av dager, dagsplan og pauser kan tas tilbake i ett trykk.
- Dagskontekst for antall personer, tidsgrense, ekstra porsjoner, rester,
  takeaway og dager borte.
- Intensjonsbasert bytte: raskere, billigere, favoritt eller overraskelse.
- Egne retter med manuell registrering, schema.org-import fra lenke og
  strukturert tekstgjenkjenning fra bilde.
- Automatisk, kategorisert handleliste med porsjonsskalering og
  enhetsnormalisering, og eksport til Apple Påminnelser eller iOS-deling.
- Lokal historikk med rotasjonsvisning: hva dere har laget, og hva som er lengst
  siden sist.
- Ukesammensetning som viser fordelingen mellom fisk, kylling, kjøtt og vegetar.
- Lys og mørk modus, Dynamic Type og VoiceOver-merking.
- Lokal lagring bak `AppStateRepository`; ingen konto eller backend kreves.
- Engelsk som utviklings- og kildespråk, med komplett norsk Bokmål-lokalisering.

Biblioteket har 40 innebygde retter med fremgangsmåte, fordelt over fisk, kylling,
kjøtt, vegetar, pizza, pasta, suppe og taco — nok til at «fisk to dager i uka» og
«pizza på lørdag» kan oppfylles uten at uka gjentar seg selv.

MVP-en leveres med fire aktive startregler:

1. Fisk på tirsdag og torsdag.
2. Kylling maksimalt to ganger i uka.
3. Pizza på lørdag — som kategori, ikke én bestemt pizza.

Community-fanen er slått av bak `FeatureFlags.communityEnabled` til
innlogging og moderering er på plass. Invitasjonskoden er slått av bak
`FeatureFlags.householdSyncEnabled` til det finnes noe i andre enden av den.

## Varsler

Én daglig påminnelse om hva som er til middag, med knappene «Vi lagde denne» og
«Noe annet» rett i varselet. Valgfritt også en påminnelse om når det er på tide å
begynne å lage mat, og en ukentlig handledag. Når neste uke er tom, kommer én
påminnelse om å planlegge den — ellers ville appen blitt taus fra mandagen etter.

Alt dette settes opp under Innstillinger.

## Fanene

`Uke` · `Handle` · `Retter` · `Regler` · `Innstillinger`

Innstillinger samler familie, historikk, butikkrekkefølge, varsler og
onboarding-omstart. Regler beholder sin egen fane: de er det appen handler om.

## Kjøring

Prosjektet krever Xcode 26.4 eller nyere og iOS 17 eller nyere. Fra en Mac:

```sh
make open
```

Velg en iPhone-simulator og kjør `MealShuffler`-scheme. Testene ligger i
`MealShufflerTests`.

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
