#!/bin/bash
# /opt/deploy/release/scripts/setup.sh
# IDEMPOTENT setup script — safe to run every deploy.
# - If pm2/nginx not installed → installs them
# - If already installed → updates config + reloads
# - Always extracts new release and reloads app

set -euo pipefail
exec > >(tee -a /var/log/deploy.log) 2>&1

echo "=========================================="
echo "  Deploy started at $(date -u)"
echo "  Build ID: ${BUILD_ID:-unknown}"
echo "=========================================="

APP_USER="appuser"
APP_DIR="/home/$APP_USER/app"
RELEASE_DIR="/opt/deploy/release"

# ----------------------------------------------
# 1. Ensure app user exists (idempotent)
# ----------------------------------------------
if ! id "$APP_USER" &>/dev/null; then
  echo "[setup] Creating $APP_USER"
  useradd -r -m -d "/home/$APP_USER" -s /bin/bash "$APP_USER"
else
  echo "[setup] $APP_USER already exists, skipping"
fi

mkdir -p "$APP_DIR"

# ----------------------------------------------
# 2. Ensure Node.js + nvm installed
# ----------------------------------------------
export NVM_DIR="/opt/nvm"
if ! command -v node &>/dev/null; then
  echo "[setup] Installing Node.js via nvm"
  mkdir -p "$NVM_DIR"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | NVM_DIR="$NVM_DIR" PROFILE=/dev/null bash
  source "$NVM_DIR/nvm.sh"
  nvm install 20
  nvm alias default 20
  ln -sf "$NVM_DIR/versions/node/$(nvm version default)/bin/node" /usr/local/bin/node
  ln -sf "$NVM_DIR/versions/node/$(nvm version default)/bin/npm"  /usr/local/bin/npm
else
  echo "[setup] Node.js already installed: $(node --version)"
  source "$NVM_DIR/nvm.sh" || true
fi

# ----------------------------------------------
# 3. Ensure PM2 installed
# ----------------------------------------------
if ! command -v pm2 &>/dev/null; then
  echo "[setup] Installing PM2"
  npm install -g pm2
  ln -sf "$(npm root -g)/pm2/bin/pm2" /usr/local/bin/pm2
else
  echo "[setup] PM2 already installed: $(pm2 --version)"
fi

# ----------------------------------------------
# 4. Refresh .env from Secrets Manager
# ----------------------------------------------
if [[ -n "${ENV_SECRET_ARN:-}" ]]; then
  echo "[setup] Refreshing .env from Secrets Manager"
  case "$ENVIRONMENT" in
    dev)  ENV_FILE="$APP_DIR/.env.dev" ;;
    qa)   ENV_FILE="$APP_DIR/.env.qa" ;;
    prod) ENV_FILE="$APP_DIR/.env.production" ;;
    *)    ENV_FILE="$APP_DIR/.env" ;;
  esac
  
  aws secretsmanager get-secret-value \
    --secret-id "$ENV_SECRET_ARN" \
    --region "$AWS_REGION" \
    --query 'SecretString' --output text \
    | jq -r 'to_entries[] | "\(.key)=\(.value)"' > "$ENV_FILE"
  
  chown "$APP_USER:$APP_USER" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

# ----------------------------------------------
# 5. Deploy release files (zero-downtime swap)
# ----------------------------------------------
echo "[setup] Syncing release files"
# Use rsync to preserve permissions and only update changed files
rsync -a --delete \
  --exclude='.env*' \
  --exclude='node_modules' \
  "$RELEASE_DIR/" "$APP_DIR/"

# Install prod dependencies on the server
cd "$APP_DIR"
sudo -u "$APP_USER" bash -c "source $NVM_DIR/nvm.sh && cd $APP_DIR && npm ci --omit=dev"

chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# ----------------------------------------------
# 6. PM2 ecosystem (write/refresh config)
# ----------------------------------------------
cat > "$APP_DIR/ecosystem.config.js" <<PMEOF
module.exports = {
  apps: [{
    name: "app",
    script: "dist/index.js",
    cwd: "$APP_DIR",
    instances: 1,
    autorestart: true,
    max_restarts: 10,
    min_uptime: "10s",
    max_memory_restart: "512M",
    env: {
      NODE_ENV: "$ENVIRONMENT",
      PORT: "$APP_PORT"
    }
  }]
};
PMEOF
chown "$APP_USER:$APP_USER" "$APP_DIR/ecosystem.config.js"

# ----------------------------------------------
# 7. Reload PM2 (zero-downtime)
# ----------------------------------------------
echo "[setup] Reloading PM2 app"
sudo -u "$APP_USER" bash -c "source $NVM_DIR/nvm.sh && cd $APP_DIR && pm2 reload ecosystem.config.js --update-env || pm2 start ecosystem.config.js"
sudo -u "$APP_USER" bash -c "source $NVM_DIR/nvm.sh && pm2 save"

# Ensure PM2 starts on reboot (only sets up once)
if ! systemctl list-unit-files | grep -q "pm2-$APP_USER.service"; then
  echo "[setup] Configuring PM2 systemd startup"
  env PATH=$PATH:/usr/local/bin pm2 startup systemd -u "$APP_USER" --hp "/home/$APP_USER"
fi

# ----------------------------------------------
# 8. Ensure nginx installed + configured (idempotent)
# ----------------------------------------------
if ! command -v nginx &>/dev/null; then
  echo "[setup] Installing nginx"
  dnf install -y nginx
fi

# Always re-write config (handles upstream port changes, etc.)
echo "[setup] Writing nginx config"
SERVER_NAME="${DOMAIN:-_}"
cat > /etc/nginx/conf.d/app.conf <<NGEOF
server {
    listen 80;
    server_name $SERVER_NAME;
    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGEOF

# Remove default nginx server block (only once)
rm -f /etc/nginx/conf.d/default.conf
sed -i '/^    server {/,/^    }/d' /etc/nginx/nginx.conf 2>/dev/null || true

# Validate & reload (no downtime)
nginx -t
if ! systemctl is-active --quiet nginx; then
  systemctl enable nginx
  systemctl start nginx
else
  systemctl reload nginx
fi

# ----------------------------------------------
# 9. SSL via Let's Encrypt (dev/qa only, idempotent)
# ----------------------------------------------
if [[ "$ENVIRONMENT" != "prod" && -n "${DOMAIN:-}" ]]; then
  if ! command -v certbot &>/dev/null; then
    echo "[setup] Installing certbot"
    dnf install -y certbot python3-certbot-nginx
  fi
  
  # Only obtain cert if not already present
  if [[ ! -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
    echo "[setup] Obtaining SSL cert for $DOMAIN"
    certbot --nginx -d "$DOMAIN" \
      --non-interactive --agree-tos \
      -m admin@$(echo $DOMAIN | sed 's/^[^.]*\.//') \
      --redirect
  else
    echo "[setup] SSL cert already exists for $DOMAIN"
  fi
fi

# ----------------------------------------------
# 10. Local health check
# ----------------------------------------------
echo "[setup] Local health check"
sleep 3
for i in {1..12}; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$APP_PORT$HEALTH_PATH" || echo "000")
  echo "  attempt $i: HTTP $CODE"
  [[ "$CODE" == "200" ]] && break
  [[ $i -eq 12 ]] && { echo "ERROR: Health check failed"; pm2 logs --lines 30 --nostream; exit 1; }
  sleep 5
done

echo "=========================================="
echo "  Deploy completed at $(date -u)"
echo "=========================================="
