#!/usr/bin/env bash
#
# pem-to-keychain.sh
#
# Interactief macOS-script dat een PEM-certificaat en private key valideert,
# controleert of ze bij elkaar horen en ze direct in de login-keychain
# installeert (via een tijdelijk .p12-bestand met willekeurig wachtwoord).
# Handig voor mTLS (bijv. Home Assistant).
#
# Vereist: macOS (security, shasum) en openssl.
# Let op: -legacy is bewust gekozen voor compatibiliteit met macOS Keychain.

set -e

CERT=$(mktemp)
KEY=$(mktemp)
P12=$(mktemp).p12
PASSWORD=$(openssl rand -hex 24)

trap 'rm -f "$CERT" "$KEY" "$P12"' EXIT

echo "Plak het certificaat inclusief BEGIN en END:"
while IFS= read -r line </dev/tty; do
  printf '%s\n' "$line" >> "$CERT"
  case "$line" in
    *"-----END CERTIFICATE-----"*)
      break
      ;;
  esac
done

echo
echo "Plak nu de private key inclusief BEGIN en END:"
while IFS= read -r line </dev/tty; do
  printf '%s\n' "$line" >> "$KEY"
  case "$line" in
    *"-----END PRIVATE KEY-----"*|\
    *"-----END RSA PRIVATE KEY-----"*|\
    *"-----END EC PRIVATE KEY-----"*)
      break
      ;;
  esac
done

openssl x509 -in "$CERT" -noout
openssl pkey -in "$KEY" -noout

CERT_HASH=$(
  openssl x509 -in "$CERT" -pubkey -noout |
  openssl pkey -pubin -outform DER 2>/dev/null |
  shasum -a 256 |
  awk '{print $1}'
)

KEY_HASH=$(
  openssl pkey -in "$KEY" -pubout -outform DER 2>/dev/null |
  shasum -a 256 |
  awk '{print $1}'
)

if [ "$CERT_HASH" != "$KEY_HASH" ]; then
  echo "FOUT: certificaat en private key horen niet bij elkaar."
  exit 1
fi

openssl pkcs12 -export -legacy \
  -out "$P12" \
  -inkey "$KEY" \
  -in "$CERT" \
  -name "Home Assistant mTLS" \
  -passout pass:"$PASSWORD"

security import "$P12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "$PASSWORD"

echo
echo "Klaar. Geïnstalleerd in de login-keychain onder Mijn certificaten."
