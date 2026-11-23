#!/usr/bin/env bash
# Runs the keystore integration test (DEVICE=macos by default, or an Android device id) (FR-HTTP-013f): makes throwaway
# certificates with openssl (the sandboxed app cannot), passes them to the test
# as --dart-define values, and the test imports the client identity into the
# login Keychain, uses it through the relay and removes it again.
set -euo pipefail
cd "$(dirname "$0")/../apps/verbnest_app"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tag="$(date +%s)"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/s.key" -out "$tmp/s.pem" -days 1 \
  -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
  -addext "extendedKeyUsage=serverAuth" 2>/dev/null
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/c.key" -out "$tmp/c.pem" -days 1 \
  -subj "/CN=verbnest-it-$tag" -addext "extendedKeyUsage=clientAuth" 2>/dev/null
openssl pkcs12 -export -in "$tmp/c.pem" -inkey "$tmp/c.key" -out "$tmp/c.p12" -passout pass:it-pass \
  -keypbe AES-256-CBC -certpbe AES-256-CBC -macalg sha256
b64() { base64 < "$1" | tr -d '\n'; }
flutter test integration_test/keystore_test.dart -d "${DEVICE:-macos}" \
  --dart-define="KS_TAG=$tag" \
  --dart-define="KS_SERVER_PEM=$(b64 "$tmp/s.pem")" \
  --dart-define="KS_SERVER_KEY=$(b64 "$tmp/s.key")" \
  --dart-define="KS_CLIENT_PEM=$(b64 "$tmp/c.pem")" \
  --dart-define="KS_P12=$(b64 "$tmp/c.p12")" "$@"
