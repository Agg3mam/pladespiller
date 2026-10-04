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
- **Knapperne** forrige, afspil/pause og næste findes i størrelserne Mellem og Stor.
- **Spol:** klik eller træk på fremdriftslinjen (Mellem og Stor).
- **Hastighed:** klik på 33 eller 45 på pladespilleren, eller vælg i menuen.
- **Højreklik** åbner menuen:
  - Lille / Mellem / Stor
  - Tema: Træ, Aluminium, Sort eller Auto (farven hentes fra coveret)
  - Hastighed: Langsom, Rolig, 33⅓ eller 45 o/min
  - Farver
  - Lås placering
  - Åbn ved login
  - Fjern widget

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
