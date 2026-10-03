#!/bin/zsh
# Fjerner Pladespillers lokale signering igen (fx ved afinstallation):
# den dedikerede nøglering, dens adgangskode-fil og – hvis den mod forventning står der –
# nøgleringen på søgelisten. Rører ikke andre nøgleringe.
# Bagefter signerer build.sh ad hoc igen (og macOS vil spørge om tilladelse igen).
set -euo pipefail
source "${0:A:h}/signing-common.sh"

# Fjern fra søgelisten, hvis den står der (setup lægger den normalt ikke dér).
typeset -a search
search=("${(@f)$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')}")
typeset -a keep
keep=()
for k in "${search[@]}"; do
  [[ "$k" == *pladespiller-signing.keychain-db ]] || keep+=("$k")
done
if (( ${#keep} != ${#search} )); then
  security list-keychains -d user -s "${keep[@]}"
  echo "Fjernet fra nøgleringenes søgeliste."
fi

if [[ -f "$SIGN_KEYCHAIN" ]]; then
  security delete-keychain "$SIGN_KEYCHAIN" 2>/dev/null; rm -f "$SIGN_KEYCHAIN"
  echo "Slettet: $SIGN_KEYCHAIN"
fi
if [[ -f "$SIGN_PASS_FILE" ]]; then
  rm -f "$SIGN_PASS_FILE"
  rmdir "${SIGN_PASS_FILE:h}" 2>/dev/null || true
  echo "Slettet: $SIGN_PASS_FILE"
fi
echo "Pladespillers lokale signering er fjernet."
