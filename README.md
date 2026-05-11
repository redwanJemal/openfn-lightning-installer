# OpenFn Lightning — one-line installer

A single bash script that provisions a production-ready
[OpenFn Lightning](https://github.com/OpenFn/lightning) stack
(Lightning web + worker + PostgreSQL) on a fresh Linux box.
Inspired by Coolify's `curl | bash` flow.

It pulls official images from Docker Hub — no source checkout required.

## What it does

1. Detects your OS (Debian/Ubuntu or RHEL/CentOS/Rocky/Alma/Fedora).
2. Installs Docker and the Docker Compose v2 plugin if missing.
3. Pulls `openfn/lightning:latest`, `openfn/ws-worker:latest`, `postgres:15.12-alpine`.
4. Generates a `.env` with strong random secrets.
5. Writes a `docker-compose.yml` for the full stack.
6. Runs `Lightning.Release.create_db()` and `Lightning.Release.migrate()`.
7. Starts the stack and waits until `GET /health_check` returns 200.
8. Prints the URL and the command to create the first superuser.

The script is **idempotent** — re-running it preserves your `.env` and
never resets the database.

## Requirements

- Linux: Debian/Ubuntu or RHEL family
- `curl`, `bash`, `openssl` (auto-installed if missing)
- Root or `sudo` access (only for the initial Docker install)
- Outbound network access to Docker Hub

## Run

```bash
curl -fsSL https://raw.githubusercontent.com/redwanJemal/openfn-lightning-installer/main/install.sh -o install.sh
bash install.sh --domain lightning.example.com --admin-email you@example.com
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
