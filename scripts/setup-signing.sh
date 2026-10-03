#!/bin/zsh
# Opretter ÉN gang et lokalt, selvsigneret kodesigneringscertifikat til Pladespiller.
#
# Hvorfor: ad hoc-signering giver appen et nyt "fingeraftryk" ved hver build, så macOS
# spørger om lov til at styre Spotify/Musik igen og igen. Med et fast certifikat er
# appens identitet den samme fra build til build, og tilladelsen huskes.
#
# Hvad det rører (og intet andet):
#   ~/Library/Keychains/pladespiller-signing.keychain-db   (egen, separat nøglering)
#   ~/.config/pladespiller/keychain-pass                    (dens adgangskode, rettigheder 600)
# Login-nøgleringen, nøgleringernes søgeliste, System-nøgleringen og tillidsindstillinger
# ændres IKKE. Ingen sudo. Fjern igen med scripts/remove-signing.sh.
#
# Kan køres flere gange: gør intet hvis alt allerede er på plads.
set -euo pipefail
source "${0:A:h}/signing-common.sh"

die() { print -u2 "Fejl: $*"; exit 1; }

if [[ -f "$SIGN_KEYCHAIN" && -f "$SIGN_PASS_FILE" ]] && sign_unlock_keychain; then
  existing="$(sign_identity_hash)"
  if [[ -n "$existing" ]]; then
    echo "Signering er allerede sat op: \"$SIGN_CERT_NAME\" ($existing)"
    echo "Nøglering: $SIGN_KEYCHAIN"
    exit 0
  fi
fi

# Halvfærdig/ødelagt opsætning fra tidligere: start forfra (kun vores egne filer).
if [[ -f "$SIGN_KEYCHAIN" ]]; then
  echo "Fandt en ufuldstændig Pladespiller-nøglering – laver den forfra."
  security delete-keychain "$SIGN_KEYCHAIN" 2>/dev/null || rm -f "$SIGN_KEYCHAIN"
fi

command -v openssl >/dev/null || die "openssl blev ikke fundet."

# Husk søgelisten, så vi kan sætte den præcis tilbage, hvis create-keychain ændrer den.
typeset -a search_before
search_before=("${(@f)$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')}")

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1) Adgangskode til den dedikerede nøglering (tilfældig, gemt lokalt med rettigheder 600).
mkdir -p "${SIGN_PASS_FILE:h}"
chmod 700 "${SIGN_PASS_FILE:h}"
( umask 077; openssl rand -hex 24 > "$SIGN_PASS_FILE" )
chmod 600 "$SIGN_PASS_FILE"
kc_pass="$(<"$SIGN_PASS_FILE")"

# 2) Selvsigneret certifikat: RSA 2048, kun til kodesignering, ca. 10 år.
cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGN_CERT_NAME
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" 2>/dev/null \
  || die "kunne ikke lave certifikatet med openssl."

# PKCS#12 med klassisk kryptering, som 'security import' kan læse.
p12_pass="$(openssl rand -hex 16)"
openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$SIGN_CERT_NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -passout "pass:$p12_pass" -out "$tmp/id.p12" 2>/dev/null \
  || die "kunne ikke pakke certifikatet (pkcs12)."

# 3) Egen nøglering, uden automatisk låsning.
security create-keychain -p "$kc_pass" "$SIGN_KEYCHAIN" || die "kunne ikke oprette nøgleringen."
security set-keychain-settings "$SIGN_KEYCHAIN"
security unlock-keychain -p "$kc_pass" "$SIGN_KEYCHAIN"

# Sæt søgelisten tilbage, hvis create-keychain har tilføjet den nye nøglering.
typeset -a search_after
search_after=("${(@f)$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')}")
if [[ "${search_after[*]}" != "${search_before[*]}" ]]; then
  security list-keychains -d user -s "${search_before[@]}"
fi

# 4) Importér nøgle+certifikat; kun codesign må bruge nøglen, uden at spørge.
security import "$tmp/id.p12" -k "$SIGN_KEYCHAIN" -P "$p12_pass" -T /usr/bin/codesign >/dev/null \
  || die "kunne ikke importere certifikatet i nøgleringen."
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$kc_pass" "$SIGN_KEYCHAIN" >/dev/null \
  || die "kunne ikke give codesign adgang til nøglen."

hash="$(sign_identity_hash)"
[[ -n "$hash" ]] || die "certifikatet blev importeret, men kan ikke findes som signeringsidentitet."

echo "Signering sat op: \"$SIGN_CERT_NAME\" ($hash)"
echo "Nøglering: $SIGN_KEYCHAIN"
echo "Adgangskode-fil: $SIGN_PASS_FILE"
echo "build.sh bruger det nu automatisk. Fjern igen med scripts/remove-signing.sh."
