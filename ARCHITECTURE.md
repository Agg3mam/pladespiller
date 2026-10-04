# Pladespiller – arkitektur

En lille baggrundsapp (LSUIElement) med et kantløst `NSPanel` nede på skrivebordet, der ser ud og opfører sig som en macOS-widget. Indholdet er en pladespiller set ovenfra, der viser det der spiller i Spotify/Musik.

Byg: `./build.sh` (`--install`, `--run`, `--run --mock`). Kun Command Line Tools, Swift Package Manager, macOS 26+ (brugerens Mac: macOS 27.2, Apple Silicon). Hele modulet er `@MainActor` som standard (`defaultIsolation`).

## Sådan hænger det sammen

```
App.swift ── opretter ──▶ Settings (@Observable, UserDefaults)
          ├─ opretter ──▶ NowPlayingStore(sources: [Spotify, Musik] eller [Mock])
          └─ opretter ──▶ WidgetPanelController(settings) { WidgetView() }
                               └─ NSHostingView( WidgetChrome { WidgetView } )
WidgetView læser Settings + NowPlayingStore fra environment.
```

- **Kilder** implementerer `NowPlayingSource` og kalder `onChange`. `NowPlayingStore` vælger den der sidst ændrede sig blandt dem der spiller.
- **Position** udregnes lokalt: `NowPlaying.position(at:)`. UI'et bruger `TimelineView`/animation, ikke polling.
- **Kommandolinje** (til test uden vindue): `--mock`, `--render-snapshots <mappe>`, `--nowplaying-log [--mock]`.

## Ejerskab af filer

En agent ændrer kun sine egne filer. Ændringer i fælles filer bestilles hos hovedagenten.

| Ejer | Filer |
|---|---|
| Hovedagent | `Package.swift`, `ARCHITECTURE.md`, `Sources/Pladespiller/App/*`, `Sources/Pladespiller/Shared/*` (NowPlaying, NowPlayingSource, MockNowPlayingSource, Settings, WidgetMetrics) |
| Vindue-agent | `Sources/Pladespiller/Window/*` (panel, chrome/baggrund, træk, gitter, placering, falmet look, højrekliksmenu, Åbn ved login) |
| Grafik-agent | `Sources/Pladespiller/Views/*` (WidgetView, pladespiller, plade, sheen, arm, knapper, temaer, SnapshotRenderer) |
| Musikdata-agent | `Sources/Pladespiller/NowPlaying/*` (NowPlayingStore, Spotify, Musik, AppleScript, cover-cache, DebugCLI) |
| Build-agent | `build.sh`, `Resources/*`, `scripts/*` |
| QA | `qa/*` (rapporter og billeder), ingen kildekode |

## Faste aftaler (API)

- `NowPlaying` (Shared/NowPlaying.swift): `trackKey`, `position(at:)`, `progress(at:)`, `formatTime(_:)`.
- `NowPlayingSource` (Shared/NowPlayingSource.swift).
- `NowPlayingStore`: `current`, `start()`, `stop()`, `playPause()`, `nextTrack()`, `previousTrack()`, `openSourceApp()`, `static defaultSources()`.
- `Settings`: `size`, `theme`, `colorMode`, `positionLocked`, `savedOrigin(screenID:)`, `saveOrigin(_:screenID:)`.
- `WidgetMetrics`: gitter 180 pt, indryk 8 pt, radius 28 pt, vinduesniveau, animationstider.
- `WidgetChrome` giver indholdet en flade på `WidgetMetrics.bodySize(for:)` og klipper den med radius 28.
- `MockNowPlayingSource.sample(_:isPlaying:progress:)` og `.artwork(for:)` til snapshots.

## Regler

- Kun hovedagenten og QA starter selve appen og tager skærmbilleder. Kun én kopi kører ad gangen.
- Skærmbilleder tages kun af enkelte vinduer (`screencapture -l <id>`): vores widget og Apples widget-vinduer. Aldrig hele skærmen.
- Start aldrig Spotify eller Musik. Send kun AppleScript til en app, der allerede kører.
- Al tekst i appen er på dansk.

## Beslutningslog

- **2026-10-03 · Bølge 0.** macOS 27.2 / arm64, kun Command Line Tools → SPM + `build.sh`. Bundle-id `dk.holgerskov.Pladespiller`.
- **2026-10-03 · Målt på brugerens Apple-widgets** (Ur, Album, Kalender, Status) via CGWindowList og `screencapture -l`:
  vinduesniveau `-2147483601` (= `desktopIconWindow + 2`); vinduer 180×180 / 360×180 / 360×360 kant i kant i et 180 pt-gitter
  (fx x = 313, 493, 673, 853, 1033; y = 38, 218); synlig flade indrykket 8 pt; hjørneradius 28 pt continuous (bedste tilpasning);
  ingen synlig systemskygge; svag lys kant ≈1 px. Widget-stil `com.apple.widgets widgetAppearance = 1`; widgets er p.t. mørke og
  uigennemsigtige selvom systemet er i lys tilstand.
- **2026-10-03 · Vinduesniveau** `desktopIconWindow + 2` = samme lag som Apples widgets. Bekræftet med CGWindowList.
- **2026-10-03 · Standardtema** Træ (foreløbig, skal bekræftes af brugeren).
- **2026-10-03 · Bølge 1 flettet** (build de63705, vindue 62a066c, musik 4f26b52, grafik c15572d).
  - Signering: selvsigneret "Pladespiller Local Signing" i egen nøglering (`scripts/setup-signing.sh` / `remove-signing.sh`); DR = certificate leaf, stabil mellem builds. Ingen hardened runtime.
  - Look: uigennemsigtig flade + lys kant, fordi brugerens Ikon- og widgetstil = Mørk (`AppleIconAppearanceTheme=RegularDark`); Liquid Glass (`.glassEffect(.clear)`) kun ved Klar/Tonet. `WidgetStyle` følger ændringer.
  - Gitter: flugter med nærmeste Apple-widget (kanter + k·180), ellers gitter fra det synlige områdes øverste venstre hjørne; aldrig overlap med Apple-widgets.
  - Træk: `WidgetPanel.sendEvent` med 4 pt-tærskel; `.claimsWidgetDrag()` til indhold der selv vil trække.
  - Musik: NSAppleScript på én seriel kø, alle scripts bag `if application id … is running`; DistributedNotifications + 5 s sikkerhedsnet kun mens der spilles.
  - Grafik: Core Animation-lagtræ (`TurntableLayer`); rotation/arm som CA-animationer lagt ind ved tilstandsskift, intet arbejde pr. frame. Sheen er fast lag over rotoren.
- **2026-10-03 · Brugerens valg efter bølge 1:** tema vælges i menuen (standard Træ indtil da); træ = mørkt, realistisk træ (ikke striber);
  lange titler = **rulletekst**; "forrige" i Musik = som Musik selv (`back track`).
- **2026-10-03 · Bølge 2-aftaler:** `Shared/WidgetPresentation.swift` (`dimAmount`, `isHovering`, environment `\.widgetPresentation`)
  og `SourceAccessProblem`; `NowPlayingStore.accessProblem`. QA-fejl fra bølge 1 i `qa/bolge1/` fordeles til ejerne.
  Hovedagent rettede M9 (AppDelegate-levetid) og M10 (én-kopi-tjek).
- **2026-10-03 · Træ = rigtigt foto** (brugerens ønske): `Resources/Textures/dark_wood.jpg`, Poly Haven "Dark Wood" 2K, CC0 (se `Resources/Textures/LICENSE.txt`).
  `build.sh` kopierer `Resources/Textures/*` til `Contents/Resources/Textures/` (hovedagenten lavede den lille ændring, da Build-agenten var færdig).
- **2026-10-03 · Bølge 2: vindue (2321afb) og musik (eec6d25) flettet.** Begge havde lavet en `DistributedObserver` → navnesammenstød;
  hovedagenten samlede dem i `Shared/DistributedObserver.swift` (init(names:handler:), init(name:handler:), init(names:onChange:)).
  Musik sender nu rå Apple Events til pid (kan aldrig starte appen); NSAppleScript-reserve med `--applescript`. Log: `--log` → `~/Library/Logs/Pladespiller/nowplaying.log`.
  Dæmpning: "Automatisk" følger Apples Widgetstil (widgetAppearance 1 = Fuld farve → ingen dæmpning), ellers Finder-reglen.
- **2026-10-04 · QA-rettelser efter bølge 2 flettet** (musik 364870a, vindue 5a2a1a4, grafik 30e3e80). N2 (etiket én sang bagud) bekræftet rettet live af hovedagenten
  med billeder af løkken; N1 (dæmpning) bevist i det lag der sidder i viewet. Placering gemmes nu som øverste venstre hjørne.
- **2026-10-04 · Brugerfeedback:** design ikke polished nok (ting sidder ikke lige), pladen lidt for hurtig → `secondsPerRevolution` 2,25 s (≈27 o/min); stor størrelse skal redesignes.
- **2026-10-04 · Hastighed kan vælges:** `SpinSpeed` (Langsom 3 s / Rolig 2,25 s standard / 33⅓ 1,8 s / 45 1,33 s) i `Settings.spinSpeed`. Menu ▸ Hastighed (Vindue); rotation + 33/45-knapper på kroppen (Grafik).
- **2026-10-04 · Polish flettet** (grafik 5c18b34, vindue 9b03c52): fast layoutgitter (`Views/Layout.swift`: padding 16, objectInset 8, gap 12), pixel-layouttjek, valgbar hastighed + 33/45-knapper, menu ▸ Hastighed. Stor har 4 varianter bag `LargeLayout` (classic standard, A helt træ, B centreret, C plade+cover) — afventer brugerens valg.
