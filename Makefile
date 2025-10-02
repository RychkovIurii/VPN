SHELL := /usr/bin/env
.SHELLFLAGS := bash -eu -o pipefail -c
.ONESHELL:
.SILENT:
.PHONY: help init ask-sni check-sni gen-keys config up down restart logs status clean fclean show-client bootstrap run

.DEFAULT_GOAL := run

# Constants / defaults
PANEL_PORT_DEFAULT := 4242
XRAY_PORT_DEFAULT  := 443
XRAY_IMAGE ?= ghcr.io/xtls/xray-core:latest
PANEL_IMAGE ?= ghcr.io/mhsanaei/3x-ui:latest

# ---- firewall helpers (UFW) ----
MY_IP      ?= 1.2.3.4      # set your workstation’s public IP here
HOST_HINT_RAW := $(shell [ -f .env ] && grep -E '^XRAY_HOST=' .env | tail -n1 | cut -d= -f2- )
HOST_HINT := $(if $(strip $(HOST_HINT_RAW)),$(strip $(HOST_HINT_RAW)),<SERVER_IP>)
PANEL_PORT_HINT_RAW := $(shell [ -f .env ] && grep -E '^PANEL_PORT=' .env | tail -n1 | cut -d= -f2- )
PANEL_PORT_HINT := $(if $(strip $(PANEL_PORT_HINT_RAW)),$(strip $(PANEL_PORT_HINT_RAW)),$(PANEL_PORT_DEFAULT))
XRAY_PORT_HINT_RAW := $(shell [ -f .env ] && grep -E '^XRAY_PORT=' .env | tail -n1 | cut -d= -f2- )
XRAY_PORT_HINT := $(if $(strip $(XRAY_PORT_HINT_RAW)),$(strip $(XRAY_PORT_HINT_RAW)),$(XRAY_PORT_DEFAULT))

help: ## show targets
	echo "Usage: make <target>"
	echo ""
	grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'


init: ## create folders & check tools
	touch .env
	mkdir -p xray templates scripts 3xui-data
	# Require docker, docker compose plugin, openssl, curl, envsubst
	command -v docker >/dev/null || { echo "docker not found"; exit 1; }
	docker compose version >/dev/null 2>&1 || { echo "docker compose plugin not found (install Docker Compose v2)"; exit 1; }
	command -v openssl >/dev/null || { echo "openssl not found"; exit 1; }
	command -v curl >/dev/null || { echo "curl not found"; exit 1; }
	command -v envsubst >/dev/null || { echo "envsubst not found (install gettext-base)"; exit 1; }

ask-sni: ## prompt SNI (decoy domain), write .env
	valid_host() { \
	  local candidate="$$1"; \
	  local domain_re='^([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$$'; \
	  local ipv4_re='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$$'; \
	  [[ "$$candidate" =~ $$domain_re ]] || [[ "$$candidate" =~ $$ipv4_re ]]; \
	}; \
	SNI_VALUE="$(strip $(SNI))"; \
	if [ -z "$$SNI_VALUE" ] && [ -f .env ]; then \
	  SNI_VALUE=$(awk -F= '/^SNI=/{print $$2; exit}' .env); \
	fi; \
	if [ -z "$$SNI_VALUE" ]; then \
	  read -p "Enter SNI (e.g. www.cloudflare.com): " SNI_VALUE; \
	else \
	  echo "Using existing SNI=$$SNI_VALUE"; \
	fi; \
	if ! valid_host "$$SNI_VALUE"; then \
	  echo "Invalid SNI '$$SNI_VALUE'. Use domain/IP like www.example.com"; \
	  exit 1; \
	fi; \
	XRAY_HOST_VALUE="$(strip $(XRAY_HOST))"; \
	if [ -z "$$XRAY_HOST_VALUE" ] && [ -f .env ]; then \
	  XRAY_HOST_VALUE=$(awk -F= '/^XRAY_HOST=/{print $$2; exit}' .env); \
	fi; \
	if [ -z "$$XRAY_HOST_VALUE" ]; then \
	  read -p "Enter your server host/IP for clients: " XRAY_HOST_VALUE; \
	else \
	  echo "Using existing XRAY_HOST=$$XRAY_HOST_VALUE"; \
	fi; \
	if ! valid_host "$$XRAY_HOST_VALUE"; then \
	  echo "Invalid XRAY_HOST '$$XRAY_HOST_VALUE'. Use domain/IP like vpn.example.com"; \
	  exit 1; \
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
	PANEL_PORT_VALUE="$(strip $(PANEL_PORT))"; \
	if [ -z "$$PANEL_PORT_VALUE" ] && grep -q '^PANEL_PORT=' "$$tmp"; then \
	  PANEL_PORT_VALUE=$(awk -F= '/^PANEL_PORT=/{print $$2; exit}' "$$tmp"); \
	fi; \
	PANEL_PORT_VALUE="$${PANEL_PORT_VALUE:-$(PANEL_PORT_DEFAULT)}"; \
	XRAY_PORT_VALUE="$(strip $(XRAY_PORT))"; \
	if [ -z "$$XRAY_PORT_VALUE" ] && grep -q '^XRAY_PORT=' "$$tmp"; then \
	  XRAY_PORT_VALUE=$(awk -F= '/^XRAY_PORT=/{print $$2; exit}' "$$tmp"); \
	fi; \
	XRAY_PORT_VALUE="$${XRAY_PORT_VALUE:-$(XRAY_PORT_DEFAULT)}"; \
	upsert SNI "$$SNI_VALUE"; \
	upsert DEST "$$SNI_VALUE:$${XRAY_PORT_VALUE}"; \
	upsert PANEL_PORT "$$PANEL_PORT_VALUE"; \
	upsert XRAY_PORT "$$XRAY_PORT_VALUE"; \
	upsert XRAY_HOST "$$XRAY_HOST_VALUE"; \
	mv "$$tmp" .env; \
	trap - EXIT; \
	echo "Saved SNI=$$SNI_VALUE XRAY_HOST=$$XRAY_HOST_VALUE to .env"

check-sni: ## validate SNI TLS/ALPN (scripts/validate_sni.sh)
	[ -f .env ] || { echo ".env missing. Run: make ask-sni"; exit 1; }
	SNI_VALUE=$(awk -F= '/^SNI=/{print $$2; exit}' .env)
	[ -n "$$SNI_VALUE" ] || { echo "SNI is empty. Run: make ask-sni"; exit 1; }
	bash scripts/validate_sni.sh "$$SNI_VALUE"

gen-keys: ## generate x25519 (pub/priv), UUID, shortId → .env
	bash scripts/gen_keys.sh "$(XRAY_IMAGE)"

config: ## render xray/config.json from template + .env
	[ -f .env ] || { echo ".env missing. Run: make ask-sni gen-keys"; exit 1; }
	set -a
	. ./.env
	set +a
	required_vars="SNI DEST UUID XR_PRIVKEY SHORTID"
	for var in $$required_vars; do \
	  eval "val=\$${var}"; \
	  if [ -z "$$val" ]; then \
	    echo "Missing $$var in .env. Run: make ask-sni gen-keys"; \
	    exit 1; \
	  fi; \
	done
	XRAY_PORT="$${XRAY_PORT:-$(XRAY_PORT_DEFAULT)}"
	PANEL_PORT="$${PANEL_PORT:-$(PANEL_PORT_DEFAULT)}"
	mkdir -p xray
	envsubst '$$XRAY_PORT $$UUID $$DEST $$SNI $$XR_PRIVKEY $$SHORTID' < templates/config.json.tpl > xray/config.json
	echo "Wrote xray/config.json"

up: config ## docker compose up -d
	DOCKER_DEFAULT_PLATFORM= docker compose up -d
	echo "Panel: http://$(HOST_HINT):$(PANEL_PORT_HINT)   Xray: $(HOST_HINT):$(XRAY_PORT_HINT)"

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

run: bootstrap ## default alias for bootstrap

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
	rm -f xray/config.json .env.tmp

fclean: ## stop and purge containers, volumes, images, data
	docker compose down --volumes --remove-orphans || true
	docker image rm -f $(XRAY_IMAGE) $(PANEL_IMAGE) 2>/dev/null || true
	rm -rf xray/config.json 3xui-data

.DEFAULT:
	case " $(MAKECMDGOALS) " in \
	  *" $@ "*) \
	    printf "Unknown target '%s'.\\n" "$@"; \
	    $(MAKE) help 2>/dev/null || true; \
	    exit 1; \
	    ;; \
	  *) \
	    exit 0; \
	    ;; \
	esac
