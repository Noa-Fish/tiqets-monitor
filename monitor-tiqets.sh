#!/usr/bin/env bash
set -euo pipefail

URL="https://www.tiqets.com/web_api/availability/groups?groupId=1111400&productIds=975248%2C1120188%2C918256&fromDate=2026-09-03&currency=EUR&salesChannel=tiqets.com"

PRODUCT_ID=918256
DATE_DEBUT="2026-09-03"
DATE_FIN="2026-09-18"

: "${TIQETS_COOKIE:?Variable TIQETS_COOKIE manquante}"
: "${DISCORD_WEBHOOK:?Variable DISCORD_WEBHOOK manquante}"

STATE_FILE="${STATE_FILE:-data/state.json}"

mkdir -p "$(dirname "$STATE_FILE")"

if [ ! -f "$STATE_FILE" ]; then
  printf '%s\n' '{"notified_dates":[]}' > "$STATE_FILE"
fi

RESPONSE=$(
  curl --silent --show-error --fail \
    --max-time 20 \
    --url "$URL" \
    -H "accept: application/json" \
    -H "accept-language: fr-FR,fr;q=0.9" \
    -H "referer: https://www.tiqets.com/fr/checkout/sagrada-familia-billet-avec-acces-rapide-tours-en-option-g1111400/?partner=barcelonahacks&selected_date=2026-09-06&selected_product=918256" \
    -H "user-agent: Mozilla/5.0" \
    -b "$TIQETS_COOKIE"
)

AVAILABLE_DATES=$(
  echo "$RESPONSE" | jq -r \
    --argjson productId "$PRODUCT_ID" \
    --arg debut "$DATE_DEBUT" \
    --arg fin "$DATE_FIN" '
      [
        .dates[]?
        | select(.date >= $debut and .date <= $fin)
        | select(
            (.availableProducts // [])
            | any(.productId == $productId)
          )
        | .date
      ]
      | sort
      | .[]
    '
)

if [ -z "$AVAILABLE_DATES" ]; then
  echo "PAS_DISPO dans la plage $DATE_DEBUT → $DATE_FIN"
  printf '%s\n' '{"notified_dates":[]}' > "$STATE_FILE"
  exit 0
fi

echo "Dates disponibles :"
echo "$AVAILABLE_DATES"

NEW_DATES=$(
  while IFS= read -r date; do
    if ! jq -e --arg date "$date" \
      '.notified_dates | index($date) != null' \
      "$STATE_FILE" >/dev/null; then
      echo "$date"
    fi
  done <<< "$AVAILABLE_DATES"
)

if [ -z "$NEW_DATES" ]; then
  echo "Aucune nouvelle date à notifier."
  exit 0
fi

FIRST_NEW_DATE=$(echo "$NEW_DATES" | head -n 1)
DATES_TEXT=$(echo "$NEW_DATES" | paste -sd ", " -)

MESSAGE="🚨 Nouvelle disponibilité Tiqets pour le produit ${PRODUCT_ID} : ${DATES_TEXT}
https://www.tiqets.com/fr/checkout/sagrada-familia-billet-avec-acces-rapide-tours-en-option-g1111400/?partner=barcelonahacks&selected_date=${FIRST_NEW_DATE}&selected_product=${PRODUCT_ID}"

PAYLOAD=$(jq -n --arg content "$MESSAGE" '{content: $content}')

curl --silent --show-error --fail \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$DISCORD_WEBHOOK"

jq \
  --rawfile newDates <(printf '%s\n' "$NEW_DATES") \
  '
    .notified_dates = (
      .notified_dates
      + ($newDates | split("\n") | map(select(length > 0)))
      | unique
      | sort
    )
  ' \
  "$STATE_FILE" > "${STATE_FILE}.tmp"

mv "${STATE_FILE}.tmp" "$STATE_FILE"

echo "Notification Discord envoyée pour : $DATES_TEXT"