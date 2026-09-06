# Første test på fysisk iPhone

Prosjektet er satt opp for både direkte installasjon fra Xcode og distribusjon
gjennom Codemagic/TestFlight. Bundle-ID-en er `no.mealshuffler.app`.

## Alternativ A: raskest fra en Mac

Forutsetninger:

- macOS med Xcode 26.4 eller nyere
- en Apple-ID lagt til i Xcode
- en iPhone med iOS 17 eller nyere

Kjør fra prosjektmappen:

```sh
make open
```

I Xcode:

1. Velg target `MealShuffler` → Signing & Capabilities.
2. Behold «Automatically manage signing» og velg Apple-teamet ditt.
3. Koble iPhone til med kabel første gang, lås den opp og godkjenn maskinen.
4. Aktiver Developer Mode på telefonen hvis iOS ber om det.
5. Velg telefonen som destination og trykk Run.

En gratis Apple-ID kan brukes til kortvarig testing på egen enhet. TestFlight
og stabil distribusjon krever aktivt Apple Developer Program-medlemskap.

## Engangsoppsett for utvidelser (App Group)

Widgeten kjører i sin egen prosess og leser planen fra en delt beholder. Det
krever ett manuelt steg i Apple Developer som verken Xcode eller Codemagic
gjør automatisk:

1. Opprett App Group `group.no.mealshuffler.shared` under Identifiers →
   App Groups.
2. Slå på App Groups-capability på App ID-en `no.mealshuffler.app` og velg
   gruppen.
3. Opprett App ID `no.mealshuffler.app.widget` med samme App Groups-capability
   og samme gruppe.
4. Regenerer provisioning profiles. Codemagic henter nå profiler for begge
   bundle-ID-ene (`BUNDLE_ID` og `WIDGET_BUNDLE_ID`).

Hvis capability-en mangler, faller appen tilbake til privat lagring og
fortsetter å virke, men widgeten viser «Ingen plan ennå» uansett hva som er
planlagt. Det er den vanligste årsaken til en tom widget.

## Alternativ B: Codemagic til TestFlight

`codemagic.yaml` følger samme signeringsmønster som Fiks og forventer:

- App Store Connect-integrasjonen `fiks_app_store_connect`
- variabelgruppen `ios_signing`
- hemmelig variabel `CERTIFICATE_PRIVATE_KEY` i gruppen, base64-kodet på én linje

Hvis dette ligger på teamnivå i Codemagic kan det gjenbrukes direkte. Hvis det
bare ligger på Fiks-applikasjonen, opprett samme gruppe for Meal Shuffler.

Én gang i Apple-systemene:

1. Opprett en eksplisitt App ID med bundle-ID `no.mealshuffler.app` i Apple
   Developer.
2. Opprett app-posten i App Store Connect med samme bundle-ID.
3. Legg repositoryet til i Codemagic og scan `codemagic.yaml`.
4. Start workflow `iOS · Simulator smoke test` manuelt først.
5. Når den er grønn, start `iOS · TestFlight` manuelt eller push en release-tag:

```sh
git tag ios-0.1.0
git push origin ios-0.1.0
```

Workflowen genererer Xcode-prosjektet, kjører testene, lager/bruker
distribusjonssertifikat og provisioning profile, bygger IPA og laster den opp.
Når Apple er ferdig med å prosessere bygget, opprett en intern testgruppe under
TestFlight → Internal Testing, legg til bygget og Apple-ID-en din, og installer
via TestFlight-appen på iPhone. Workflowen sender ikke første build til ekstern
Beta App Review.

Hvis du bruker et annet navn på Codemagic-integrasjonen, endrer du bare
`integrations.app_store_connect` i `codemagic.yaml`.

## Første praktiske testrunde

Kjør denne runden på en fysisk iPhone. Punktene er gruppert etter hva som er
mest sannsynlig å gå galt.

### Migrering fra en eksisterende installasjon (viktigst)

Dette er det eneste som kan ødelegge ekte data, og det kan bare testes på en
telefon som allerede har den gamle appen installert. Ikke slett appen først.

- Installer den nye builden over en eksisterende v1-installasjon.
- Kontroller at ukeplan, egne retter, favoritter, regler og historikk er intakt.
- Kontroller at antall personer i husholdningen er uendret.
- Kontroller at en egen rett med pris fortsatt viser samme pris
  (feltet er omdøpt fra `estimatedCostNOK`, men leses fra den gamle nøkkelen).
- Kontroller at smaksvalg fra onboarding fortsatt gjelder.

### Planlegging

- Fullfør swipe-onboarding og kontroller at valg blir lagret etter omstart.
- Lag ukeplan med standardreglene og kontroller tirsdag/torsdag/lørdag.
- Lås én dag, shuffle resten og bekreft at låst middag ikke endres.
- **Trykk shuffle 5–10 ganger og bekreft at uken faktisk varierer.**
- **Endre antall personer på én dag og bekreft at resten av uken står stille.**
- **Slå av en regel og bekreft at bare dagene regelen gjelder blir planlagt på
  nytt.**
- Bruk «bytt med en annen dag» og bekreft at porsjoner følger med.

### Handleliste

- **Kryss av halve listen, shuffle én dag, og bekreft at avkryssingene
  består.**
- Bekreft at mengder følger antall personer.
- Eksporter til Påminnelser.
- Kontroller tom tilstand ved å sette alle dager til «ingen hjemme».

### Dato og uke

- Kontroller at uketeksten øverst viser riktig datointervall.
- **Still telefonens dato en uke frem, åpne appen, og bekreft at uken rulles
  over og den gamle uken havner i historikk.** Still datoen tilbake etterpå.
- Planlegg neste uke, still datoen frem, og bekreft at den planen tas i bruk.
- Slå på middagspåminnelse og bekreft at varselet kommer og navngir riktig rett.
- Bytt telefonens region til en der uken starter på søndag og kontroller at
  planleggeren følger den rekkefølgen.

### Import

- Importer én oppskrift fra en `https`-lenke, gjerne fra et norsk matnettsted.
- **Ta bilde av en kokebokside med overskrifter og fremgangsmåte, og bekreft at
  bare ingredienser havner i ingredienslisten — ikke stegene, tidsangivelser
  eller sidetall.**
- Rediger en innebygd rett og bekreft at det ikke dukker opp to like rader.
- Slett den redigerte varianten og bekreft at originalen kommer tilbake.

### Widget, Siri og matlaging

- Legg widgeten på hjemskjermen i både liten og medium størrelse.
- Bekreft at den viser kveldens middag, og at den sier «Ingen plan ennå» hvis
  uken er tom.
- Shuffle en dag i appen og bekreft at widgeten oppdaterer seg.
- Spør Siri «hva er til middag».
- Start matlaging fra ••• på en dag: skjermen skal holde seg våken, mengder skal
  følge antall porsjoner, og «vi lagde denne» skal havne i historikken.

### Handleliste med egne varer

- Legg til en vare uten mengde og bekreft at den ikke vises som «1».
- Legg til en vare som allerede står på listen, og bekreft at den slås sammen
  i stedet for å bli en ny linje.
- Hold inne en vare → «Har det allerede», og bekreft at den flyttes ned og kan
  legges tilbake.

### Utseende og tilgjengelighet

- **Kjør hele appen i mørk modus.**
- Sett tekststørrelse til XXL og kontroller at ingenting klippes.
- Kjør VoiceOver over ukeplan og handleliste: hver knapp skal ha navn, og
  avkryssede varer skal leses som valgt.
- Kontroller på en smal skjerm (iPhone SE eller mini).

### Robusthet

- Kontroller offline oppstart og at eksisterende ukeplan fortsatt finnes.
- Send appen i bakgrunnen rett etter en endring og åpne den igjen — endringen
  skal være lagret (skrivingen er debounced og tømmes ved bakgrunnskjøring).
- Kjør minst én runde med «Slett app» først, slik at onboarding og fersk lokal
  tilstand blir verifisert.

## Avgrensning i denne builden

Data, husholdning og historikk lagres lokalt på én telefon. Synkronisering
mellom telefoner, innlogging, bildeopplasting og et ekte offentlig community
krever en backend-adapter senere. `AppStateRepository` og `RecipeExtractor` er
sømmene den adapteren skal implementere.

Community er slått av i denne builden (`FeatureFlags.communityEnabled`). Fanen
var fylt med tre lokale testfamilier og en invitasjonslenke som bare åpnet en
dialog om at synkronisering ikke er bygget. Den slås på igjen sammen med
innlogging og moderering.
