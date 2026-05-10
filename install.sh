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

# ---- main ------------------------------------------------------------------

main() {
  log "OpenFn Lightning installer (scaffold)"
  log "Install dir: $INSTALL_DIR"
  log "Domain:      $DOMAIN"
  log "Port:        $PORT"
  warn "Install logic not implemented yet — see TODO."
}

main "$@"
