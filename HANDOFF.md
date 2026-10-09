# Handoff: Pladespiller

*Status pr. 2026-10-09 (main `19b7bc3`, version 0.3 på GitHub, nyere build installeret lokalt).*

Giv denne fil til en ny Claude Code-session. Den samler alt, du skal vide for at fortsætte. Detaljerne og den fulde beslutningslog står i [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 1. Hvad det er

En lille macOS-app i Swift/SwiftUI, der viser en **pladespiller set ovenfra** som en widget på skrivebordet. Pladen er den sang, der spiller i **Spotify** eller **Musik**. Coveret er etiketten, pladen drejer, og armen viser, hvor langt sangen er nået.

Det er ikke en WidgetKit-widget. Det er en baggrundsapp (`LSUIElement`) med et kantløst `NSPanel` på samme vinduesniveau som Apples widgets. Den er kun til brugerens egen Mac.

**Om brugeren:** brugeren er ikke udvikler. Skriv **på dansk og i et let sprog**, forklar hvad du gør, og sig præcis hvad brugeren skal klikke på eller godkende. Spørg, før du gætter på design- og produktvalg.

**Brugerens Mac:** macOS 27.2, Apple Silicon. Der er kun Command Line Tools (ingen Xcode, og brugeren skal ikke bedes om at installere det). Der er to eksterne skærme på 2560×1440, hvoraf den ene kører 144 Hz. I Udseende er "Ikon- og widgetstil" sat til **Mørk** (`AppleIconAppearanceTheme=RegularDark`), og widgetstilen er Fuld farve (`com.apple.widgets widgetAppearance=1`).

---

## 2. Byg, kør, test

```bash
cd "/Users/holgerskov/Claude code/Pladespiller"
./build.sh                 # byg til build/Pladespiller.app
./build.sh --install       # byg og læg i ~/Applications (lukker en kørende kopi)
./build.sh --run --mock    # installér og start med testdata
open ~/Applications/Pladespiller.app --args --log   # rigtig musik + log
```

**Kommandolinje-flag** (binæren ligger i `.build/debug/Pladespiller` efter `swift build`):

| Flag | Gør |
|---|---|
| `--mock` | testdata i en løkke på 34 s (afspil, pause, ny sang, uden cover, intet spiller) |
| `--log` | den installerede app logger til `~/Library/Logs/Pladespiller/nowplaying.log` |
| `--render-snapshots <mappe>` | tegner alle visninger til PNG uden vindue; kør også layout-, spin- og live-tjek |
| `--window-selftest` | 71 tjek af gitter, menu, fuld skærm osv. ("alt OK") |
| `--nowplaying-log --selftest` | 95 tjek af kilder, LRC-parser, LRCLIB-backoff og cache |
| `--nowplaying-log [--cmd playpause\|next\|previous\|seek:<s>] [--app spotify\|music]` | live-log og kommandoer fra Terminal (så får Terminal tilladelsen, ikke appen) |
| `--lyrics "Titel" "Kunstner" [sek]` | hent sangtekst fra LRCLIB og print den |
| `--applescript` | reservevej med NSAppleScript i stedet for rå Apple Events |
| `--unregister-login-item` | bruges af `scripts/uninstall.sh` |

**Signering:** builds signeres med det selvsignerede certifikat "Pladespiller Local Signing". Det ligger i en separat nøglering (`~/Library/Keychains/pladespiller-signing.keychain-db`), og adgangskoden til den ligger i `~/.config/pladespiller/keychain-pass`. Fordi signaturen er den samme hver gang, husker macOS tilladelserne mellem builds. Opsætning sker med `scripts/setup-signing.sh`, og fjernelse med `scripts/remove-signing.sh`. Det kører uden hardened runtime.

**Afinstallation:** `scripts/uninstall.sh` (har `--dry-run`).

---

## 3. Funktioner (det der virker nu)

- **Vindue:**
  - Ligger på niveau −2147483601, ligesom Apples widgets.
  - Kan trækkes med en grænse på 4 pt, før det tæller som træk, og falder på plads i et gitter på 180 pt, der flugter med Apples widgets.
  - Placeringen gemmes pr. skærm som øverste venstre hjørne, og den finder sin plads igen ved skærmskift, dvale og login.
  - Udseendet er målt på brugerens widgets: indryk 8 pt, radius 28 continuous, en svag lys kant og ingen skygge.
- **Størrelser:** Lille 164×164, Mellem 344×164 og Stor 344×344 pt synlig flade.
- **Temaer:**
  - **Flad** (standard, efter brugerens referencebillede): ensfarvet krop, lys gennemskinnelig plade, stor cover-etiket og en enkel hvid arm.
  - Desuden Træ (rigtigt foto, Poly Haven "Dark Wood", CC0), Aluminium, Sort og Auto.
  - **Farve** til Flad: Auto (fra coveret), ti faste farver, eller "Vælg farve…" via NSColorPanel.
- **Står alene** (standard, `showControls=false`): kun pladespilleren, med **sangtekst** nederst i hjørnet. Når der ikke findes nogen, står der titel og kunstner. Med "Vis knapper og tekst" kommer knapper, fremdriftslinje og spoling frem. I Stor er det layoutet "Helt træ" med en infobjælke.
- **Bevægelse:**
  - Hastigheden kan vælges: Langsom 3 s, Rolig 2,25 s (standard), 33⅓ eller 45 o/min. Den kan også skiftes med 33/45-knapperne på kroppen (ikke i Flad).
  - Pladen speeder op på 0,8 s og ned på 1,2 s.
  - Armen følger sangen, løftes ved pause og flytter sig ved ny sang på under 1 s.
  - Lysrefleksen står stille, mens pladen drejer.
- **Klik:** armen = afspil/pause, pladen = åbn musikappen, og i fremdriftslinjen kan man klikke og trække for at spole.
- **Musikdata:**
  - Spotify og Musik læses med rå Apple Events, der sendes til appens **pid**, så Spotify eller Musik aldrig bliver startet.
  - Opdateringer kommer med det samme via `DistributedNotificationCenter` (`.deliverImmediately`), og der tjekkes kun hvert 5. sekund, mens der spilles.
  - Afspil/pause opdateres med det samme i widgetten (optimistisk), og spoling sendes højst hver 100 ms.
- **Sangtekst:**
  - Hentes fra **LRCLIB** (brugeren har godkendt, at titel og kunstner sendes dertil).
  - Formatet er LRC, også med ord-timing, og teksterne caches både i hukommelsen og på disken (`~/Library/Caches/dk.holgerskov.Pladespiller/lyrics/`).
  - En sang, der ikke findes, gemmes i 7 dage, så den ikke slås op igen.
  - Er LRCLIB overbelastet (5xx), prøver den igen efter 15 s, 60 s og 5 min.
- **Fuld skærm** (menu ▸ Fuld skærm, Esc lukker):
  - Den vises på den ekstra skærm som en **levende baggrund** (niveau `desktopIconWindow+1`), så alle vinduer ligger foran.
  - Der er to visninger: Med sangtekst og Kun pladespiller.
  - Cursoren skjules efter 3 s, og skærmen holdes tændt, mens der spilles.
  - **Nye vinduer**, der åbner på den skærm, flyttes til hovedskærmen. Det kræver adgangen Tilgængelighed, som brugeren har sagt ja til; der spørges kun, når fuld skærm åbnes. Vinduer, man selv trækker derover, får lov at blive.
- **Menu (højreklik):**
  - Lille / Mellem / Stor
  - Tema ▸, Farve ▸, Hastighed ▸, Dæmpning ▸
  - Vis knapper og tekst, Vis sangtekst
  - Fuld skærm, Fuld skærm-visning ▸, Fuld skærm-skærm ▸, Hold skærmen tændt, Flyt nye vinduer væk
  - Lås placering, Åbn ved login (SMAppService)
  - Fjern widget: spørger først og slår også login fra
- **Dæmpning:** "Automatisk" følger Apples widgetstil. Hos brugeren er den Fuld farve, så der dæmpes aldrig, ligesom Apples egne widgets. Desuden kan man vælge "Altid fuld farve" og "Altid dæmpet".
- **Ydelse** (målt i bølge 1 og 2): ca. 0 % CPU, både mens pladen drejer og når den står stille (al bevægelse kører i Core Animation), og 42 MB hukommelse, der ikke vokser.

---

## 4. Opbygning og ejerskab

Swift Package Manager og `Package.swift` (tools 6.2, `.macOS("26.0")`, `defaultIsolation(MainActor.self)`). Bemærk: `@Entry`-makroen virker ikke med kun Command Line Tools. Brug `EnvironmentKey`.

| Mappe | Indhold | Ejer (agent) |
|---|---|---|
| `Sources/Pladespiller/App/` | `App.swift`: opstart, flag, sammensætning | Hovedagent |
| `Sources/Pladespiller/Shared/` | fælles aftaler: `NowPlaying`, `NowPlayingSource`, `Settings`, `WidgetMetrics`, `WidgetPresentation`, `Lyrics`, `DistributedObserver`, `MockNowPlayingSource` | Hovedagent |
| `Sources/Pladespiller/Window/` | panel, chrome, træk/gitter, placering, dæmpning, menu, fuld skærm, `NewWindowMover`, selvtest | Vindue-agent |
| `Sources/Pladespiller/Views/` | pladespilleren (Core Animation-lag), temaer, layout, sangtekst, rulletekst, spolelinje, fuld skærm-visning, snapshots | Grafik-agent |
| `Sources/Pladespiller/NowPlaying/` | Spotify/Musik-kilder, Apple Events, store, LRCLIB, cover-cache, log, CLI, selvtest | Musikdata-agent |
| `build.sh`, `Resources/`, `scripts/` | build, Info.plist, ikon, tekstur, signering, afinstallation | Build-agent |
| `qa/` | QA-rapporter og billeder | QA |
| `design/` | prompt til Claude Design; brugerens referencebillede (`reference.*`, **ikke i git**) | Hovedagent |

**Fast API, som de andre dele bygger på:** `NowPlayingStore`: `current`, `accessProblem`, `lyrics`, `lyricsEnabled`, `start/stop`, `playPause`, `nextTrack`, `previousTrack`, `seek(to:)`, `openSourceApp()`, `openAutomationSettings()`. `Settings`-nøglerne har præfikset `pladespiller.` (se `Shared/Settings.swift`).

---

## 5. Arbejdsgang med flere agenter (sådan har det kørt)

Brugeren bad om, at opgaven løses af flere agenter i et hierarki.
- Hovedagenten er den eneste, der taler med brugeren. Den laver de fælles aftaler, fletter og kontrollerer.
- Hver område-agent arbejder i sin egen **git worktree** og på sin egen gren: `../Pladespiller-worktrees/{vindue,grafik,musik,build}`.
  - Før en opgave kører agenten `git merge main`.
  - Efter opgaven fletter hovedagenten grenen ind i `main`.
- En agent ændrer **kun sine egne filer**. Ændringer i fælles filer bestilles hos hovedagenten med en præcis diff.
- **Kun hovedagenten og QA starter selve appen.** De andre tester med `swift build`, `--render-snapshots` og selvtest.
- Efter større bølger kontrollerer QA og giver en fejlliste med alvorlighed og ejer.

Faldgruber, vi har mødt:
- To agenter lavede samme typenavn (`DistributedObserver`). Den er nu samlet i Shared.
- Snapshots tegnede et andet lag, end live-visningen viste (QA N1). `LiveSequenceTest` fanger det nu.
- CA-animationer med absolut starttid og `.backwards`-fyld hang på startværdien live (QA N2). Nu starter alle "nu", og der er et sikkerhedsnet.
- Hovedagenten genstartede appen, mens brugeren var i højrekliksmenuen. **Genstart ikke appen uden grund**, mens brugeren bruger den.

---

## 6. Regler og samtykke fra brugeren

- **Skærmbilleder:** tag kun billeder af enkelte vinduer med `screencapture -x -o -l <vinduesnummer>`: vores vindue (ejer "Pladespiller") og Apples widget-vinduer (ejer "Notification Center", lag −2147483601). **Aldrig** hele skærmen eller andre apps. Find vinduesnumre med CGWindowList, og filtrér på **lag** (ejer-navnet "Pladespiller" rammer også menuvinduer).
- **Spotify og Musik:** start dem aldrig, og send ikke Apple Events til dem i test uden brugeren.
- **Tilladelser brugeren har givet:**
  - Automatisering (Spotify og Musik): givet.
  - LRCLIB: titel og kunstner må sendes dertil.
  - Tilgængelighed: kun til at flytte nye vinduer væk fra fuld skærm-skærmen.
  - Covers via iTunes Search API er **ikke** godkendt.
- **Referencebilledet** (`design/reference.*`) viser en andens Snapchat-profil og et ophavsretsbeskyttet cover. Det skal blive uden for git; det står i `.gitignore`. Det gælder også `qa/preview/reference-*`.
- **Commits** bruger den lokale git-identitet `Holger Skov <294425076+Agg3mam@users.noreply.github.com>` og slutter med `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. **Push kun, når brugeren beder om det.**

---

## 7. GitHub

- Repoet er privat: https://github.com/Agg3mam/pladespiller (remote `origin`, gren `main`). `gh` ligger i `/opt/homebrew/bin/gh`, og brugeren er logget ind som Agg3mam.
- Releases v0.1, v0.2 og v0.3 har hver en `Pladespiller.zip` (en færdigbygget app).
  - Sådan laves en ny release: hæv versionen i `Resources/Info.plist` (`CFBundleShortVersionString` og `CFBundleVersion`), kør `./build.sh`, og zip med `ditto -c -k --sequesterRsrc --keepParent build/Pladespiller.app build/Pladespiller.zip`. Kør derefter `git push`, og `gh release create vX.Y build/Pladespiller.zip --repo Agg3mam/pladespiller --title … --notes …` (noterne på dansk).
- **v0.3 er den seneste på GitHub.** Flad-temaet, sangteksten, fuld skærm og flytning af nye vinduer er **ikke** udgivet endnu. Det skal blive v0.4, når brugeren beder om det.
- Brugeren vil invitere én person som collaborator, men har **endnu ikke givet brugernavnet**.
- `README.md` (dansk vejledning) beskriver v0.3. Den skal opdateres med Flad, Farve, sangtekst, fuld skærm og Tilgængelighed før v0.4.

---

## 8. Det, der mangler eller er usikkert

**Skal prøves live med brugeren** (ingen agent har kunnet starte appen):
1. **Fuld skærm:**
   - Esc, klik og fokus.
   - At cursoren skjules.
   - At den ligger som baggrund bag vinduer.
   - At Dock og menulinjen ligger foran.
   - At skærmen holdes tændt (`pmset -g assertions | grep Pladespiller`).
2. **Flyt nye vinduer væk:**
   - Adgangen Tilgængelighed og den danske forklaring.
   - Om TextEdit og Safari (Cmd+N) flytter til hovedskærmen.
   - At dialoger ikke flyttes.
   - At vinduer, man selv trækker derover, bliver.
3. **Sangtekst i takt** med en rigtig sang. LRCLIB virker (fx *Didn't I* af Darondo gav 35 linjer).
4. **Menuen:** Farve ▸ og "Vælg farve…", der skal give fokus tilbage, når panelet lukkes. "Fjern widget".
5. Spoling i **Musik** (Spotify er bekræftet live).

**Ikke QA-kontrolleret siden bølge 2:** polering, Stor "Helt træ", spoling, Flad, sangtekst, fuld skærm og flytning af vinduer. Kør en QA-runde (visuelt, ydelse med fuld skærm og WindowServer, og kodegennemgang), før v0.4 udgives.

**Kendte småting og åbne valg:**
- **Flad mod referencen:** armen står mere på skrå end på brugerens billede (der står den næsten lodret), og titlen er lidt større. Brugeren har ikke svaret på, om det skal ændres.
- **Større covers til fuld skærm:** Spotify giver 640 px, som skaleres ca. 1,25× op på 2560×1440.
  - Muligheden er Spotifys `ab67616d0000b273` → `…82c1` (uofficiel), med fallback til 640 px. Den er ikke bygget, og brugeren er ikke spurgt endnu.
  - iTunes-opslag kræver brugerens samtykke.
- Under "Farve ▸" skifter et farvevalg temaet til Flad. Det var agentens valg, og brugeren har ikke kommenteret det.
- I Mellem, når pladespilleren står alene, er hjørnefeltet kun 128 pt bredt, så lange titler ruller, og sangteksten ombrydes.
- **Fase 2, MediaRemote** (en generel kilde for YouTube, Tidal, Podcasts osv.) er undersøgt, men brugeren har ikke besluttet noget. Muligheden er `ungive/mediaremote-adapter` via `/usr/bin/perl`. Det er en privat omvej, som Apple kan lukke. Den er ikke prøvet på 27.2.
- Spørgsmål, brugeren ikke har svaret på:
  - Er tempoet i rulleteksten godt?
  - Hvad står der i Widgetstil, og skal den dæmpes, mens man arbejder i andre programmer?
- **Den endelige vejledning** (afsnit 6.7 i det oprindelige oplæg) er ikke skrevet. Den skal kort forklare brug, tilladelser og afinstallation, samt hvilke agenter der lavede hvad.

---

## 9. Hvem lavede hvad (indtil nu)

Fem agenter plus hovedagenten (Vindue, Grafik, Musikdata, Build og QA), og én hjælpeagent hos QA til kodegennemgang. Der er 68 commits på `main`.
