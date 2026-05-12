# OpenFn Lightning — one-line installer

A single bash script that provisions a production-ready
[OpenFn Lightning](https://github.com/OpenFn/lightning) stack
(Lightning web + worker + PostgreSQL) on a fresh Linux box.
Inspired by Coolify's `curl | bash` flow.

It pulls official images from Docker Hub — no source checkout required.

## What it does

1. Detects your OS (Debian/Ubuntu or RHEL/CentOS/Rocky/Alma/Fedora).
2. Installs Docker and the Docker Compose v2 plugin if missing (via `get.docker.com`).
3. Pulls `openfn/lightning:latest`, `openfn/ws-worker:latest`, `postgres:15.12-alpine`.
4. Generates a `.env` with strong random secrets:
   - `SECRET_KEY_BASE`, `WORKER_SECRET`, `PRIMARY_ENCRYPTION_KEY`
   - `POSTGRES_PASSWORD`
   - RSA keypair for `WORKER_RUNS_PRIVATE_KEY` / `WORKER_LIGHTNING_PUBLIC_KEY`
5. Writes a `docker-compose.yml` for the full stack.
6. Runs `Lightning.Release.create_db()` and `Lightning.Release.migrate()`.
7. Starts the stack and waits until `GET /health_check` returns 200.
8. Prints the URL, the location of `.env` (chmod 600), and the exact command to create the first superuser.

The script is **idempotent** — re-running it preserves your `.env` and never resets the database.

## Requirements

- Linux: Debian/Ubuntu or RHEL family
- `curl`, `bash`, `openssl` (auto-installed if missing)
- Root or `sudo` access (only needed for the initial Docker install)
- Outbound network access to Docker Hub

## Run it

### One-liner (download and execute)

```bash
curl -fsSL https://raw.githubusercontent.com/redwanJemal/openfn-lightning-installer/main/install.sh -o install.sh
bash install.sh --domain lightning.example.com --admin-email you@example.com
```

### Or pipe straight to bash (no flags)

```bash
curl -fsSL https://raw.githubusercontent.com/redwanJemal/openfn-lightning-installer/main/install.sh | bash
```

### Or clone the repo and run directly

```bash
git clone https://github.com/redwanJemal/openfn-lightning-installer.git
cd openfn-lightning-installer
bash install.sh --domain localhost --port 4500 --admin-email you@example.com
```

### Non-interactive (CI, provisioning)

```bash
bash install.sh \
  --non-interactive \
  --domain lightning.example.com \
  --port 4000 \
  --admin-email you@example.com \
  --install-dir /opt/openfn-lightning
```

## Flags

| Flag                | Default                                                | Description                                  |
| ------------------- | ------------------------------------------------------ | -------------------------------------------- |
| `--domain`          | `localhost`                                            | Public hostname (used for `URL_HOST`)        |
| `--port`            | `4000`                                                 | Host port to bind                            |
| `--admin-email`     | `admin@<domain>`                                       | Sets `EMAIL_ADMIN`; used in seed-user banner |
| `--install-dir`     | `/opt/openfn-lightning` (root) or `~/openfn-lightning` | Where `.env` and `docker-compose.yml` go     |
| `--non-interactive` | off                                                    | Skip prompts; use defaults / flags           |
| `-h`, `--help`      |                                                        | Show help                                    |

## After install — create the first user

The official Lightning prod image does **not** seed a default user.
The success banner prints the exact command; run it from your install dir
(replace the password — min 12 chars):

```bash
cd /opt/openfn-lightning   # or wherever you installed
docker compose exec web /app/bin/lightning rpc \
  'Lightning.Accounts.register_superuser(%{first_name: "Admin", last_name: "User", email: "you@example.com", password: "your-strong-password"})'
```

Then sign in at `http://<domain>:<port>/users/log_in`.

## Common operations

All run from your install dir:

```bash
docker compose ps                                  # status
docker compose logs -f web                         # tail web logs
docker compose logs -f worker                      # tail worker logs
docker compose down                                # stop (data persists)
docker compose up -d                               # start
docker compose pull && docker compose up -d        # upgrade to latest images
```

The PostgreSQL data lives in a named Docker volume (`<install-dir>_postgres-data`).
`docker compose down -v` deletes it — only do that if you want to wipe everything.

## Putting it behind HTTPS

The script defaults to `URL_SCHEME=http` and binds to `0.0.0.0:<port>`. In production:

1. Run a reverse proxy (Caddy, nginx, Traefik) terminating TLS at `:443`.
2. Edit `<install-dir>/.env`:
   - `URL_SCHEME=https`
   - `URL_PORT=443`
3. Optionally set `LIGHTNING_HOST_BIND=127.0.0.1` so Lightning only listens on loopback.
4. `docker compose up -d` to apply.

## Files written

- `<install-dir>/.env` — secrets and config, mode `0600`. **Back this up.**
  Losing `PRIMARY_ENCRYPTION_KEY` makes stored credentials unrecoverable.
- `<install-dir>/docker-compose.yml` — the stack definition.

## Troubleshooting

**`curl: (7) Failed to connect to 127.0.0.1 port <port>`**
The web container is still booting. Check `docker compose logs web` from the install dir.

**`Migrations already up`**
Expected on re-runs. The script is idempotent.

**`role "lightning" does not exist` after wiping `.env` but keeping the volume**
The DB volume holds credentials matching the old `.env`. Either restore the old `.env` or
`docker compose down -v` (destroys data) and re-run.

**Health check fails after install**
Run `docker compose logs web` — most often `SECRET_KEY_BASE` mismatch (someone edited `.env`
after first boot) or the DB volume was deleted while `.env` stayed.

## Compatibility notes

- The script uses `Lightning.Release.migrate/0` instead of `mix ecto.migrate` because the
  official `openfn/lightning` image is a Mix release with no `mix` binary.
- The superuser is created via `docker compose exec web /app/bin/lightning rpc` rather
  than `eval` — `eval` doesn't start `Lightning.Repo` so `register_superuser` fails.
- Tested against Lightning `2.16.x` and Docker Engine `29.x` / Compose `v5.x`.
