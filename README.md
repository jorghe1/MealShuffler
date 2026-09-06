# Meal Shuffler

En native SwiftUI-MVP for enkel, regelstyrt middagsplanlegging.

## Dette er med

- Swipe-onboarding som lærer hvilke hverdagsretter familien liker.
- Regelbygger med dagregler, ukentlige minimum og maksimum, som harde eller
  myke regler.
- En lokal planmotor som respekterer låste dager og forklarer regelkonflikter.
- Ukevisning forankret i en ekte kalenderuke, med automatisk ukeskifte,
  arkivert historikk og planlegging av neste uke.
- Dagskontekst for antall personer, tidsgrense, ekstra porsjoner, rester,
  takeaway og dager borte.
- Intensjonsbasert bytte: raskere, billigere, favoritt eller overraskelse.
- Egne retter med manuell registrering, schema.org-import fra lenke og
  strukturert tekstgjenkjenning fra bilde.
- Automatisk, kategorisert handleliste med porsjonsskalering og
  enhetsnormalisering, og eksport til Apple Påminnelser eller iOS-deling.
- Valgfri daglig påminnelse om hva som er til middag.
- Lokal historikk og forsiktig preferanselæring med repetisjonskontroll.
- Lys og mørk modus, Dynamic Type og VoiceOver-merking.
- Lokal lagring bak `AppStateRepository`; ingen konto eller backend kreves.
- Engelsk som utviklings- og kildespråk, med komplett norsk Bokmål-lokalisering.

MVP-en leveres med tre aktive startregler:

1. Fisk på tirsdag og torsdag.
2. Kylling maksimalt to ganger i uka.
3. Pizza på lørdag.

Community-fanen er slått av bak `FeatureFlags.communityEnabled` til
innlogging og moderering er på plass.

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

Tre protokoller er sømmene mot en backend:

- `AppStateRepository` — hvor appens tilstand bor. `UserDefaultsStateRepository`
  er den lokale implementasjonen.
- `RecipeExtractor` — oppskriftsuttrekk. De lokale implementasjonene
  (schema.org og OCR) fungerer som rask sti; en tjenestebasert utgave kan legges
  bak `ChainedRecipeExtractor` uten at visningene endres.
- `CommunityRepository` — community. `LocalCommunityRepository` gir et
  persistérbart testmiljø på én enhet.

Offentlig publisering krever aktiv bekreftelse på delingsrettigheter og beholder
originalkilde for nettimport. Autentisering, modereringskø og bildeopplasting må
ferdigstilles før et åpent community.

## Sjekker

`ci/` inneholder tre rene Python-sjekker som kjører før xcodegen, og som også
kjører gratis på Linux i GitHub Actions:

```sh
python3 ci/validate-localizations.py   # norsk lokalisering mot kildetekst
python3 ci/check-swift-structure.py    # klammebalanse, døde symboler, duplikater
python3 ci/check-store-api.py          # visningenes bruk av AppStore
```

> Dette arbeidsområdet ble opprettet på Windows, så selve Xcode-builden må gjøres
> på macOS. Prosjektbeskrivelsen og kildekoden er uten tredjepartsavhengigheter.
