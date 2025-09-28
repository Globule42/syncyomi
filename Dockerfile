# -----------------------------
# final image with Nginx
# -----------------------------
FROM alpine:latest

LABEL org.opencontainers.image.source="https://github.com/SyncYomi/SyncYomi"

ENV HOME="/config" \
    XDG_CONFIG_HOME="/config" \
    XDG_DATA_HOME="/config"

RUN apk add --no-cache ca-certificates curl tzdata jq nginx bash

WORKDIR /app

VOLUME /config

COPY --from=app-builder /src/bin/syncyomi /usr/local/bin/

# -----------------------------
# config Nginx
# -----------------------------
RUN mkdir -p /etc/nginx

# nginx.conf principal
RUN cat > /etc/nginx/nginx.conf <<EOF
worker_processes auto;
events { worker_connections 1024; }

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile      on;

    include /etc/nginx/conf.d/*.conf;
}
EOF

# site par défaut (reverse proxy)
RUN mkdir -p /etc/nginx/conf.d
RUN cat > /etc/nginx/conf.d/default.conf <<EOF
server {
    listen 8282;

    location / {
        proxy_pass http://127.0.0.1:8282;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

EXPOSE 8282

# lancer syncyomi en arrière-plan puis nginx en foreground
CMD ["/bin/sh", "-c", "/usr/local/bin/syncyomi --config /config & sleep 1; nginx -g 'daemon off;'"]
