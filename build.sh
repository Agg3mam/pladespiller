#!/bin/zsh
# Bygger Pladespiller.app.
#   ./build.sh                byg til build/Pladespiller.app
#   ./build.sh --install      byg og læg i ~/Applications (lukker en kørende kopi først)
#   ./build.sh --run          som --install, og start appen
#   ./build.sh --run --mock   som --run, med testdata (andre ukendte argumenter sendes også videre til appen)
#
# Signering (ejes af Build-agenten):
#   Findes den lokale identitet "Pladespiller Local Signing" (lav den én gang med
#   scripts/setup-signing.sh), signeres der med den, så macOS husker tilladelsen til at
#   styre Spotify/Musik mellem builds. Ellers ad hoc ("-") med en besked.
#   SIGN_IDENTITY=<navn/hash> eller SIGN_IDENTITY=- tilsidesætter valget.
set -euo pipefail
cd "${0:A:h}"
source scripts/signing-common.sh

APP_NAME="Pladespiller"
BUNDLE_ID="dk.holgerskov.Pladespiller"
APP="build/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"

die() { print -u2 "Fejl: $*"; exit 1; }

install=false; run=false; extra_args=()
for a in "$@"; do
  case "$a" in
    --install) install=true ;;
    --run) install=true; run=true ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) extra_args+=("$a") ;;
  esac
done

command -v swift >/dev/null || die "swift blev ikke fundet. Installér Command Line Tools: xcode-select --install"

# --- Byg ---------------------------------------------------------------------
# De to ld-advarsler "search path '/Library/Developer/CommandLineTools/Developer/...' not found"
# er harmløse: SwiftPM foreslår Xcodes test-mapper, som ikke findes med kun Command Line Tools.
# De filtreres væk; alle andre beskeder vises.
echo "Bygger $APP_NAME (release, arm64)…"
build_log="$(mktemp)"; trap 'rm -f "$build_log"' EXIT
if ! swift build -c release --arch arm64 >"$build_log" 2>&1; then
  grep -v "ld: warning: search path '/Library/Developer/CommandLineTools/Developer/" "$build_log" >&2 || true
  die "swift build fejlede (se ovenfor)."
fi
grep -E "warning:|error:" "$build_log" \
  | grep -v "ld: warning: search path '/Library/Developer/CommandLineTools/Developer/" || true
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
[[ -x "$BIN" ]] || die "fandt ikke den byggede fil: $BIN"

# --- Pak .app ----------------------------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/"
else
  echo "Bemærk: Resources/AppIcon.icns mangler (lav det med: swift scripts/make-icon.swift)."
fi
plutil -lint -s "$APP/Contents/Info.plist" || die "Info.plist er ugyldig."

# --- Signér ------------------------------------------------------------------
# Ingen hardened runtime (--options runtime): den er kun et krav ved notarisering/distribution,
# og her ville den blot kræve ekstra entitlements for Apple Events uden gevinst for en lokal app.
codesign_args=(--force --timestamp=none --identifier "$BUNDLE_ID")
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  identity="$SIGN_IDENTITY"
  if [[ "$identity" == "$SIGN_CERT_NAME" || ( -n "$identity" && "$identity" == "$(sign_identity_hash)" ) ]]; then
    sign_unlock_keychain || die "kunne ikke låse $SIGN_KEYCHAIN op."
    codesign_args+=(--keychain "$SIGN_KEYCHAIN")
  fi
else
  identity="$(sign_identity_hash)"
  if [[ -n "$identity" ]] && sign_unlock_keychain; then
    codesign_args+=(--keychain "$SIGN_KEYCHAIN")
  else
    identity="-"
    echo "Bemærk: signerer ad hoc. macOS vil spørge om lov til at styre Spotify/Musik efter hver build."
    echo "        Kør én gang: scripts/setup-signing.sh  – så huskes tilladelsen."
  fi
fi
codesign "${codesign_args[@]}" --sign "$identity" "$APP" \
  || die "codesign fejlede. Prøv: scripts/remove-signing.sh && scripts/setup-signing.sh"
codesign --verify --strict "$APP" || die "signaturen kunne ikke verificeres."
if [[ "$identity" == "-" ]]; then
  echo "Bygget: $APP (ad hoc-signeret)"
else
  echo "Bygget: $APP (signeret med \"$SIGN_CERT_NAME\")"
fi

# --- Installér / start -------------------------------------------------------
if $install; then
  if pgrep -x "$APP_NAME" >/dev/null; then
    echo "Lukker den kørende $APP_NAME…"
    pkill -x "$APP_NAME" || true
    for _ in {1..50}; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.1; done
    if pgrep -x "$APP_NAME" >/dev/null; then
      echo "Bemærk: $APP_NAME lukkede ikke inden for 5 sekunder – tvinger den til at lukke."
      pkill -9 -x "$APP_NAME" || true
      for _ in {1..20}; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.1; done
    fi
    if pgrep -x "$APP_NAME" >/dev/null; then
      die "$APP_NAME kører stadig og kunne ikke lukkes. Luk den selv (Aktivitetsovervågning) og prøv igen."
    fi
  fi
  mkdir -p "$INSTALL_DIR" || die "kunne ikke oprette $INSTALL_DIR"
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP" "$INSTALL_DIR/" || die "kunne ikke kopiere appen til $INSTALL_DIR"
  echo "Installeret: $INSTALL_DIR/$APP_NAME.app"
fi

if $run; then
  if (( ${#extra_args} )); then
    open "$INSTALL_DIR/$APP_NAME.app" --args "${extra_args[@]}"
  else
    open "$INSTALL_DIR/$APP_NAME.app"
  fi
  echo "Startet: $APP_NAME ${extra_args[*]}"
fi
