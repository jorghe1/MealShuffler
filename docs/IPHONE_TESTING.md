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

Test med «Slett app» mellom minst én av rundene slik at onboarding og fersk lokal
tilstand blir verifisert.

- Fullfør swipe-onboarding og kontroller at valg blir lagret etter omstart.
- Lag ukeplan med standardreglene og kontroller tirsdag/torsdag/lørdag.
- Lås én dag, shuffle resten og bekreft at låst middag ikke endres.
- Opprett og rediger en egen rett.
- Importer én oppskrift fra en `https`-lenke og én fra et bilde.
- Lag handleliste, kryss av varer og eksporter til Påminnelser.
- Prøv stor tekststørrelse, VoiceOver og en smal iPhone-skjerm.
- Kontroller offline oppstart og at eksisterende ukeplan fortsatt finnes.

## Avgrensning i denne builden

Data, husholdning og testcommunity lagres lokalt på én telefon. Firebase er ikke
en forutsetning for denne testen. Synkronisering mellom telefoner, innlogging,
bildeopplasting og et ekte offentlig community krever en backend-adapter senere.
