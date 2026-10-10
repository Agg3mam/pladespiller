# Pladespiller

En lille widget til skrivebordet på macOS, der viser en pladespiller set ovenfra. Pladen er den sang, du hører lige nu i **Spotify** eller **Musik**. Albumcoveret er pladens etiket, pladen drejer, mens musikken spiller, og pickuparmen viser, hvor langt sangen er nået.

Den ligger nede på skrivebordet sammen med Apples egne widgets, falder på plads i deres gitter og kan ikke ses i Dock.

**Krav:** macOS 26 eller nyere og en Mac med Apple-chip (M1 eller nyere).

## Installér den færdige app

1. Hent `Pladespiller.zip` under **Releases** til højre på denne side.
2. Pak den ud, og læg `Pladespiller.app` i mappen **Programmer**.
3. Åbn den. Appen er bygget privat og ikke godkendt af Apple, så macOS stopper den første gang:
   - Åbn **Systemindstillinger ▸ Anonymitet og sikkerhed**, rul ned, og klik **Åbn alligevel** ud for Pladespiller.
   - Eller højreklik på appen i Finder og vælg **Åbn**.
4. Afspil en sang i Spotify eller Musik. macOS spørger, om **"Pladespiller" må styre "Spotify"** (eller "Musik"). Klik **OK**.

Fortryder du en tilladelse, kan du ændre den i Systemindstillinger ▸ Anonymitet og sikkerhed ▸ Automatisering.

## Brug

- **Træk** widgetten for at flytte den. Den falder på plads i gitteret.
- **Klik på armen:** afspil/pause. **Klik på pladen:** åbn musikappen.
- **Sangtekst:** står i hjørnet og følger sangen linje for linje. Teksterne hentes fra [LRCLIB](https://lrclib.net). Kun sangens titel og kunstner sendes dertil. Kan slås fra i menuen.
- **Knapper og tekst** (slås til i menuen): titel, kunstner, fremdrift med tider og forrige/afspil/næste. I Stor kommer knapperne frem, når musen er over widgetten.
- **Spol:** klik eller træk på fremdriftslinjen.
- **Menu:** højreklik på widgetten eller klik på ikonet med pladen i **menulinjen**:
  - Lille / Mellem / Stor
  - Tema: Flad, Træ, Aluminium, Sort eller Auto (farven hentes fra coveret)
  - Farve (til Flad): Auto fra coveret, ti faste farver eller "Vælg farve…"
  - Hastighed: Langsom, Rolig, 33⅓ eller 45 o/min
  - Dæmpning: følger Apples widgetstil, eller altid fuld farve/dæmpet
  - Vis knapper og tekst, Vis sangtekst
  - Fuld skærm (se nedenfor)
  - Julestemning: Til, Fra eller Automatisk i julen (1. dec–6. jan), og Sne på skrivebordet
  - Sprog: Dansk, English eller Automatisk (som Macen)
  - Lås placering, Åbn ved login, Fjern widget

I temaet Flad er armen hvid, når macOS står i lys tilstand, og sort i mørk tilstand. I de andre temaer er armen en lille 3D-model med ægte metal og lys.

## Julestemning

En lyskæde med store glaspærer, der blinker blødt hver for sig, og sne, der falder i tre dybder og svajer. Den lægger sig oven på det tema, du har valgt, og virker også på fuld skærm. Med **Sne på skrivebordet** falder sneen også over hele skrivebordet, bag dine vinduer og ikoner (man klikker lige igennem den). Det hele kører i Core Animation, så appen bruger ikke CPU på det.

## Fuld skærm

Vælg **Fuld skærm** i menuen. Pladespilleren vises stor på din ekstra skærm, med sangteksten ved siden af eller alene (menu ▸ Fuld skærm-visning).

- Den ligger som en levende baggrund: dine vinduer ligger foran, og menulinjen på den skærm skjules.
- Cursoren forsvinder efter 3 sekunder, og skærmen holdes tændt, mens der spilles.
- **Esc** lukker fuld skærm.
- Med **Flyt nye vinduer væk** flyttes nye vinduer, der åbner på fuld skærm-skærmen, over på din arbejdsskærm. Det kræver adgangen **Tilgængelighed** (Systemindstillinger ▸ Anonymitet og sikkerhed ▸ Tilgængelighed). Appen spørger først, når du bruger funktionen.

## Afinstallér

Højreklik på widgetten og vælg **Fjern widget**. Slet derefter `Pladespiller.app`.

Har du bygget appen selv, kan du i stedet køre `scripts/uninstall.sh`. Det fjerner også indstillinger, tilladelser og logfiler.

## Byg selv

Det kræver Command Line Tools (`xcode-select --install`). Xcode er ikke nødvendigt.

```bash
./build.sh --run
```

- Testdata uden musik: `./build.sh --run --mock`.
- Valgfrit: kør `scripts/setup-signing.sh` én gang. Så laves et lokalt signeringscertifikat, og macOS husker tilladelserne mellem builds.

Opbygningen og de vigtigste beslutninger står i [ARCHITECTURE.md](ARCHITECTURE.md).

## Tak

- Træet er "Dark Wood" fra [Poly Haven](https://polyhaven.com/a/dark_wood) (CC0).
