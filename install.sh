#!/usr/bin/env bash
#
# OpenFn Lightning one-line installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/redwanJemal/openfn-lightning-installer/main/install.sh | bash
#
# Flags:
#   --domain <host>        Public hostname (default: localhost)
#   --port <port>          Host port to bind (default: 4000)
#   --admin-email <email>  Admin email (default: admin@<domain>)
#   --install-dir <path>   Install directory
#   --non-interactive      Skip prompts; use defaults / passed flags
#   -h, --help             Show help

set -Eeuo pipefail

# ---- output helpers --------------------------------------------------------

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

log()  { printf '%s[+]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s[✓]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[✗]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { err "$*"; exit 1; }

trap 'err "Aborted on line $LINENO. See errors above."' ERR

# ---- defaults & flag parsing -----------------------------------------------

DOMAIN="localhost"
PORT="4000"
ADMIN_EMAIL=""
INSTALL_DIR=""
NON_INTERACTIVE="false"

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)           DOMAIN="${2:?missing value for --domain}"; shift 2 ;;
    --port)             PORT="${2:?missing value for --port}"; shift 2 ;;
    --admin-email)      ADMIN_EMAIL="${2:?missing value for --admin-email}"; shift 2 ;;
    --install-dir)      INSTALL_DIR="${2:?missing value for --install-dir}"; shift 2 ;;
    --non-interactive)  NON_INTERACTIVE="true"; shift ;;
    -h|--help)          usage ;;
    *) die "Unknown flag: $1 (use --help)" ;;
  esac
done

[[ "$PORT" =~ ^[0-9]+$ ]] || die "--port must be numeric, got: $PORT"

if [[ -z "$INSTALL_DIR" ]]; then
  if [[ $EUID -eq 0 ]]; then
    INSTALL_DIR="/opt/openfn-lightning"
  else
    INSTALL_DIR="${HOME}/openfn-lightning"
  fi
fi

# ---- sudo helper -----------------------------------------------------------

SUDO=""
need_sudo() {
  if [[ $EUID -ne 0 ]]; then
    command -v sudo >/dev/null || die "sudo is required to install Docker but is not installed."
    SUDO="sudo"
  fi
}

# ---- OS detection ----------------------------------------------------------

detect_os() {
  [[ -f /etc/os-release ]] || die "Cannot detect OS: /etc/os-release missing."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_LIKE="${ID_LIKE:-}"
}

is_debian_family() {
  case "$OS_ID" in ubuntu|debian|raspbian) return 0 ;; esac
  [[ "$OS_LIKE" == *debian* ]]
}

is_rhel_family() {
  case "$OS_ID" in rhel|centos|rocky|almalinux|fedora|amzn) return 0 ;; esac
  [[ "$OS_LIKE" == *rhel* || "$OS_LIKE" == *fedora* ]]
}

# ---- docker install --------------------------------------------------------

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    ok "Docker already installed: $(docker --version)"
    return
  fi
  log "Installing Docker via official get.docker.com convenience script..."
  need_sudo
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL https://get.docker.com -o "$tmp"; then
    rm -f "$tmp"
    die "Failed to download get.docker.com installer."
  fi
  $SUDO sh "$tmp"
  rm -f "$tmp"
  command -v docker >/dev/null || die "Docker install reported success but 'docker' is not on PATH."
  ok "Docker installed: $(docker --version)"
}

install_compose_plugin() {
  if docker compose version >/dev/null 2>&1; then
    ok "Docker Compose plugin present."
    return
  fi
  warn "Docker Compose v2 plugin missing; installing distro package..."
  need_sudo
  if is_debian_family; then
    $SUDO apt-get update -y
    $SUDO apt-get install -y docker-compose-plugin
  elif is_rhel_family; then
    if command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y docker-compose-plugin
    else
      $SUDO yum install -y docker-compose-plugin
    fi
  else
    die "Unsupported distro for automatic Compose plugin install: $OS_ID."
  fi
  docker compose version >/dev/null 2>&1 || die "Compose plugin install failed."
  ok "Docker Compose plugin installed."
}

ensure_docker_running() {
  if docker info >/dev/null 2>&1; then
    return
  fi
  warn "Docker daemon not reachable; attempting to start..."
  need_sudo
  if command -v systemctl >/dev/null 2>&1; then
    $SUDO systemctl enable --now docker || true
  elif command -v service >/dev/null 2>&1; then
    $SUDO service docker start || true
  fi
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    docker info >/dev/null 2>&1 && return
    sleep 1
  done
  die "Docker daemon is not running. Start it and re-run this script."
}

# ---- main ------------------------------------------------------------------

main() {
  log "OpenFn Lightning installer"
  detect_os
  log "Detected OS: ${OS_ID} (like: ${OS_LIKE:-n/a})"

  is_debian_family || is_rhel_family || die "Unsupported OS family. Supported: Debian/Ubuntu, RHEL/CentOS/Rocky/Alma/Fedora."

  install_docker
  install_compose_plugin
  ensure_docker_running

  log "Install dir: $INSTALL_DIR"
  log "Domain:      $DOMAIN"
  log "Port:        $PORT"
  warn "TODO: secret generation, env file, compose file, migrations."
}

main "$@"
