#!/bin/bash
set -e

echo "🚀 Starting X-UI + nginx reverse proxy..."

# nginx روی پورت سرویس گوش می‌دهد.
# اگر پلتفرم متغیر PORT را تزریق کند همان استفاده می‌شود، وگرنه 3000 (پورت EXPOSE و پورت تنظیم‌شده‌ی سرویس).
export NGINX_PORT="${PORT:-3000}"

cd /usr/local/x-ui

echo "🔧 Applying panel settings via x-ui CLI..."
./x-ui setting -port 2053 -webBasePath /managepanel/ || true

echo "🔧 Building nginx.conf for fixed port: $NGINX_PORT"
envsubst '${NGINX_PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

echo "▶️  Starting x-ui in background..."
./x-ui &
X_UI_PID=$!

sleep 2

echo "▶️  Starting nginx in foreground on port $NGINX_PORT..."
nginx -t
exec nginx -g "daemon off;"
