#!/bin/bash
# Runs on the EC2 instance via SSM. All variables below are injected by
# the GitHub Actions deploy job (see deploy_via_ssm.py).
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${REPO:?REPO is required}"
: "${RUN_ID:?RUN_ID is required}"
: "${ART_NAME:?ART_NAME is required}"
: "${APP_PORT:?APP_PORT is required}"
: "${HEALTH_PATH:?HEALTH_PATH is required}"

TARGET_DIR="/home/ec2-user/landing-page"
STAGE_DIR="/home/ec2-user/landing-page-stage"
ZIP_PATH="/home/ec2-user/landing-page-artifact.zip"
ART_API="https://api.github.com/repos/${REPO}/actions/runs/${RUN_ID}/artifacts?per_page=100"

echo "Fetching artifact list from: $ART_API"
ART_RESPONSE=$(curl -fsSL \
  -H 'Accept: application/vnd.github+json' \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  "$ART_API")

echo "Available artifacts:"
echo "$ART_RESPONSE" | jq -r '.artifacts[].name'

ART_ID=$(echo "$ART_RESPONSE" | jq -r --arg N "$ART_NAME" '.artifacts[] | select(.name==$N) | .id' | head -n 1)

if [ -z "$ART_ID" ] || [ "$ART_ID" = "null" ]; then
  echo "ERROR: Artifact not found: $ART_NAME"
  exit 1
fi
echo "Found artifact ID: $ART_ID"

echo "Downloading artifact..."
curl -fL \
  -H 'Accept: application/vnd.github+json' \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  "https://api.github.com/repos/${REPO}/actions/artifacts/${ART_ID}/zip" \
  -o "$ZIP_PATH"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
unzip -oq "$ZIP_PATH" -d "$STAGE_DIR"
rm -rf "$TARGET_DIR"
mv "$STAGE_DIR" "$TARGET_DIR"
rm -f "$ZIP_PATH"

cp /home/ec2-user/app/ecosystem.config.js "$TARGET_DIR/"
cd "$TARGET_DIR"

pm2 list || true
pm2 delete all || true
pm2 start ecosystem.config.js
pm2 save

HEALTH_URL="http://127.0.0.1:${APP_PORT}${HEALTH_PATH}"
echo "Running health check on $HEALTH_URL"
for i in $(seq 1 12); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" || echo 000)
  echo "Attempt $i: HTTP $code"
  if [ "$code" = "200" ]; then
    break
  fi
  if [ "$i" -eq 12 ]; then
    echo "ERROR: Health check failed"
    exit 1
  fi
  sleep 5
done

echo "===== DEPLOY SUMMARY ====="
echo "Environment: ${ENVIRONMENT:-unknown}"
echo "Build ID:    ${BUILD_ID:-unknown}"
echo "Deploy path: $TARGET_DIR"
pm2 list
echo "===== END SUMMARY ====="
