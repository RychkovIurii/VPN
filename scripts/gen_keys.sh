#!/usr/bin/env bash
set -euo pipefail

XRAY_IMAGE="${1:-ghcr.io/xtls/xray-core:latest}"

echo "== Generate x25519, UUID, shortId =="

command -v docker >/dev/null || { echo "docker not found"; exit 1; }

PAIR=$(docker run --rm "$XRAY_IMAGE" xray x25519)
XR_PRIVKEY=$(echo "$PAIR" | awk '/Private key:/ {print $3}')
XR_PUBKEY=$(echo  "$PAIR" | awk '/Public key:/  {print $3}')
UUID=$(docker run --rm "$XRAY_IMAGE" xray uuid)
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
