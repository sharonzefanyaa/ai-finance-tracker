#!/usr/bin/env bash
# Generate finance-tracker.json, safe for GitHub uploads, from an n8n export.
#
# What gets removed or replaced:
#   - your Telegram user ID (Telegram Trigger "userIds")  -> YOUR_TELEGRAM_USER_ID
#   - the n8n instance ID (meta.instanceId)               -> removed (empty)
# What is NOT in an n8n export in the first place: API keys, bot tokens and database passwords.
# Credentials appear only as a name + internal ID (for example "OpenAI account"); the ID is not a secret.
#
# Usage: bash sanitize-workflow.sh <n8n-export-file.json>
set -euo pipefail
[ $# -eq 1 ] || { echo "Usage: bash sanitize-workflow.sh <export-file.json>"; exit 1; }
[ -f "$1" ] || { echo "File not found: $1"; exit 1; }

sed -E \
  -e 's/("userIds": *")[0-9, ]+(")/\1YOUR_TELEGRAM_USER_ID\2/' \
  -e 's/("instanceId": *")[0-9a-fA-F]+(")/\1\2/' \
  "$1" > finance-tracker.json

# Safety checks: stop if anything private is still in the file.
if grep -qE '"userIds": *"[0-9]' finance-tracker.json; then
  echo "Original Telegram user ID still detected in the file. Do not commit."; exit 1
fi
if grep -qE '"instanceId": *"[0-9a-fA-F]+"' finance-tracker.json; then
  echo "instanceId still detected in the file. Do not commit."; exit 1
fi
if grep -qE '[0-9]{8,10}:[A-Za-z0-9_-]{30,}|sk-[A-Za-z0-9_-]{20,}|trycloudflare\.com' finance-tracker.json; then
  echo "Something that looks like a bot token, API key or tunnel URL is in the file. Do not commit."; exit 1
fi

echo "Done: finance-tracker.json is ready to commit."
grep '"userIds"' finance-tracker.json | tr -s ' '
