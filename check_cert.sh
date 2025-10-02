#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-www.example.com}"

echo "== Checking ${TARGET} =="

# 1) Certificate & Chain
echo -e "\n[Cert & Chain]"
echo | openssl s_client \
  -verify_return_error -verify_hostname "${TARGET}" \
  -servername "${TARGET}" -connect "${TARGET}:443" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

# 2) ALPN (HTTP/2?)
echo -e "\n[ALPN]"
echo | openssl s_client -alpn "h2,http/1.1" \
  -servername "${TARGET}" -connect "${TARGET}:443" 2>/dev/null \
  | awk '/ALPN protocol/ {print $0}'

# 3) Explicit TLS version checks
for ver in tls1_2 tls1_3; do
  echo -ne "\n[${ver}] "
  if echo | openssl s_client -"${ver}" \
     -servername "${TARGET}" -connect "${TARGET}:443" 2>/dev/null \
     | awk '/Protocol|Cipher/ {print $0}' | sed -n '1,2p'; then
    :
  else
    echo "not supported"
  fi
done

# 4) Quick HEAD request with HTTP/2
echo -e "\n[curl HEAD]"
curl -I --http2 -sD - "https://${TARGET}" | head -n 10
