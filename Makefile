SHELL := /usr/bin/env
.SHELLFLAGS := bash -eu -o pipefail -c
.ONESHELL:
.SILENT:
.PHONY: help init ask-sni check-sni gen-keys config up down restart logs status clean show-client bootstrap

DEFAULT_GOAL := help

# Load .env if present
-include .env

# Defaults
PANEL_PORT ?= 4242
XRAY_PORT  ?= 443
XRAY_IMAGE ?= ghcr.io/xtls/xray-core:latest
PANEL_IMAGE ?= ghcr.io/mhsanaei/3x-ui:latest

# ---- firewall helpers (UFW) ----
MY_IP      ?= 1.2.3.4      # set your workstation’s public IP here
HOST_HINT := $(if $(strip $(XRAY_HOST)),$(strip $(XRAY_HOST)),<SERVER_IP>)

help: ## show targets
	echo "Usage: make <target>"
	echo ""
	grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'


init: ## create folders & check tools
	mkdir -p xray templates scripts 3xui-data
	# Require docker, docker compose plugin, openssl, curl, envsubst
	command -v docker >/dev/null || { echo "docker not found"; exit 1; }
	docker compose version >/dev/null 2>&1 || { echo "docker compose plugin not found (install Docker Compose v2)"; exit 1; }
	command -v openssl >/dev/null || { echo "openssl not found"; exit 1; }
	command -v curl >/dev/null || { echo "curl not found"; exit 1; }
	command -v envsubst >/dev/null || { echo "envsubst not found (install gettext-base)"; exit 1; }

ask-sni: ## prompt SNI (decoy domain), write .env
	SNI_VALUE="$(strip $(SNI))"; \
	if [ -z "$$SNI_VALUE" ]; then \
	  read -p "Enter SNI (e.g. www.cloudflare.com): " SNI_VALUE; \
	else \
	  echo "Using existing SNI=$$SNI_VALUE"; \
	fi; \
	XRAY_HOST_VALUE="$(strip $(XRAY_HOST))"; \
	if [ -z "$$XRAY_HOST_VALUE" ]; then \
	  read -p "Enter your server host/IP for clients: " XRAY_HOST_VALUE; \
	else \
	  echo "Using existing XRAY_HOST=$$XRAY_HOST_VALUE"; \
	fi; \
	tmp=.env.tmp; \
	trap 'rm -f "$$tmp"' EXIT; \
	if [ -f .env ]; then \
	  cp .env "$$tmp"; \
	else \
	  : > "$$tmp"; \
	fi; \
	upsert() { \
	  local k="$$1" v="$$2"; \
	  if grep -q "^$$k=" "$$tmp" 2>/dev/null; then \
	    sed -i "s|^$$k=.*|$$k=$$v|g" "$$tmp"; \
	  else \
	    echo "$$k=$$v" >> "$$tmp"; \
	  fi; \
	}; \
	upsert SNI "$$SNI_VALUE"; \
	upsert DEST "$$SNI_VALUE:443"; \
	upsert PANEL_PORT "$(PANEL_PORT)"; \
	upsert XRAY_PORT "$(XRAY_PORT)"; \
	upsert XRAY_HOST "$$XRAY_HOST_VALUE"; \
	mv "$$tmp" .env; \
	trap - EXIT; \
	echo "Saved SNI=$$SNI_VALUE XRAY_HOST=$$XRAY_HOST_VALUE to .env"

check-sni: ## validate SNI TLS/ALPN (scripts/validate_sni.sh)
	[ -n "$(SNI)" ] || { echo "SNI is empty. Run: make ask-sni"; exit 1; }
	bash scripts/validate_sni.sh "$(SNI)"

gen-keys: ## generate x25519 (pub/priv), UUID, shortId → .env
	bash scripts/gen_keys.sh "$(XRAY_IMAGE)"

config: ## render xray/config.json from template + .env
	[ -f .env ] || { echo ".env missing. Run: make ask-sni gen-keys"; exit 1; }
	[ -n "$(SNI)" -a -n "$(DEST)" -a -n "$(UUID)" -a -n "$(XR_PRIVKEY)" -a -n "$(SHORTID)" ] || \
	  { echo "Missing vars. Do: make ask-sni gen-keys"; exit 1; }
	mkdir -p xray
	export SNI="$(SNI)" DEST="$(DEST)" UUID="$(UUID)" XR_PRIVKEY="$(XR_PRIVKEY)" SHORTID="$(SHORTID)" XRAY_PORT="$(XRAY_PORT)"; \
	envsubst < templates/config.json.tpl > xray/config.json
	echo "Wrote xray/config.json"

up: config ## docker compose up -d
	DOCKER_DEFAULT_PLATFORM= docker compose up -d
	echo "Panel: http://$(HOST_HINT):$(PANEL_PORT)   Xray: $(HOST_HINT):$(XRAY_PORT)"

down: ## docker compose down
	docker compose down

restart: ## restart services
	docker compose restart

logs: ## tail xray logs
	docker logs -f xray

status: ## docker compose ps
	docker compose ps

show-client: ## print vless:// import URI (for v2rayN/NG)
	bash scripts/make_vless_uri.sh

bootstrap: init ask-sni gen-keys up ## provision & start everything

fw-open-xray: ## allow 443/tcp for Xray
	sudo ufw allow 443/tcp

fw-open-panel-ip: ## allow 4242/tcp only from MY_IP
	test "$(MY_IP)" != "" || { echo "Set MY_IP=your.ip.addr"; exit 1; }
	sudo ufw delete allow 4242/tcp || true
	sudo ufw allow from $(MY_IP) to any port 4242 proto tcp
	sudo ufw status | grep 4242 || true

fw-close-panel: ## remove any 4242 rules
	# This removes all 4242 allows (idempotent)
	sudo ufw status numbered | awk '/4242\/tcp/ {print $2}' | tr -d '[]' | sort -nr | xargs -r -I{} sudo ufw --force delete {}
	sudo ufw status | grep 4242 || true

clean: ## remove generated files (keeps .env)
	rm -f xray/config.json
