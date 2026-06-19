#!/bin/sh
set -e

if [ -z "${DATABASE_URL:-}" ]; then
  if [ -n "${DB_PASSWORD:-}" ] && [ -n "${DB_HOST:-}" ]; then
    DB_PASSWORD_ENCODED=$(node -e "console.log(encodeURIComponent(process.env.DB_PASSWORD))")
    DATABASE_URL="postgresql://${DB_USERNAME:-postgres}:${DB_PASSWORD_ENCODED}@${DB_HOST}:${DB_PORT:-5432}/${DB_NAME:-postgres}"
    export DATABASE_URL
    echo "[entrypoint] DATABASE_URL constructed from DB_* variables"
  else
    echo "[entrypoint] ERROR: DATABASE_URL is not set and DB_HOST/DB_PASSWORD are missing"
    exit 1
  fi
fi

# Parse host and port from DATABASE_URL
# e.g. postgresql://user:pass@hostname:5432/dbname
DB_HOST=$(echo "$DATABASE_URL" | sed -E 's|.*@([^:/]+)[:/].*|\1|')
DB_PORT=$(echo "$DATABASE_URL" | sed -E 's|.*:([0-9]+)/.*|\1|')
DB_PORT="${DB_PORT:-5432}"

MAX_RETRIES=30
RETRY_INTERVAL=2
attempt=0

echo "[entrypoint] Waiting for database at ${DB_HOST}:${DB_PORT} ..."
until nc -z "$DB_HOST" "$DB_PORT" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge "$MAX_RETRIES" ]; then
    echo "[entrypoint] ERROR: database not ready after $((MAX_RETRIES * RETRY_INTERVAL))s"
    exit 1
  fi
  echo "[entrypoint] Retrying... (${attempt}/${MAX_RETRIES})"
  sleep "$RETRY_INTERVAL"
done

echo "[entrypoint] Applying migrations..."
npx prisma migrate deploy

echo "[entrypoint] Starting server..."
exec node dist/server.js