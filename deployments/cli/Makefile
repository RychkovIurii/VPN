SHELL := /usr/bin/env
.SHELLFLAGS := bash -eu -o pipefail -c
.ONESHELL:
.SILENT:
.PHONY: help init ask-sni check-sni gen-keys config up down restart logs status clean fclean show-client bootstrap run

.DEFAULT_GOAL := run

XRAY_IMAGE ?= ghcr.io/xtls/xray-core:latest
XRAY_PORT_DEFAULT := 443

SCRIPTS_DIR := ../../scripts
TEMPLATES_DIR := templates
XRAY_DIR := xray
ENV_FILE := .env

help: ## show targets
	echo "Usage: make <target>"
	echo ""
	grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

init: ## prepare folders & ensure tooling
	touch $(ENV_FILE)
	mkdir -p $(XRAY_DIR)
	if ! command -v docker >/dev/null; then \
	  echo "docker not found; attempting automatic install"; \
	  bash $(SCRIPTS_DIR)/install_docker.sh docker || { echo "failed to install docker"; exit 1; }; \
	fi
	command -v docker >/dev/null || { echo "docker still missing after install"; exit 1; }
	if ! docker compose version >/dev/null 2>&1; then \
	  echo "docker compose plugin not found; attempting automatic install"; \
	  bash $(SCRIPTS_DIR)/install_docker.sh compose || { echo "failed to install docker compose plugin"; exit 1; }; \
	fi
	docker compose version >/dev/null 2>&1 || { echo "docker compose plugin still missing"; exit 1; }
	command -v openssl >/dev/null || { echo "openssl not found"; exit 1; }
	command -v curl >/dev/null || command -v wget >/dev/null || { echo "curl or wget required"; exit 1; }
	command -v envsubst >/dev/null || { echo "envsubst not found (install gettext-base)"; exit 1; }

ask-sni: ## prompt SNI/server host, update .env
	valid_host() { \
	  local candidate="$$1"; \
	  local domain_re='^([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$$'; \
	  local ipv4_re='^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$$'; \
	  [[ "$$candidate" =~ $$domain_re ]] || [[ "$$candidate" =~ $$ipv4_re ]]; \
	}; \
	detect_ipv4() { \
	  local ip=""; \
	  if command -v curl >/dev/null; then \
	    ip=$$(curl -4 -fsS --retry 2 https://ifconfig.me 2>/dev/null || true); \
	    [ -z "$$ip" ] && ip=$$(curl -4 -fsS --retry 2 https://ifconfig.co 2>/dev/null || true); \
	  fi; \
	  if [ -z "$$ip" ] && command -v wget >/dev/null; then \
	    ip=$$(wget -qO- -4 https://ifconfig.me 2>/dev/null || true); \
	  fi; \
	  if [ -z "$$ip" ] && command -v dig >/dev/null; then \
	    ip=$$(dig +short -4 myip.opendns.com @resolver1.opendns.com 2>/dev/null || true); \
	  fi; \
	  printf '%s' "$$ip"; \
	}; \
	SNI_VALUE="$(strip $(SNI))"; \
	if [ -z "$$SNI_VALUE" ] && [ -f $(ENV_FILE) ]; then \
	  SNI_VALUE=$(awk -F= '/^SNI=/{print $$2; exit}' $(ENV_FILE)); \
	fi; \
	if [ -z "$$SNI_VALUE" ]; then \
	  read -p "Enter SNI (e.g. www.example.com): " SNI_VALUE; \
	else \
	  echo "Using existing SNI=$$SNI_VALUE"; \
	fi; \
	if ! valid_host "$$SNI_VALUE"; then \
	  echo "Invalid SNI '$$SNI_VALUE'."; \
	  exit 1; \
	fi; \
	XRAY_HOST_VALUE="$(strip $(XRAY_HOST))"; \
	if [ -z "$$XRAY_HOST_VALUE" ] && [ -f $(ENV_FILE) ]; then \
	  XRAY_HOST_VALUE=$(awk -F= '/^XRAY_HOST=/{print $$2; exit}' $(ENV_FILE)); \
	fi; \
	if [ -z "$$XRAY_HOST_VALUE" ]; then \
	  XRAY_HOST_VALUE=$$(detect_ipv4); \
	  [ -n "$$XRAY_HOST_VALUE" ] && echo "Detected XRAY_HOST=$$XRAY_HOST_VALUE"; \
	fi; \
	if [ -z "$$XRAY_HOST_VALUE" ]; then \
	  read -p "Enter server host/IP for clients: " XRAY_HOST_VALUE; \
	else \
	  echo "Using existing XRAY_HOST=$$XRAY_HOST_VALUE"; \
	fi; \
	if ! valid_host "$$XRAY_HOST_VALUE"; then \
	  echo "Invalid XRAY_HOST '$$XRAY_HOST_VALUE'."; \
	  exit 1; \
	fi; \
	XRAY_PORT_VALUE="$(strip $(XRAY_PORT))"; \
	if [ -z "$$XRAY_PORT_VALUE" ] && [ -f $(ENV_FILE) ]; then \
	  XRAY_PORT_VALUE=$(awk -F= '/^XRAY_PORT=/{print $$2; exit}' $(ENV_FILE)); \
	fi; \
	XRAY_PORT_VALUE="$$XRAY_PORT_VALUE"; \
	[ -n "$$XRAY_PORT_VALUE" ] || XRAY_PORT_VALUE="$(XRAY_PORT_DEFAULT)"; \
	tmp=$(ENV_FILE).tmp; \
	trap 'rm -f "$$tmp"' EXIT; \
	[ -f $(ENV_FILE) ] && cp $(ENV_FILE) "$$tmp" || : > "$$tmp"; \
	upsert() { \
	  local k="$$1" v="$$2"; \
	  if grep -q "^$$k=" "$$tmp" 2>/dev/null; then \
	    sed -i "s|^$$k=.*|$$k=$$v|" "$$tmp"; \
	  else \
	    echo "$$k=$$v" >> "$$tmp"; \
	  fi; \
	}; \
	upsert SNI "$$SNI_VALUE"; \
	upsert DEST "$$SNI_VALUE:$$XRAY_PORT_VALUE"; \
	upsert XRAY_PORT "$$XRAY_PORT_VALUE"; \
	upsert XRAY_HOST "$$XRAY_HOST_VALUE"; \
	mv "$$tmp" $(ENV_FILE); \
	trap - EXIT; \
	echo "Saved SNI=$$SNI_VALUE XRAY_HOST=$$XRAY_HOST_VALUE XRAY_PORT=$$XRAY_PORT_VALUE"

check-sni: ## validate SNI TLS/ALPN (scripts/validate_sni.sh)
	[ -f $(ENV_FILE) ] || { echo ".env missing. Run: make ask-sni"; exit 1; }
	SNI_VALUE=$(awk -F= '/^SNI=/{print $$2; exit}' $(ENV_FILE))
	[ -n "$$SNI_VALUE" ] || { echo "SNI is empty. Run: make ask-sni"; exit 1; }
	bash $(SCRIPTS_DIR)/validate_sni.sh "$$SNI_VALUE"

gen-keys: ## generate x25519 (pub/priv), UUID, shortId → .env
	bash $(SCRIPTS_DIR)/gen_keys.sh "$(XRAY_IMAGE)"

config: ## render xray/config.json from template + .env
	[ -f $(ENV_FILE) ] || { echo ".env missing. Run: make ask-sni gen-keys"; exit 1; }
	set -a
	. ./$(ENV_FILE)
	XRAY_PORT="$${XRAY_PORT:-$(XRAY_PORT_DEFAULT)}"
	export XRAY_PORT
	set +a
	required="SNI DEST UUID XR_PRIVKEY SHORTID"
	for var in $$required; do \
	  eval "val=\$${var}"; \
	  if [ -z "$$val" ]; then \
	    echo "Missing $$var in .env. Run: make ask-sni gen-keys"; \
	    exit 1; \
	  fi; \
	done
	mkdir -p $(XRAY_DIR)
	envsubst '$$XRAY_PORT $$UUID $$DEST $$SNI $$XR_PRIVKEY $$SHORTID' < $(TEMPLATES_DIR)/config.json.tpl > $(XRAY_DIR)/config.json
	echo "Wrote $(XRAY_DIR)/config.json"

up: config ## docker compose up -d
	DOCKER_DEFAULT_PLATFORM= docker compose up -d
	HOST_VALUE=$(awk -F= '/^XRAY_HOST=/{print $$2; exit}' $(ENV_FILE) 2>/dev/null)
	if [ -z "$$HOST_VALUE" ]; then \
	  HOST_VALUE=$(awk -F= '/^SNI=/{print $$2; exit}' $(ENV_FILE) 2>/dev/null); \
	fi; \
	if [ -z "$$HOST_VALUE" ]; then \
	  detect_ipv4() { \
	    local ip=""; \
	    if command -v curl >/dev/null; then \
	      ip=$$(curl -4 -fsS --retry 2 https://ifconfig.me 2>/dev/null || true); \
	      [ -z "$$ip" ] && ip=$$(curl -4 -fsS --retry 2 https://ifconfig.co 2>/dev/null || true); \
	    fi; \
	    if [ -z "$$ip" ] && command -v wget >/dev/null; then \
	      ip=$$(wget -qO- -4 https://ifconfig.me 2>/dev/null || true); \
	    fi; \
	    if [ -z "$$ip" ] && command -v dig >/dev/null; then \
	      ip=$$(dig +short -4 myip.opendns.com @resolver1.opendns.com 2>/dev/null || true); \
	    fi; \
	    printf '%s' "$$ip"; \
	  }; \
	  HOST_VALUE=$$(detect_ipv4); \
	fi
	[ -n "$$HOST_VALUE" ] || HOST_VALUE="<SERVER_IP>"
	XRAY_PORT_VALUE=$(awk -F= '/^XRAY_PORT=/{print $$2; exit}' $(ENV_FILE) 2>/dev/null)
	[ -n "$$XRAY_PORT_VALUE" ] || XRAY_PORT_VALUE="$(XRAY_PORT_DEFAULT)"
	echo "Xray: $$HOST_VALUE:$$XRAY_PORT_VALUE"

down: ## docker compose down
	docker compose down

restart: ## restart service
	docker compose restart

logs: ## tail xray logs
	docker logs -f xray-cli

status: ## docker compose ps
	docker compose ps

show-client: ## print vless:// URI
	bash $(SCRIPTS_DIR)/make_vless_uri.sh

bootstrap: init ask-sni gen-keys up ## one-shot provision

run: bootstrap ## default alias

fw-open-xray: ## allow XRAY_PORT in ufw
	XRAY_PORT_VALUE=$(awk -F= '/^XRAY_PORT=/{print $$2; exit}' $(ENV_FILE) 2>/dev/null)
	[ -n "$$XRAY_PORT_VALUE" ] || XRAY_PORT_VALUE="$(XRAY_PORT_DEFAULT)"
	sudo ufw allow $$XRAY_PORT_VALUE/tcp

clean: ## remove generated files (keep .env)
	rm -f $(XRAY_DIR)/config.json $(ENV_FILE).tmp

fclean: ## stop and purge containers, volumes, images
	docker compose down --volumes --remove-orphans || true
	docker image rm -f $(XRAY_IMAGE) 2>/dev/null || true
	rm -rf $(XRAY_DIR)/config.json $(ENV_FILE) $(ENV_FILE).tmp

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
