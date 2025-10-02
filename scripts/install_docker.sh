#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-docker}"  # docker | compose | both
if [[ "$ACTION" != "docker" && "$ACTION" != "compose" && "$ACTION" != "both" ]]; then
  echo "Usage: $0 [docker|compose|both]" >&2
  exit 1
fi

# Determine privilege escalation
SUDO=""
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if command -v sudo >/dev/null; then
    SUDO="sudo"
  else
    echo "This script needs root privileges. Install sudo or run as root." >&2
    exit 1
  fi
fi

fetch_script() {
  local url="$1"
  local dest="$2"
  if command -v curl >/dev/null; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null; then
    wget -q "$url" -O "$dest"
  else
    echo "Neither curl nor wget is available to download $url" >&2
    return 1
  fi
}

install_docker() {
if command -v docker >/dev/null; then
    return 0
fi
  echo "Installing Docker Engine via get.docker.com script"
  local tmp
  tmp=$(mktemp)
  fetch_script "https://get.docker.com" "$tmp"
  chmod +x "$tmp"
  $SUDO "$tmp"
  rm -f "$tmp"
  if ! command -v docker >/dev/null; then
    echo "Docker installation did not succeed" >&2
    return 1
  fi
  # Ensure service is running
  if command -v systemctl >/dev/null; then
    $SUDO systemctl enable --now docker >/dev/null 2>&1 || true
  fi
  # Inform user about group membership
  local target_user="${SUDO_USER:-${USER:-$(id -un)}}"
  if getent group docker >/dev/null; then
    if id -nG "$target_user" 2>/dev/null | grep -qw docker; then
      echo "User $target_user already in docker group"
    else
      echo "Adding $target_user to docker group (logout/login required)"
      $SUDO usermod -aG docker "$target_user" || true
    fi
  fi
}

install_compose_plugin() {
  if ! command -v docker >/dev/null; then
    install_docker
  fi
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi
  echo "Installing Docker Compose plugin"
  if command -v apt-get >/dev/null; then
    $SUDO apt-get update -y
    $SUDO apt-get install -y docker-compose-plugin
  elif command -v yum >/dev/null || command -v dnf >/dev/null; then
    local mgr
    if command -v dnf >/dev/null; then mgr=dnf; else mgr=yum; fi
    $SUDO "$mgr" install -y docker-compose-plugin || $SUDO "$mgr" install -y docker-compose
  else
    # fallback to standalone binary under /usr/local/bin
    local version="v2.27.0"
    local arch
    arch=$(uname -m)
    case "$arch" in
      x86_64|amd64) arch="x86_64" ;;
      aarch64|arm64) arch="aarch64" ;;
      armv7l) arch="armv7" ;;
      *) echo "Unsupported architecture '$arch' for docker compose binary" >&2; return 1 ;;
    esac
    local url="https://github.com/docker/compose/releases/download/${version}/docker-compose-$(uname -s)-${arch}"
    local dest="/usr/local/bin/docker-compose"
    fetch_script "$url" /tmp/docker-compose
    chmod +x /tmp/docker-compose
    $SUDO mv /tmp/docker-compose "$dest"
    # shim for `docker compose`
    if ! command -v docker-compose >/dev/null; then
      echo "Installed docker-compose standalone at $dest"
    fi
    if ! docker compose version >/dev/null 2>&1; then
      mkdir -p ~/.docker/cli-plugins
      $SUDO mkdir -p /usr/libexec/docker/cli-plugins 2>/dev/null || true
      local plugin_dest="/usr/libexec/docker/cli-plugins/docker-compose"
      $SUDO cp "$dest" "$plugin_dest" 2>/dev/null || true
    fi
  fi
  docker compose version >/dev/null 2>&1
}

case "$ACTION" in
  docker)
    install_docker
    ;;
  compose)
    install_compose_plugin
    ;;
  both)
    install_docker
    install_compose_plugin
    ;;
 esac
