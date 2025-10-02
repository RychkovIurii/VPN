{
  "log": { "level": "warning" },
  "inbounds": [
    {
      "tag": "vless-reality-in",
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST}",
          "xver": 0,
          "serverNames": ["${SNI}"],
          "privateKey": "${XR_PRIVKEY}",
          "shortIds": ["${SHORTID}"],
          "spiderX": "/"
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["tls", "http"] }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ]
}
