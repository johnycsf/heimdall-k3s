#!/usr/bin/env bash
set -euo pipefail

APP=/var/www/html
DATA=/config

mkdir -p "$DATA/storage" "$DATA/bootstrap-cache"

if [[ ! -f "$DATA/.initialized" ]]; then
  cp -a "$APP/storage/." "$DATA/storage/"
  touch "$DATA/.initialized"
fi

# Persist Laravel writable dirs on the volume
rm -rf "$APP/storage"
ln -sfn "$DATA/storage" "$APP/storage"
rm -rf "$APP/bootstrap/cache"
ln -sfn "$DATA/bootstrap-cache" "$APP/bootstrap/cache"

if [[ ! -f "$DATA/.env" ]]; then
  cp "$APP/.env.example" "$DATA/.env"
  sed -i "s|^APP_ENV=.*|APP_ENV=production|" "$DATA/.env"
  sed -i "s|^APP_DEBUG=.*|APP_DEBUG=false|" "$DATA/.env"
  sed -i "s|^APP_URL=.*|APP_URL=${APP_URL:-http://localhost}|" "$DATA/.env"
  sed -i "s|^DB_DATABASE=.*|DB_DATABASE=/config/app.sqlite|" "$DATA/.env"
  if grep -q '^ALLOW_INTERNAL_REQUESTS=' "$DATA/.env"; then
    sed -i "s|^ALLOW_INTERNAL_REQUESTS=.*|ALLOW_INTERNAL_REQUESTS=${ALLOW_INTERNAL_REQUESTS:-true}|" "$DATA/.env"
  else
    echo "ALLOW_INTERNAL_REQUESTS=${ALLOW_INTERNAL_REQUESTS:-true}" >>"$DATA/.env"
  fi
fi

# Keep runtime toggles in sync with container env
if [[ -n "${ALLOW_INTERNAL_REQUESTS:-}" ]]; then
  if grep -q '^ALLOW_INTERNAL_REQUESTS=' "$DATA/.env"; then
    sed -i "s|^ALLOW_INTERNAL_REQUESTS=.*|ALLOW_INTERNAL_REQUESTS=${ALLOW_INTERNAL_REQUESTS}|" "$DATA/.env"
  else
    echo "ALLOW_INTERNAL_REQUESTS=${ALLOW_INTERNAL_REQUESTS}" >>"$DATA/.env"
  fi
fi
if [[ -n "${APP_URL:-}" ]]; then
  sed -i "s|^APP_URL=.*|APP_URL=${APP_URL}|" "$DATA/.env"
fi

ln -sfn "$DATA/.env" "$APP/.env"
touch "$DATA/app.sqlite"

chown -R www-data:www-data "$DATA"
chown -h www-data:www-data "$APP/storage" "$APP/bootstrap/cache" "$APP/.env" || true

cd "$APP"
as_www() { runuser -u www-data -- "$@"; }

if ! grep -q '^APP_KEY=base64:' "$DATA/.env"; then
  as_www php artisan key:generate --force
fi
as_www php artisan migrate --force

exec "$@"
