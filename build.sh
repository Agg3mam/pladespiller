#!/bin/zsh
# Bygger Pladespiller.app.
#   ./build.sh            byg til build/Pladespiller.app
#   ./build.sh --install  byg, læg i ~/Applications
#   ./build.sh --run      byg, læg i ~/Applications og start (lukker en kørende kopi først)
#   ./build.sh --run --mock   som --run, men med testdata
# Signering: SIGN_IDENTITY (standard "-" = ad hoc). Ejes af Build-agenten.
set -euo pipefail
cd "${0:A:h}"

APP_NAME="Pladespiller"
APP="build/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

install=false; run=false; extra_args=()
for a in "$@"; do
  case "$a" in
    --install) install=true ;;
    --run) install=true; run=true ;;
    *) extra_args+=("$a") ;;
  esac
done

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

codesign --force --sign "$SIGN_IDENTITY" --identifier dk.holgerskov.Pladespiller "$APP"
echo "Bygget: $APP"

if $install; then
  pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP" "$INSTALL_DIR/"
  echo "Installeret: $INSTALL_DIR/$APP_NAME.app"
fi

if $run; then
  open "$INSTALL_DIR/$APP_NAME.app" --args "${extra_args[@]}"
fi
