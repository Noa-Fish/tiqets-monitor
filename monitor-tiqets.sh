#!/usr/bin/env bash
set -euo pipefail

URL='https://www.tiqets.com/web_api/availability/groups?groupId=1111400&productIds=975248%2C1120188%2C918256&fromDate=2026-09-03&currency=EUR&salesChannel=tiqets.com'

: "${TIQETS_COOKIE:?Variable TIQETS_COOKIE manquante}"
: "${DISCORD_WEBHOOK:?Variable DISCORD_WEBHOOK manquante}"
: "${STATE_FILE:=state.json}"

# Plage de dates souhaitée
DATE_DEBUT="2026-09-03"
DATE_FIN="2026-09-18"

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

# Initialiser state.json s'il n'existe pas
if [ ! -f "$STATE_FILE" ]; then
  echo '{"last_notified_date":null}' > "$STATE_FILE"
fi

LAST_NOTIFIED=$(jq -r '.last_notified_date // empty' "$STATE_FILE")

# Trouver la première date dispo pour le produit 918256 dans la plage
FIRST_DATE_IN_RANGE=$(
  echo "$RESPONSE" | jq -r --arg deb "$DATE_DEBUT" --arg fin "$DATE_FIN" '
    .dates
    | map(select(.availableProducts != null))
    | map(select(.availableProducts | map(.productId == 918256) | any))
    | map(select(.date >= $deb and .date <= $fin))
    | sort_by(.date)
    | .[0].date
    // empty
  '
)

if [ -z "$FIRST_DATE_IN_RANGE" ]; then
  echo "PAS_DISPO dans la plage $DATE_DEBUT – $DATE_FIN"
  # On reset l'état si plus rien de dispo
  if [ "$LAST_NOTIFIED" != "null" ] && [ -n "$LAST_NOTIFIED" ]; then
    jq '.last_notified_date = null' "$STATE_FILE" > "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
    git add "$STATE_FILE"
    git commit -m "Reset: plus de dispo dans la plage" || true
    git push || true
  fi
  exit 0
fi

echo "DISPO 918256 à partir du $FIRST_DATE_IN_RANGE (plage $DATE_DEBUT – $DATE_FIN)"

NEED_NOTIFY=false

# Première dispo détectée
if [ -z "$LAST_NOTIFIED" ] || [ "$LAST_NOTIFIED" = "null" ]; then
  NEED_NOTIFY=true
fi

# Nouvelle date plus tôt que celle déjà notifiée
if [ -n "$LAST_NOTIFIED" ] && [ "$LAST_NOTIFIED" != "null" ]; then
  if [[ "$FIRST_DATE_IN_RANGE" < "$LAST_NOTIFIED" ]]; then
    NEED_NOTIFY=true
  fi
fi

if [ "$NEED_NOTIFY" = true ]; then
  MESSAGE="🚨 Disponibilité détectée sur Tiqets pour le 918256 à partir du $FIRST_DATE_IN_RANGE — va acheter maintenant : https://www.tiqets.com/fr/checkout/sagrada-familia-billet-avec-acces-rapide-tours-en-option-g1111400/?partner=barcelonahacks&selected_date=$FIRST_DATE_IN_RANGE&selected_product=918256"

  curl --silent --show-error --fail \
    -X POST \
    -H 'Content-Type: application/json' \
    -d "{\"content\": \"$MESSAGE\"}" \
    "$DISCORD_WEBHOOK"

  # Mettre à jour state.json
  jq --arg d "$FIRST_DATE_IN_RANGE" '.last_notified_date = $d' "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"

  git add "$STATE_FILE"
  git commit -m "Update dispo: $FIRST_DATE_IN_RANGE" || true
  git push || true
else
  echo "Déjà notifié pour une date <= $FIRST_DATE_IN_RANGE (last_notified_date=$LAST_NOTIFIED)"
fi