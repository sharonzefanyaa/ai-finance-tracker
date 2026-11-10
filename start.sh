#!/usr/bin/env bash
# Start the Cloudflare tunnel first, retrieve its URL, then run n8n with
# WEBHOOK_URL so the Telegram Trigger registers a valid HTTPS URL.
set -euo pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo ".env file not found. Copy it from .env.example first."; exit 1; }

echo "-> Starting tunnel..."
docker compose up -d --force-recreate cloudflared

URL=""
for _ in $(seq 1 30); do
  URL=$(docker compose logs cloudflared 2>&1 \
        | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' \
        | grep -v '^https://api\.' | tail -1 || true)
  [ -n "$URL" ] && break
  sleep 2
done
[ -n "$URL" ] || { echo "Failed to retrieve tunnel URL. Check: docker compose logs cloudflared"; exit 1; }

echo "-> Tunnel URL: $URL"
export WEBHOOK_URL="$URL"

echo "-> Starting Postgres + n8n..."
docker compose up -d postgres

echo "-> Applying functions.sql (safe to rerun; does not modify data)..."
for i in $(seq 1 30); do
  if docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT to_regclass('"'"'public.transactions'"'"') IS NOT NULL"' 2>/dev/null | grep -q t; then
    docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -v ON_ERROR_STOP=1' < functions.sql \
      || { echo "functions.sql failed to apply. Check the error message above."; exit 1; }
    break
  fi
  [ "$i" = 30 ] && { echo "Postgres/tables are not ready. Check: docker compose logs postgres"; exit 1; }
  sleep 2
done
docker compose up -d --force-recreate n8n

echo
echo "Done. n8n Editor: http://localhost:5678"
echo "Telegram Webhook: $URL"
echo "If the bot does not respond, open the workflow and deactivate it, then activate it again (toggle Active)."