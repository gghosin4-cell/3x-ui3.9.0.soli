#!/usr/bin/env bash
# بررسی صحت nginx.conf.template:
#   1) سینتکس کانفیگ رندرشده
#   2) پاسخ سالم روی مسیر ریشه وقتی هیچ اینباندی روی 8080 نیست
#   3) حفظ پروکسی هر سه مسیر (پنل، ساب، اینباند) وقتی سرویس‌ها بالا هستند
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
PORT="${TEST_PORT:-3999}"
PIDS=()

cleanup() {
    local rc=$?
    trap - EXIT
    # nginx با -g pid راه افتاده، پس همان pid را مستقیم علامت می‌دهیم
    if [ -f "$WORK/nginx.pid" ]; then
        kill -TERM "$(cat "$WORK/nginx.pid")" >/dev/null 2>&1 || true
    fi
    for pid in "${PIDS[@]:-}"; do
        [ -n "$pid" ] && kill -TERM "$pid" >/dev/null 2>&1 || true
    done
    sleep 0.5
    for pid in "${PIDS[@]:-}"; do
        [ -n "$pid" ] && kill -KILL "$pid" >/dev/null 2>&1 || true
    done
    wait >/dev/null 2>&1 || true
    rm -rf "$WORK"
    exit "$rc"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

stub() { # stub <port> <label>
    python3 - "$1" "$2" <<'PY' &
import sys, http.server
port, label = int(sys.argv[1]), sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"STUB-{label} {self.path}".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY
    PIDS+=($!)
}

wait_port() { # wait_port <port>
    for _ in $(seq 1 50); do
        if curl -fsS --max-time 1 "http://127.0.0.1:$1/" >/dev/null 2>&1; then return 0; fi
        sleep 0.2
    done
    return 1
}

mkdir -p "$WORK/logs"
export NGINX_PORT="$PORT"
if command -v envsubst >/dev/null 2>&1; then
    envsubst '${NGINX_PORT}' < "$ROOT/nginx.conf.template" > "$WORK/nginx.conf"
else
    # در ایمیج از gettext/envsubst استفاده می‌شود؛ برای محیط تست محلی sed کافی است
    sed "s|\${NGINX_PORT}|$NGINX_PORT|g" "$ROOT/nginx.conf.template" > "$WORK/nginx.conf"
fi
[ -s "$WORK/nginx.conf" ] || fail "رندر قالب nginx.conf ناموفق بود"

nginx -t -p "$WORK" -c "$WORK/nginx.conf" >/dev/null 2>&1 \
    || { nginx -t -p "$WORK" -c "$WORK/nginx.conf"; fail "سینتکس nginx.conf نامعتبر است"; }
echo "OK: سینتکس کانفیگ معتبر است"

nginx -p "$WORK" -c "$WORK/nginx.conf" -g "pid $WORK/nginx.pid;" \
    || fail "nginx بالا نیامد"
wait_port "$PORT" || fail "nginx روی پورت $PORT گوش نمی‌دهد"

# 1) بدون هیچ سرویسی روی 8080: مسیر ریشه باید سالم بماند
code=$(curl -s -o "$WORK/root.txt" -w '%{http_code}' --max-time 5 "http://127.0.0.1:$PORT/")
[ "$code" = "200" ] || fail "مسیر ریشه بدون اینباند باید 200 بدهد، دریافت شد: $code"
grep -q "x-ui is running" "$WORK/root.txt" || fail "متن پاسخ مسیر ریشه نامناسب است: $(head -c 200 "$WORK/root.txt")"
echo "OK: مسیر ریشه بدون اینباند پاسخ 200 می‌دهد"

# 2) با سرویس‌های زنده: هر سه مسیر باید پروکسی شوند
stub 2053 PANEL
stub 2096 SUB
stub 8080 INBOUND
wait_port 2053 || fail "stub پنل بالا نیامد"
wait_port 2096 || fail "stub ساب بالا نیامد"
wait_port 8080 || fail "stub اینباند بالا نیامد"

check() { # check <path> <expected-body>
    local body
    body=$(curl -fsS --max-time 5 "http://127.0.0.1:$PORT$1") \
        || fail "درخواست $1 ناموفق بود"
    [ "$body" = "$2" ] || fail "برای $1 انتظار «$2» بود، دریافت شد «$body»"
    echo "OK: $1 -> $2"
}

check "/managepanel/"      "STUB-PANEL /managepanel/"
check "/managepanel/x"     "STUB-PANEL /managepanel/x"
check "/sub/abc123"        "STUB-SUB /sub/abc123"
check "/vless-ws"          "STUB-INBOUND /vless-ws"

# 3) حتی وقتی اینباند زنده است، مسیر ریشه باید پاسخ سلامت nginx را بدهد
# (اینباند xray برای مسیرهای ناشناخته 404 خالی می‌دهد و نباید روی ریشه اثر بگذارد)
root_code=$(curl -s -o "$WORK/root2.txt" -w '%{http_code}' --max-time 5 "http://127.0.0.1:$PORT/")
[ "$root_code" = "200" ] || fail "مسیر ریشه با اینباند فعال باید 200 بدهد، دریافت شد: $root_code"
grep -q "x-ui is running" "$WORK/root2.txt" || fail "مسیر ریشه به‌جای پاسخ سلامت، پاسخ اینباند را داد: $(head -c 200 "$WORK/root2.txt")"
echo "OK: مسیر ریشه با اینباند فعال هم پاسخ سلامت می‌دهد"

echo "همه‌ی بررسی‌های nginx با موفقیت گذشتند"
