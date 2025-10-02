#!/usr/bin/env bash
set -euo pipefail
[ -f .env ] || { echo ".env missing"; exit 1; }
source .env

: "${UUID:?}"
: "${XR_PUBKEY:?}"
: "${SHORTID:?}"
: "${SNI:?}"
: "${XRAY_PORT:=443}"

HOST_INPUT="${1:-${XRAY_HOST:-}}"
: "${HOST_INPUT:?Set XRAY_HOST in .env or pass host/IP as first argument}"
HOST="${HOST_INPUT}"

# v2ray/v2rayN style VLESS REALITY URI
# vless://<uuid>@<host>:<port>?encryption=none&flow=xtls-rprx-vision&security=reality&fp=chrome&pbk=<pub>&sni=<sni>&sid=<shortid>&type=tcp#Reality
URI="vless://${UUID}@${HOST}:${XRAY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&fp=chrome&pbk=${XR_PUBKEY}&sni=${SNI}&sid=${SHORTID}&type=tcp#Reality"
echo "$URI"
