FROM alpine:3.24

# OS packages stay on the current patched Alpine revision (musl, busybox, nginx, ...).
RUN apk upgrade --no-cache \
    && apk add --no-cache \
    curl \
    bash \
    ca-certificates \
    socat \
    tzdata \
    sqlite \
    nginx \
    gettext \
    && ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime

# دانلود و نصب 3x-ui
# v3.11.0 همراه با xray ای عرضه می‌شود که github.com/klauspost/compress v1.20.0 دارد
# (نسخه‌ی v3.9.0 از v1.17.4 استفاده می‌کرد که GO-2026-5841 دارد).
RUN curl -fsSL https://github.com/mhsanaei/3x-ui/releases/download/v3.11.0/x-ui-linux-amd64.tar.gz -o /tmp/x-ui.tar.gz \
    && tar -xzf /tmp/x-ui.tar.gz -C /usr/local/ \
    && rm /tmp/x-ui.tar.gz \
    && chmod +x /usr/local/x-ui/x-ui

RUN mkdir -p /etc/x-ui /var/log/x-ui

COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY start.sh /start.sh
RUN chmod +x /start.sh

# nginx روی همین پورت (پورت سرویس) گوش می‌دهد
EXPOSE 3000

# Railway پورت رو از طریق متغیر $PORT تزریق می‌کند
CMD ["/start.sh"]
