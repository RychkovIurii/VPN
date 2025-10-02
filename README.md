# Reality VPN Deployments

Repository now ships two self-contained setups under `deployments/`:

- `deployments/cli/` – single Xray container fully managed by Make targets. Ideal if you just need Reality inbound + generated credentials.
- `deployments/panel/` – Xray + 3x-ui panel with write access to configs. Use this when you want to manage users through the web UI.

Use the top-level Makefile to route commands:

```
make cli           # show CLI-only targets
make cli-run       # bootstrap the CLI deployment (init → ask-sni → gen-keys → up)
make panel         # show panel deployment targets
make panel-run     # same bootstrap but with 3x-ui
```

## CLI-only deployment (`deployments/cli`)

1. `make cli-run` – installs Docker if needed, collects SNI/host, generates keys, renders `xray/config.json`, and starts the container.
2. `make cli-show-client` – prints the VLESS Reality URI from `.env`.
3. `make cli-fw-open-xray` – opens the chosen XRAY port in UFW (optional).

Regenerate config after changing environment variables: `make cli-config`.

## Panel deployment (`deployments/panel`)

1. `make panel-run` – same bootstrap flow, but spins up both Xray and 3x-ui (panel).
2. Access the panel through SSH tunnel: `ssh -L 4242:127.0.0.1:4242 user@server`, then open `http://localhost:4242`.
3. Create or import the inbound in 3x-ui; afterwards manage users there. The panel has full write access to `deployments/panel/xray/`.
4. When you change inbounds/users through the panel, rerun `make panel-up` (or `docker compose -f deployments/panel/docker-compose.yml restart xray`) so the dedicated Xray container reloads the updated config.

Firewall helpers:

- `make panel-fw-open-xray`
- `make panel-fw-open-panel-ip`
- `make panel-fw-close-panel`

## Common scripts

Reusable helper scripts live in `scripts/`:

- `gen_keys.sh` – generates UUID/X25519 pairs via Docker.
- `validate_sni.sh` – quick SNI TLS/ALPN check.
- `make_vless_uri.sh` – builds a VLESS Reality URI from `.env`.
- `install_docker.sh` – installs Docker Engine + compose plugin when missing.

Each deployment keeps its own `.env` and `.env.example` so you can configure/dev independently.
