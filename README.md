# Meal Shuffler

En native SwiftUI-MVP for enkel, regelstyrt middagsplanlegging.

## Dette er med

- Swipe-onboarding som lærer hvilke hverdagsretter brukeren liker.
- Regelbygger med dagregler, ukentlige minimum og maksimum.
- En lokal planmotor som respekterer låste dager og forklarer regelkonflikter.
- Ukevisning med «bytt», «lås» og «shuffle resten».
- Automatisk, kategorisert handleliste fra ukens retter.
- Lokal lagring i `UserDefaults`; ingen konto eller backend er nødvendig.
- Visuell regelsetningsbygger med harde og myke regler.
- Dagskontekst for antall personer, tidsgrense, ekstra porsjoner, rester, takeaway og dager borte.
- Intensjonsbasert bytte: raskere, billigere, favoritt eller overraskelse.
- Egne retter med manuell registrering, schema.org-import fra lenke og tekstgjenkjenning fra bilde.
- Porsjonsskalering og enhetsnormalisering i handlelisten.
- Husholdningsprofil, invitasjonsidentitet og delbar ukeplan.
- Eksport av handleliste til Apple Påminnelser eller vanlig iOS-deling.
- Lokal historikk og forsiktig preferanselæring med repetisjonskontroll.
- Et repository-basert testcommunity med testfamilier, publisering, vurdering og rapportering.
- Engelsk som utviklings- og standardspråk, med komplett norsk Bokmål-lokalisering.

MVP-en leveres med tre aktive startregler:

1. Fisk på tirsdag og torsdag.
2. Kylling maksimalt to ganger i uka.
3. Pizza på lørdag.

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

Selve planleggingen er domenelogikk uten UI- eller nettverksavhengigheter. Lagret
MVP-tilstand har bakoverkompatibel dekoding for felter som er lagt til etter
første versjon.

Community bruker `CommunityRepository`. `LocalCommunityRepository` gir et
persistérbart testmiljø på én enhet. En fremtidig CloudKit-, Supabase- eller egen
API-adapter kan implementere samme protokoll uten at Community-visningene må
skrives om. Invitasjonslenker og husholdningsidentitet er etablert, men sanntids-
synkronisering mellom forskjellige enheter krever denne backend-adapteren.

Offentlig publisering krever aktiv bekreftelse på delingsrettigheter, beholder
originalkilde for nettimport og har rapporteringsmodell fra starten. Modereringskø,
autentisering og opplasting av bilder må ferdigstilles før et helt åpent community.

> Dette arbeidsområdet ble opprettet på Windows, så selve Xcode-builden må gjøres
> på macOS. Prosjektbeskrivelsen og kildekoden er uten tredjepartsavhengigheter.
