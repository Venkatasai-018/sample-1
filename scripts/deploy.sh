#!/bin/bash
# /home/appuser/app/scripts/deploy.sh
# Runs ON the EC2 instance, triggered by GitHub Actions via SSM.
# Idempotent — safe to run repeatedly on every deploy.
#
# Args: $1=GIT_BRANCH  $2=APP_PORT  $3=HEALTH_PATH

set -euo pipefail

GIT_BRANCH="${1:-main}"
APP_PORT="${2:-3001}"
HEALTH_PATH="${3:-/health}"
APP_DIR="/home/appuser/app"

# Log everything (visible in SSM output + CloudWatch)
exec > >(tee -a /home/appuser/deploy.log) 2>&1

echo "=========================================="
echo "  Deploy started at $(date -u)"
echo "  Branch: $GIT_BRANCH | Port: $APP_PORT"
echo "=========================================="

source /opt/nvm/nvm.sh

cd "$APP_DIR"

# ----------------------------------------------
# 1. Fetch latest code
# ----------------------------------------------
echo "--- Pulling latest code ---"
git fetch --all --prune
git reset --hard "origin/${GIT_BRANCH}"
git checkout "${GIT_BRANCH}"
COMMIT=$(git rev-parse --short HEAD)
echo "Now on commit: $COMMIT"

# ----------------------------------------------
# 2. Refresh .env from Secrets Manager
# ----------------------------------------------
# Adjust ENV_FILE based on which file your app loads
ENVIRONMENT="${ENVIRONMENT:-dev}"
ENV_SECRET_ARN="${ENV_SECRET_ARN:-}"

if [[ -n "$ENV_SECRET_ARN" ]]; then
  echo "--- Refreshing .env from Secrets Manager ---"
  case "$ENVIRONMENT" in
    dev)  ENV_FILE="$APP_DIR/.env.dev" ;;
    qa)   ENV_FILE="$APP_DIR/.env.qa" ;;
    prod) ENV_FILE="$APP_DIR/.env.production" ;;
  esac
  
  aws secretsmanager get-secret-value \
    --secret-id "$ENV_SECRET_ARN" \
    --region "${AWS_REGION:-us-east-1}" \
    --query 'SecretString' --output text \
    | jq -r 'to_entries[] | "\(.key)=\(.value)"' > "$ENV_FILE"
  
  chmod 600 "$ENV_FILE"
fi

# ----------------------------------------------
# 3. Install dependencies & build
# ----------------------------------------------
echo "--- Installing dependencies ---"
npm ci

echo "--- Building app ---"
npm run build

# ----------------------------------------------
# 4. Zero-downtime reload via PM2
# ----------------------------------------------
echo "--- Reloading app via PM2 ---"
# 'reload' = zero-downtime (vs 'restart' which has brief downtime)
pm2 reload ecosystem.config.js --update-env || pm2 start ecosystem.config.js
pm2 save

# ----------------------------------------------
# 5. Local health check
# ----------------------------------------------
echo "--- Health check ---"
sleep 5
for i in {1..12}; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${APP_PORT}${HEALTH_PATH}" || echo "000")
  echo "Attempt $i: HTTP $HTTP_CODE"
  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "Health check passed"
    break
  fi
  if [[ $i -eq 12 ]]; then
    echo "ERROR: Health check failed after 12 attempts"
    pm2 logs --lines 50 --nostream
    exit 1
  fi
  sleep 5
done

echo "=========================================="
echo "  Deploy completed at $(date -u)"
echo "  Commit: $COMMIT"
echo "=========================================="
