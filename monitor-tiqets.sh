#!/usr/bin/env bash
set -euo pipefail

URL='https://www.tiqets.com/web_api/availability/groups?groupId=1111400&productIds=975248%2C1120188%2C918256&fromDate=2026-09-03&currency=EUR&salesChannel=tiqets.com'

PRODUCT_ID=918256
DATE_DEBUT='2026-09-03'
DATE_FIN='2026-09-18'

: "${TIQETS_COOKIE:?Variable TIQETS_COOKIE manquante}"
: "${DISCORD_WEBHOOK:?Variable DISCORD_WEBHOOK manquante}"

# En local : data/state.json.
# Dans GitHub Actions, STATE_FILE est aussi défini à data/state.json.
STATE_FILE="${STATE_FILE:-data/state.json}"

mkdir -p "$(dirname "$STATE_FILE")"

if [ ! -f "$STATE_FILE" ]; then
  printf '%s\n' '{"notified_dates":[]}' > "$STATE_FILE"
fi

RESPONSE=$(
  curl --silent --show-error --fail \
    --max-time 20 \
    --url "$URL" \
    -H 'accept: application/json' \
    -H 'accept-language: fr-FR,fr;q=0.9' \
    -H 'referer: https://www.tiqets.com/fr/checkout/sagrada-familia-billet-avec-acces-rapide-tours-en-option-g1111400/?partner=barcelonahacks&selected_date=2026-09-06&selected_product=918256' \
    -H 'user-agent: Mozilla/5.0' \
    -b "$TIQETS_COOKIE"
)

# Liste de toutes les dates disponibles, pour le produit demandé et dans ta plage.
AVAILABLE_DATES=$(
  echo "$RESPONSE" | jq -r \
    --argjson productId "$PRODUCT_ID" \
    --arg debut "$DATE_DEBUT" \
    --arg fin "$DATE_FIN" '
      [
        .dates[]?
        | select(.date >= $debut and .date