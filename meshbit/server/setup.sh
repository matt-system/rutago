#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created server/.env. Set SERVER_NAME to matrix.<PUBLIC_IP>.sslip.io and replace both passwords, then run this script again."
  exit 2
fi
set -a
source .env
set +a
: "${SERVER_NAME:?Set SERVER_NAME in .env}"
: "${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD in .env}"
: "${SYNAPSE_REGISTRATION_SHARED_SECRET:?Set SYNAPSE_REGISTRATION_SHARED_SECRET in .env}"
if [[ "$SERVER_NAME" == *REPLACE_WITH_PUBLIC_IP* ]]; then
  echo "SERVER_NAME still contains the example IP placeholder." >&2
  exit 2
fi
mkdir -p data
if [[ ! -f data/homeserver.yaml ]]; then
  docker run --rm -v "$PWD/data:/data" -e SYNAPSE_SERVER_NAME="$SERVER_NAME" -e SYNAPSE_REPORT_STATS=no matrixdotorg/synapse:latest generate
  docker run --rm --entrypoint python3 -v "$PWD/data:/data" -v "$PWD/configure_synapse.py:/configure_synapse.py:ro" -e SERVER_NAME="$SERVER_NAME" -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" -e SYNAPSE_REGISTRATION_SHARED_SECRET="$SYNAPSE_REGISTRATION_SHARED_SECRET" matrixdotorg/synapse:latest /configure_synapse.py
fi
docker compose up -d
echo "Synapse containers started. Verify: curl https://$SERVER_NAME/_matrix/client/versions"
