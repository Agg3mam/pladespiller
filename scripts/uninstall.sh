#!/bin/zsh
# Fjerner Pladespiller fra denne Mac igen.
#   scripts/uninstall.sh              fjern alt (spørger om signeringen også skal fjernes)
#   scripts/uninstall.sh --dry-run    vis kun, hvad der ville ske – ændrer intet
#   scripts/uninstall.sh --yes        svar ja til alt (fjerner også signeringen)
#   scripts/uninstall.sh --keep-signing   behold signeringen uden at spørge
#
# Alle trin kan køres flere gange: det, der allerede er væk, springes bare over.
set -uo pipefail
SCRIPTS="${0:A:h}"

APP_NAME="Pladespiller"
BUNDLE_ID="dk.holgerskov.Pladespiller"
APP="$HOME/Applications/$APP_NAME.app"

dry=false; answer=""
for a in "$@"; do
  case "$a" in
    --dry-run|-n) dry=true ;;
    --yes|-y) answer=ja ;;
    --keep-signing) answer=nej ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) print -u2 "Ukendt valg: $a (se --help)"; exit 2 ;;
  esac
done

step() { print -- "\n• $*"; }
ok()   { print -- "  ✓ $*"; }
did()  { $dry || ok "$@"; }   # kun når noget faktisk er gjort
info() { print -- "  – $*"; }
exec 3>&1   # prøvekørsels-beskeder går hertil, også når kommandoens eget output er slået fra
# Kører en kommando – eller viser den bare ved --dry-run.
do_it() {
  if $dry; then print -u3 -- "  (prøvekørsel) ville køre: ${(q-)@}"; return 0; fi
  "$@"
}

$dry && print "Prøvekørsel: der bliver ikke ændret noget."
print "Fjerner $APP_NAME fra denne Mac."

# 1) Luk appen -------------------------------------------------------------
step "Lukker $APP_NAME"
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  do_it pkill -x "$APP_NAME"
  if ! $dry; then
    for _ in {1..30}; do pgrep -x "$APP_NAME" >/dev/null 2>&1 || break; sleep 0.1; done
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      do_it pkill -9 -x "$APP_NAME"; sleep 0.3
    fi
    pgrep -x "$APP_NAME" >/dev/null 2>&1 && info "Appen ville ikke lukke. Luk den selv og kør scriptet igen." || ok "Lukket."
  fi
else
  ok "Den kørte ikke."
fi

# 2) "Åbn ved login" --------------------------------------------------------
# Appen er meldt til via SMAppService.mainApp. Den post kan kun meldes fra rent af appen selv
# (der findes intet Apple-værktøj, der fjerner én enkelt post – 'sfltool resetbtm' nulstiller
# ALLE login-emner og bruges derfor ikke). Kan appen det (--unregister-login-item), beder vi den
# om det, før den slettes. Bagefter tjekker vi (kun læsning) om posten stadig står der.
step "Melder \"Åbn ved login\" fra"
BIN="$APP/Contents/MacOS/$APP_NAME"
if [[ -x "$BIN" ]] && grep -aq -- "--unregister-login-item" "$BIN" 2>/dev/null; then
  if $dry; then
    do_it "$BIN" --unregister-login-item
  else
    "$BIN" --unregister-login-item >/dev/null 2>&1 &
    pid=$!
    for _ in {1..50}; do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null && did "Meldt fra." || info "Appen svarede ikke – se nedenfor."
  fi
elif [[ -x "$BIN" ]]; then
  info "Denne version af appen kan ikke melde sig selv fra. Posten forsvinder normalt af sig selv, når appen er slettet."
else
  info "Appen er ikke installeret – intet at melde fra."
fi

# 3) Slet appen --------------------------------------------------------------
step "Sletter appen"
if [[ -e "$APP" ]]; then
  do_it rm -rf "$APP" && did "Slettet: $APP"
else
  ok "Allerede væk: $APP"
fi

# 4) Indstillinger -------------------------------------------------------------
step "Sletter indstillingerne (størrelse, tema, placering …)"
for domain in "$BUNDLE_ID" pladespiller.selftest pladespiller.snapshots; do
  if defaults read "$domain" >/dev/null 2>&1; then
    do_it defaults delete "$domain" >/dev/null 2>&1 && did "Slettet: $domain"
  else
    ok "Ingen gemte indstillinger: $domain"
  fi
done

# 5) Tilladelser -------------------------------------------------------------
step "Nulstiller tilladelsen til at styre Spotify og Musik"
if do_it tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1; then
  did "Nulstillet. (Installeres appen igen, spørger macOS på ny.)"
else
  info "Der var ingen tilladelse at nulstille."
fi

# 6) Logfiler og mellemlager ----------------------------------------------------
step "Sletter logfiler og midlertidige filer"
for p in "$HOME/Library/Logs/$APP_NAME" \
         "$HOME/Library/Caches/$BUNDLE_ID" \
         "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
         "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"; do
  if [[ -e "$p" ]]; then
    do_it rm -rf "$p" && did "Slettet: $p"
  fi
done
ok "Færdig med logfiler."

# 7) Tjek om login-posten er væk ---------------------------------------------------
step "Tjekker login-emner"
if sfltool dumpbtm 2>/dev/null | grep -q "$BUNDLE_ID"; then
  info "macOS viser stadig $APP_NAME under login-emner. Det er ufarligt (appen er væk),"
  info "men du kan fjerne den selv: Systemindstillinger ▸ Generelt ▸ Login-emner og"
  info "udvidelser ▸ vælg $APP_NAME ▸ tryk på minus (–)."
else
  ok "$APP_NAME står ikke længere under login-emner."
fi

# 8) Signering (valgfrit) -----------------------------------------------------------
step "Signeringen (det lokale certifikat, der får macOS til at huske tilladelsen)"
if [[ -z "$answer" ]]; then
  if [[ -t 0 ]]; then
    read -r "svar?  Skal den også fjernes? Den skal kun bruges, hvis du vil bygge appen igen. [j/N] "
    [[ "${svar:l}" == j* || "${svar:l}" == y* ]] && answer=ja || answer=nej
  else
    answer=nej
  fi
fi
if [[ "$answer" == ja ]]; then
  if $dry; then do_it "$SCRIPTS/remove-signing.sh"; else "$SCRIPTS/remove-signing.sh" | sed 's/^/  /'; fi
else
  ok "Beholdt. Fjern den senere med: scripts/remove-signing.sh"
fi

if $dry; then print "\nPrøvekørsel slut – intet blev ændret."; else print "\n$APP_NAME er fjernet."; fi
exit 0
