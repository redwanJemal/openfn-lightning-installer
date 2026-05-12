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
#   --admin-email <email>  Admin email used as EMAIL_ADMIN (default: admin@<domain>)
#   --install-dir <path>   Install directory (default: /opt/openfn-lightning or $HOME/openfn-lightning)
#   --non-interactive      Skip prompts; use defaults / passed flags
#   -h, --help             Show help

set -Eeuo pipefail

# ---- constants -------------------------------------------------------------

LIGHTNING_IMAGE="openfn/lightning:latest"
WORKER_IMAGE="openfn/ws-worker:latest"
POSTGRES_IMAGE="postgres:15.12-alpine"

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

# ---- prompts ---------------------------------------------------------------

prompt() {
  local var_name="$1" question="$2" default="${3:-}"
  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    printf -v "$var_name" '%s' "$default"
    return
  fi
  local answer
  if [[ -n "$default" ]]; then
    read -r -p "$question [$default]: " answer </dev/tty || true
  else
    read -r -p "$question: " answer </dev/tty || true
  fi
  printf -v "$var_name" '%s' "${answer:-$default}"
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
    ok "Docker Compose plugin present: $(docker compose version --short 2>/dev/null || docker compose version | head -1)"
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
    die "Unsupported distro for automatic Compose plugin install: $OS_ID. Install 'docker compose' manually."
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

# ---- secret generators -----------------------------------------------------

require_openssl() {
  command -v openssl >/dev/null 2>&1 && return
  log "Installing openssl..."
  need_sudo
  if is_debian_family; then
    $SUDO apt-get update -y && $SUDO apt-get install -y openssl
  elif is_rhel_family; then
    if command -v dnf >/dev/null 2>&1; then $SUDO dnf install -y openssl; else $SUDO yum install -y openssl; fi
  else
    die "openssl is required but not installed."
  fi
}

gen_hex()    { openssl rand -hex "$1"; }
gen_b64()    { openssl rand -base64 "$1" | tr -d '\n'; }
gen_b64url() { openssl rand -base64 "$1" | tr -d '\n=' | tr '+/' '-_'; }

gen_rsa_keypair_b64() {
  # Generate an RSA keypair, emit base64-encoded PEMs (single line) on stdout.
  # Output format: "<private_b64>|<public_b64>"
  local tmpdir priv_pem pub_pem
  tmpdir="$(mktemp -d)"
  priv_pem="$tmpdir/private.pem"
  pub_pem="$tmpdir/public.pem"
  openssl genrsa -out "$priv_pem" 2048 >/dev/null 2>&1
  openssl rsa -in "$priv_pem" -pubout -out "$pub_pem" >/dev/null 2>&1
  local priv_b64 pub_b64
  priv_b64="$(base64 -w0 <"$priv_pem" 2>/dev/null || base64 <"$priv_pem" | tr -d '\n')"
  pub_b64="$(base64 -w0 <"$pub_pem" 2>/dev/null || base64 <"$pub_pem" | tr -d '\n')"
  rm -rf "$tmpdir"
  printf '%s|%s' "$priv_b64" "$pub_b64"
}

# ---- env file generation ---------------------------------------------------

write_env_file() {
  # Idempotent: if .env exists, preserve it untouched.
  if [[ -f "$INSTALL_DIR/.env" ]]; then
    ok "Existing .env found; reusing it (secrets preserved)."
    # shellcheck disable=SC1091
    set -a; . "$INSTALL_DIR/.env"; set +a
    return
  fi

  log "Generating secrets..."
  local secret_key_base worker_secret primary_enc_key postgres_password
  secret_key_base="$(gen_b64 48)"          # ~64 chars base64
  worker_secret="$(gen_b64 32)"            # 256-bit
  primary_enc_key="$(gen_b64 32)"          # 32 random bytes, base64-encoded
  postgres_password="$(gen_b64url 24)"     # url-safe (no '/' or '=' in DATABASE_URL)

  local keypair priv_key pub_key
  keypair="$(gen_rsa_keypair_b64)"
  priv_key="${keypair%%|*}"
  pub_key="${keypair##*|}"

  local scheme="http" external_port="$PORT"
  if [[ "$DOMAIN" != "localhost" && "$DOMAIN" != "127.0.0.1" ]]; then
    warn "Domain is '$DOMAIN'. URL_SCHEME defaults to 'http' — set URL_SCHEME=https and URL_PORT=443 in .env once TLS is fronted by a reverse proxy."
  fi

  umask 077
  cat >"$INSTALL_DIR/.env" <<EOF
# OpenFn Lightning configuration — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Treat this file as a secret. Permissions are restricted to the installing user.

# --- Public URL ---
URL_HOST=${DOMAIN}
URL_PORT=${external_port}
URL_SCHEME=${scheme}
PORT=4000
LISTEN_ADDRESS=0.0.0.0

# --- Host port binding (controls 'ports:' mapping in docker-compose.yml) ---
LIGHTNING_HOST_BIND=0.0.0.0
LIGHTNING_HOST_PORT=${external_port}

# --- Mode ---
MIX_ENV=prod
NODE_ENV=production
DOCKER_RESTART_POLICY=unless-stopped

# --- Database ---
POSTGRES_USER=lightning
POSTGRES_PASSWORD=${postgres_password}
POSTGRES_DB=lightning
DATABASE_URL=postgresql://lightning:${postgres_password}@postgres:5432/lightning
DISABLE_DB_SSL=true
ECTO_IPV6=false

# --- Secrets (DO NOT regenerate after first run — see PRIMARY_ENCRYPTION_KEY note) ---
SECRET_KEY_BASE=${secret_key_base}
PRIMARY_ENCRYPTION_KEY=${primary_enc_key}
WORKER_SECRET=${worker_secret}
WORKER_RUNS_PRIVATE_KEY=${priv_key}
WORKER_LIGHTNING_PUBLIC_KEY=${pub_key}

# --- Admin / email ---
EMAIL_ADMIN=${ADMIN_EMAIL}
MAIL_PROVIDER=local

# --- Storage ---
STORAGE_BACKEND=local

# --- Worker tuning ---
WORKER_CAPACITY=5
WORKER_MAX_RUN_DURATION_SECONDS=300
WORKER_MAX_RUN_MEMORY_MB=500
RUN_GRACE_PERIOD_SECONDS=10
EOF
  chmod 600 "$INSTALL_DIR/.env"
  ok "Wrote $INSTALL_DIR/.env (mode 0600)"

  # Export for the rest of this script.
  # shellcheck disable=SC1091
  set -a; . "$INSTALL_DIR/.env"; set +a
}

# ---- docker-compose.yml ----------------------------------------------------

write_compose_file() {
  # Idempotent: only write if missing or different.
  local target="$INSTALL_DIR/docker-compose.yml"
  local tmp; tmp="$(mktemp)"
  cat >"$tmp" <<'YAML'
# OpenFn Lightning — production stack
# Pulled images only (no source checkout required).

services:
  postgres:
    image: postgres:15.12-alpine
    restart: ${DOCKER_RESTART_POLICY:-unless-stopped}
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 5s

  web:
    image: openfn/lightning:latest
    pull_policy: always
    restart: ${DOCKER_RESTART_POLICY:-unless-stopped}
    depends_on:
      postgres:
        condition: service_healthy
    env_file:
      - .env
    ports:
      - "${LIGHTNING_HOST_BIND:-0.0.0.0}:${LIGHTNING_HOST_PORT:-4000}:4000"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:4000/health_check || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 6
      start_period: 20s

  worker:
    image: openfn/ws-worker:latest
    pull_policy: always
    restart: ${DOCKER_RESTART_POLICY:-unless-stopped}
    depends_on:
      web:
        condition: service_healthy
    environment:
      WORKER_SECRET: ${WORKER_SECRET}
      WORKER_LIGHTNING_PUBLIC_KEY: ${WORKER_LIGHTNING_PUBLIC_KEY}
      WORKER_CAPACITY: ${WORKER_CAPACITY:-5}
      WORKER_MAX_RUN_DURATION_SECONDS: ${WORKER_MAX_RUN_DURATION_SECONDS:-300}
      WORKER_MAX_RUN_MEMORY_MB: ${WORKER_MAX_RUN_MEMORY_MB:-500}
    command: ["pnpm", "start:prod", "-l", "ws://web:4000/worker"]
    expose:
      - "2222"

volumes:
  postgres-data:
YAML

  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    ok "docker-compose.yml unchanged."
    rm -f "$tmp"
  else
    mv "$tmp" "$target"
    ok "Wrote $target"
  fi
}

# ---- compose wrapper -------------------------------------------------------

compose() {
  ( cd "$INSTALL_DIR" && docker compose --env-file .env "$@" )
}

pull_images() {
  log "Pulling images: $LIGHTNING_IMAGE, $WORKER_IMAGE, $POSTGRES_IMAGE..."
  compose pull
  ok "Images pulled."
}

run_migrations() {
  # OpenFn's prod image is a Mix release at /app/bin/lightning — `mix` is NOT
  # available. Migrations are exposed via Lightning.Release.migrate/0.
  log "Starting postgres for migrations..."
  compose up -d postgres
  log "Waiting for postgres to be healthy..."
  for _ in $(seq 1 30); do
    local state
    state="$(compose ps --format '{{.Health}}' postgres 2>/dev/null | head -1)"
    [[ "$state" == "healthy" ]] && break
    sleep 2
  done
  log "Creating database (if needed) and running migrations..."
  compose run --rm --no-deps web /app/bin/lightning eval "Lightning.Release.create_db()"
  compose run --rm --no-deps web /app/bin/lightning eval "Lightning.Release.migrate()"
  ok "Migrations complete."
}

start_stack() {
  log "Starting full stack (web + worker + postgres)..."
  compose up -d
  ok "Stack started."
}

wait_for_health() {
  # NOTE: use LIGHTNING_HOST_PORT (host-side binding) — PORT was clobbered to
  # the container-internal value (4000) when we sourced .env.
  local url="http://127.0.0.1:${LIGHTNING_HOST_PORT}/health_check"
  log "Waiting for Lightning to be reachable at $url ..."
  local attempt=0 max=60
  while (( attempt < max )); do
    if curl -fsS -o /dev/null "$url"; then
      ok "Lightning is reachable."
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  err "Lightning did not become healthy within $((max * 2))s."
  warn "Recent web logs:"
  compose logs --tail=80 web >&2 || true
  return 1
}

# ---- main ------------------------------------------------------------------

main() {
  log "OpenFn Lightning installer"
  detect_os
  log "Detected OS: ${OS_ID} (like: ${OS_LIKE:-n/a})"

  is_debian_family || is_rhel_family || die "Unsupported OS family. Supported: Debian/Ubuntu, RHEL/CentOS/Rocky/Alma/Fedora."

  require_openssl
  install_docker
  install_compose_plugin
  ensure_docker_running

  if [[ "$NON_INTERACTIVE" != "true" ]]; then
    prompt DOMAIN       "Public hostname"   "$DOMAIN"
    prompt PORT         "Host port to bind" "$PORT"
    prompt ADMIN_EMAIL  "Admin email"       "${ADMIN_EMAIL:-admin@${DOMAIN}}"
  else
    [[ -n "$ADMIN_EMAIL" ]] || ADMIN_EMAIL="admin@${DOMAIN}"
  fi
  [[ "$PORT" =~ ^[0-9]+$ ]] || die "PORT must be numeric, got: $PORT"

  log "Install dir: $INSTALL_DIR"
  log "Domain:      $DOMAIN"
  log "Port:        $PORT"
  log "Admin email: $ADMIN_EMAIL"

  mkdir -p "$INSTALL_DIR"

  write_env_file
  write_compose_file
  pull_images
  run_migrations
  start_stack

  if wait_for_health; then
    cat <<EOF

${C_GREEN}${C_BOLD}OpenFn Lightning is up.${C_RESET}

  URL:           http://${DOMAIN}:${LIGHTNING_HOST_PORT}
  Login page:    http://${DOMAIN}:${LIGHTNING_HOST_PORT}/users/log_in
  Health check:  http://127.0.0.1:${LIGHTNING_HOST_PORT}/health_check
  Config:        ${INSTALL_DIR}/.env  (chmod 600 — back this up)
  Compose file:  ${INSTALL_DIR}/docker-compose.yml

No superuser is seeded by default. Create the first one by running
(from ${INSTALL_DIR}, replace the password — min 12 chars):

  docker compose exec web /app/bin/lightning rpc \\
    'Lightning.Accounts.register_superuser(%{first_name: "Admin", last_name: "User", email: "${ADMIN_EMAIL}", password: "CHANGE-ME-min-12-chars"})'

Then sign in at the login page above.

Common commands (run from ${INSTALL_DIR}):
  docker compose logs -f web
  docker compose ps
  docker compose down            # stop
  docker compose pull && docker compose up -d   # upgrade

EOF
    exit 0
  else
    die "Install completed but Lightning failed health check. Inspect 'docker compose logs' in $INSTALL_DIR."
  fi
}

main "$@"
