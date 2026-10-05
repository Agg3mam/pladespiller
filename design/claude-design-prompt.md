Du skal designe en macOS-widget, der hedder **Pladespiller**: en pladespiller set ovenfra, som viser den sang, der spiller lige nu i Spotify eller Musik. Jeg har vedhæftet et billede. **Billedet er din vigtigste kilde.** Følg dets stil, farver, materialer, lys, proportioner og stemning så tæt som muligt. Når billedet og reglerne nedenfor siger noget forskelligt, følger du reglerne for mål og indhold og billedet for alt det visuelle.

## Hvad widgetten er
- Den ligger på skrivebordet ved siden af Apples egne widgets (macOS 26 Tahoe / 27) og skal se lige så gennemført ud som dem.
- Pladespilleren er set lige oppefra. Albumcoveret er pladens etiket, og pladen drejer, mens der spilles.
- Pickuparmen ligger på pladen og bevæger sig fra yderkant til centrum, efterhånden som sangen spiller. Ved pause løftes den og hviler på sin støtte.
- Lysrefleksen på pladen står stille, mens pladen drejer under den. Tegn den som et separat lag.
- Små detaljer: knapperne 33 og 45, hvor den valgte lyser orange, og en lille LED, der lyser, mens der spilles.

## Faste mål (skal overholdes præcist, i punkter @1x)
| Størrelse | Synlig flade | Hjørneradius |
|---|---|---|
| Lille | 164 × 164 | 28, continuous ("squircle") |
| Mellem | 344 × 164 | 28, continuous |
| Stor | 344 × 344 | 28, continuous |

- Der er ingen skygge uden om widgetten. Apples widgets har kun en meget svag, lys kant på ca. 1 px.
- Indhold, der skal flugte med kanten, skal have samme afstand overalt. Brug 16 pt som udgangspunkt, medmindre billedet tydeligt viser noget andet.
- Indre hjørner skal være koncentriske med widgetten: indre radius = 28 − afstanden til kanten.
- Skrift: SF Pro (systemskriften). Tal i tider skal have fast bredde (tabular).
- Klikbare ting skal være mindst 14 pt store.

## Indhold pr. størrelse
- **Lille:** kun pladespilleren. Når musen er over, vises en diskret afspil/pause-knap.
- **Mellem:** pladespilleren og:
  - titel (fed), kunstner med et lille ikon for kildeappen, album
  - en tynd fremdriftslinje
  - knapperne forrige, afspil/pause og næste
- **Stor:** større pladespiller og:
  - titel, kunstner, album
  - fremdriftslinje med tider i begge ender (`1:39 ··· 3:58`)
  - knapper
- **Fremdriftslinjen** kan man klikke og trække på for at spole. Vis den i to tilstande: normal, og med musen over (tykkere og med en lille knap).
- **Lange titler** ruller langsomt (marquee). Vis en titel, der er for lang.

## To valgfrie visninger (brugeren slår dem til og fra i menuen)
**1. "Kun pladespiller"**
- Kan vælges i alle tre størrelser, og den er vigtigst i Stor.
- Pladespilleren fylder hele widgetten: ingen tekst, ingen knapper, ingen fremdriftslinje.
- Det skal være et smukt objekt i sig selv, næsten som et stilleben på skrivebordet. Pladespilleren må gerne gå helt ud til widgettens kanter, så widgetten selv bliver pladespillerens krop.
- Armen viser stadig, hvor langt sangen er nået, og pladen drejer.
- Vis den i alle tre størrelser, og i Stor også i pause og "intet spiller".

**2. Animeret sangtekst (lyrics) nede i hjørnet**
- Den linje, der synges lige nu, vises lille og elegant i et hjørne af widgetten, oven på pladespilleren eller ved siden af den. Den må ikke dække etiketten eller armen.
- Den kan kombineres både med det normale layout og med "Kun pladespiller".
- **Animation:** linjen skifter blødt i takt med sangen. Den nye linje glider eller toner ind, og den gamle toner ud. Gerne ord-for-ord-fremhævning, hvor det ord, der synges, lyser op (karaoke-agtigt), men roligt og ikke prangende. Den kommende linje må gerne vises svagt under den aktuelle.
- Den skal kunne læses på alle temaer, fx med en svag sløret eller mørk baggrund bag teksten.
- Der skal være plads til lange linjer: højst 2 linjer, ellers ombryd eller afkort pænt.
- **Tilstande:** instrumentalt stykke (fx en diskret "♪ ···"), ingen tekst fundet (feltet skjules helt) og pause (linjen står stille og er dæmpet).
- Vis lyrics i Lille, Mellem og Stor, og vis hvordan animationen ser ud trin for trin: 3–4 billeder af et linjeskift.

## Tilstande der skal vises
1. Spiller
2. Pause (armen løftet til hvile, LED slukket)
3. Intet spiller (tom/neutral etiket, teksten "Intet spiller" og "Start musik i Spotify eller Musik")
4. Sang uden cover (cremefarvet etiket med titlen i lille skrift)
5. Manglende tilladelse (en kort tekst med et advarselsikon: "Ingen adgang til Spotify · Åbn Indstillinger")
6. Dæmpet (når man arbejder i et andet program: afmættet, ca. 60 % opacitet, baggrunden halvgennemsigtig over et sløret skrivebord)

## Temaer
Brugeren vælger selv tema. Lav dem alle i samme stil som billedet:
- **Træ** (standard). Brugeren vil have mørkt træ, der ligner ægte træ og ikke bare striber. Hvis billedet viser et materiale, så brug det.
- **Aluminium** (børstet)
- **Sort**
- **Auto** (kroppens farve hentes fra albumcoveret, i en dæmpet udgave)

Lav det hele i både **lys og mørk tilstand**. Tekst skal kunne læses i alle kombinationer.

## Det du skal levere
1. **Designet:** et lærred med alle tre størrelser i hovedtemaet (spiller, mørk tilstand) ved siden af hinanden. Derunder tilstandene 2–6 i Mellem, alle fire temaer i Mellem, lys tilstand, "Kun pladespiller" i alle tre størrelser og lyrics (også kombineret med "Kun pladespiller"). Brug realistiske eksempelsange med rigtigt udseende covers.
2. **Ét forstørret nærbillede** af pladespilleren, der viser materialer, riller, refleks, arm og pickup.
3. **En specifikation til udvikleren.** Den skal være så præcis, at designet kan bygges i SwiftUI/Core Animation uden at gætte. Brug netop disse overskrifter:
   - **Layout pr. størrelse:** position og størrelse (x, y, b, h i pt fra fladens øverste venstre hjørne) for hvert element: krop, plade, etiket, arm (omdrejningspunkt, længde, vinkel ved 0 % og 100 % og i hvile), 33/45, LED, titel, kunstner, ikon, album, fremdriftslinje, tider og knapper.
   - **Typografi:** for hver tekst: skriftvægt, størrelse, linjehøjde, farve (hex og opacitet) i lys og mørk.
   - **Farver og materialer:** hex-værdier for alle flader, kanter, skygger (x, y, blur, farve, opacitet) og gradienter (stop og vinkel) i hvert tema, i lys og mørk.
   - **Pladen:** radier for yderkant, rilleområde, glat zone, etiket og spindelhul; rillernes tæthed; refleksens form og styrke.
   - **Ikoner:** navnet på SF Symbol, størrelse og vægt for hver knap.
   - **Tilstande:** præcis hvad der ændrer sig i hver tilstand og ved hover, inklusive værdierne.
   - **Bevægelse:** varighed og easing for start/stop af pladen, armens løft og sænkning, skift af sang og hover på fremdriftslinjen.
   - **Kun pladespiller:** layoutet for hver størrelse (krop, plade og arm i pt).
   - **Lyrics:** placering og maksimal størrelse pr. størrelse og layout, skrift, farver, baggrund og kanter, og animationen (varighed, easing og forskydning for linjeskift og ord-fremhævning).
   - **Teksturer:** skal designet bruge et billede (fx træ), så beskriv præcist hvilket slags billede, hvordan det er beskåret, og hvilke lag der ligger ovenpå.

Gæt ikke på ting, der ikke kan ses på billedet. Vælg det, der ligner Apples egne widgets mest, og skriv i specifikationen, at det er dit valg.
