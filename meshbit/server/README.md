# Meshbit private Matrix homeserver (free-tier deployment)

This folder prepares a self-hosted Matrix Synapse server. It is **not deployed yet**: it needs a Linux VPS with a stable public IPv4 address. Cloudflare Workers cannot host Synapse because it is a persistent stateful service; R2 is not required.

## Zero-cost target

Use an Oracle Cloud Always Free Ampere VM if an Always Free shape is available in the selected region. Oracle account creation, payment-card verification, region capacity and VM provisioning must be completed in the Oracle console. Do not send account passwords, API keys or card data in chat.

For a no-domain test endpoint, this stack uses the public `sslip.io` DNS wildcard: `matrix.<PUBLIC_IP>.sslip.io`. Caddy requests and renews HTTPS certificates automatically. Reserve a stable public IP before generating the Matrix config: Matrix server names are permanent and cannot safely be renamed after accounts are created.

## VM requirements

- Ubuntu 24.04, ARM64 or AMD64
- Stable public IPv4
- 2+ vCPU and 4+ GB RAM recommended for a small private beta
- Inbound TCP 22 (SSH), 80 and 443; do not expose PostgreSQL or Synapse port 8008
- Docker Engine and Docker Compose plugin

## Deploy

1. Create an Always Free VM and reserve its public IP.
2. Clone this repository and enter `meshbit/server`.
3. Copy `.env.example` to `.env`.
4. Set `SERVER_NAME=matrix.<YOUR_PUBLIC_IP>.sslip.io`; generate two different long random secrets for the database and registration secret.
5. Run `./setup.sh`.
6. Verify `https://<SERVER_NAME>/_matrix/client/versions` returns JSON.
7. Create accounts with the admin CLI (registration is disabled publicly):
   `docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008`
8. Keep federation port 8448 closed for this private beta. Back up the PostgreSQL volume and `data/` signing keys.

## Security boundaries

- Synapse stores encrypted room events when clients use Matrix E2EE; it does not encrypt plaintext messages on behalf of a broken client.
- Public account registration is disabled. Create users only with the admin CLI.
- Caddy terminates HTTPS. PostgreSQL is isolated on an internal Docker network.
- This setup is a small private beta, not a hardened public federation service. Add monitoring, off-host encrypted backups, resource alerts and an incident/recovery plan before broad release.

## Current app integration status

The mobile app currently builds the Matrix Rust SDK and checks homeserver login capabilities. It does **not yet** authenticate users, create encrypted rooms, send/receive encrypted events, or implement Bluetooth LE mesh. Deploying this server alone will not make those client features ready.
