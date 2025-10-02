#!/usr/bin/env bash
set -euo pipefail

XRAY_IMAGE="${1:-ghcr.io/xtls/xray-core:latest}"

echo "== Generate x25519, UUID, shortId =="

command -v docker >/dev/null || { echo "docker not found"; exit 1; }

PAIR=$(docker run --rm "$XRAY_IMAGE" x25519)
extract_field() {
  local label="$1"
  awk -F': ' -v target="$label" 'BEGIN{IGNORECASE=1} $1==target {gsub(/\r/, "", $2); print $2; exit}'
}
XR_PRIVKEY=$(echo "$PAIR" | extract_field "PrivateKey")
if [ -z "$XR_PRIVKEY" ]; then
  XR_PRIVKEY=$(echo "$PAIR" | extract_field "Private key")
fi
XR_PUBKEY=$(echo "$PAIR" | extract_field "PublicKey")
if [ -z "$XR_PUBKEY" ]; then
  XR_PUBKEY=$(echo "$PAIR" | extract_field "Public key")
fi
if [ -z "$XR_PUBKEY" ]; then
  XR_PUBKEY=$(echo "$PAIR" | extract_field "Password")
fi
if [ -z "$XR_PRIVKEY" ] || [ -z "$XR_PUBKEY" ]; then
  echo "Failed to parse keys from xray x25519 output" >&2
  echo "$PAIR" >&2
  exit 1
fi
UUID=$(docker run --rm "$XRAY_IMAGE" uuid)
SHORTID=$(openssl rand -hex 8)

touch .env
upsert () {
  local k="$1" v="$2"
  if grep -q "^$k=" .env 2>/dev/null; then
    sed -i "s|^$k=.*|$k=$v|g" .env
  else
    echo "$k=$v" >> .env
  fi
}
upsert XR_PRIVKEY "$XR_PRIVKEY"
upsert XR_PUBKEY  "$XR_PUBKEY"
upsert UUID       "$UUID"
upsert SHORTID    "$SHORTID"

echo "XR_PRIVKEY=$XR_PRIVKEY"
echo "XR_PUBKEY=$XR_PUBKEY"
echo "UUID=$UUID"
echo "SHORTID=$SHORTID"
echo "Saved secrets to .env (do NOT commit)."
