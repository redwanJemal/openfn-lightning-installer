# OpenFn Lightning — one-line installer

A single bash script that provisions a production-ready
[OpenFn Lightning](https://github.com/OpenFn/lightning) stack from official
Docker Hub images. Inspired by Coolify's `curl | bash` flow.

## Status

In active development. Currently handles OS detection and Docker /
Compose plugin installation; secret generation, env file, and stack
start-up are still to come.

## Requirements

- Linux: Debian/Ubuntu or RHEL/CentOS/Rocky/Alma/Fedora
- `curl`, `bash`
- Root or `sudo` access (for the initial Docker install)
- Outbound network access to Docker Hub

## Run

```bash
curl -fsSL https://raw.githubusercontent.com/redwanJemal/openfn-lightning-installer/main/install.sh -o install.sh
bash install.sh
```
