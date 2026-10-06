#!/usr/bin/env bash
#
# pem-to-p12.sh
#
# Interactief macOS-script dat een PEM-certificaat en private key valideert,
# controleert of ze bij elkaar horen, en samenvoegt tot een met wachtwoord
# beveiligd PKCS#12 (.p12) bestand, handig voor mTLS (bijv. Home Assistant).
#
# Vereist: macOS (osascript, shasum) en openssl.
# Let op: -legacy is bewust gekozen voor compatibiliteit met macOS Keychain.

set -e

CERT=$(mktemp)
KEY=$(mktemp)

cleanup() {
  rm -f "$CERT" "$KEY"
}
trap cleanup EXIT

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

echo
echo "Certificaat en private key worden gecontroleerd..."

openssl x509 -in "$CERT" -noout >/dev/null
openssl pkey -in "$KEY" -noout >/dev/null

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

while true; do
  read -r -s -p "Kies een wachtwoord voor het .p12-bestand: " P12_PASSWORD </dev/tty
  echo
  read -r -s -p "Herhaal het wachtwoord: " P12_PASSWORD_CONFIRM </dev/tty
  echo

  if [ -z "$P12_PASSWORD" ]; then
    echo "Het wachtwoord mag niet leeg zijn."
  elif [ "$P12_PASSWORD" != "$P12_PASSWORD_CONFIRM" ]; then
    echo "De wachtwoorden komen niet overeen. Probeer opnieuw."
  else
    break
  fi
done

OUTPUT=$(
  osascript <<'APPLESCRIPT'
set outputFile to choose file name with prompt "Kies waar het PKCS#12-bestand moet worden opgeslagen" default name "home-assistant-mtls.p12"
return POSIX path of outputFile
APPLESCRIPT
)

case "$OUTPUT" in
  *.p12|*.P12)
    ;;
  *)
    OUTPUT="${OUTPUT}.p12"
    ;;
esac

openssl pkcs12 -export -legacy \
  -out "$OUTPUT" \
  -inkey "$KEY" \
  -in "$CERT" \
  -name "Home Assistant mTLS" \
  -passout pass:"$P12_PASSWORD"

chmod 600 "$OUTPUT"

unset P12_PASSWORD
unset P12_PASSWORD_CONFIRM

echo
echo "Klaar. Het PKCS#12-bestand is opgeslagen als:"
echo "$OUTPUT"
