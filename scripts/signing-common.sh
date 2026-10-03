# Fælles stier til den lokale signering. Indlæses af setup-/remove-signing.sh og build.sh.
SIGN_CERT_NAME="Pladespiller Local Signing"
SIGN_KEYCHAIN="$HOME/Library/Keychains/pladespiller-signing.keychain-db"
SIGN_PASS_FILE="$HOME/.config/pladespiller/keychain-pass"

# Skriver SHA-1 for signeringsidentiteten i den dedikerede nøglering (tom hvis ingen).
# Uden -v, fordi certifikatet bevidst ikke er "betroet" i systemet – det kan stadig signere.
sign_identity_hash() {
  [[ -f "$SIGN_KEYCHAIN" ]] || return 0
  security find-identity -p codesigning "$SIGN_KEYCHAIN" 2>/dev/null \
    | awk -v n="\"$SIGN_CERT_NAME\"" 'index($0, n) && $2 ~ /^[0-9A-F]{40}$/ { print $2; exit }'
}

sign_unlock_keychain() {
  [[ -f "$SIGN_PASS_FILE" ]] || return 1
  security unlock-keychain -p "$(<"$SIGN_PASS_FILE")" "$SIGN_KEYCHAIN" 2>/dev/null
}
