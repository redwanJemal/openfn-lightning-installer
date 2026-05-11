# OpenFn Lightning — one-line installer

A single bash script that provisions a production-ready
[OpenFn Lightning](https://github.com/OpenFn/lightning) stack from official
Docker Hub images. Inspired by Coolify's `curl | bash` flow.

## Status

In active development. Currently:

- OS detection (Debian/Ubuntu + RHEL family)
- Docker + Compose plugin auto-install
- `.env` generation with strong random secrets (`SECRET_KEY_BASE`,
  `WORKER_SECRET`, `PRIMARY_ENCRYPTION_KEY`, `POSTGRES_PASSWORD`,
  RSA keypair for worker JWTs)

Still to come: `docker-compose.yml` generation, migrations, stack start,
health check.

## Requirements

- Linux: Debian/Ubuntu or RHEL/CentOS/Rocky/Alma/Fedora
- `curl`, `bash`, `openssl` (auto-installed if missing)
- Root or `sudo` access (for the initial Docker install)
- Outbound network access to Docker Hub

## Run

```bash
curl -fsSL https://raw.githubusercontent.com/redwanJemal/openfn-lightning-installer/main/install.sh -o install.sh
bash install.sh --domain localhost --admin-email you@example.com
```
