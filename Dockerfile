# -----------------------------
# build web (frontend)
# -----------------------------
FROM node:20-alpine3.18 AS web-builder
WORKDIR /web

RUN apk add --no-cache python3 make g++

COPY web/package.json web/pnpm-lock.yaml ./

RUN npm install -g pnpm
RUN pnpm install --frozen-lockfile

COPY web/ .
RUN pnpm run build

# -----------------------------
# build app (backend Go)
# -----------------------------
FROM golang:1.20-alpine3.16 AS app-builder

ARG VERSION=dev
ARG REVISION=dev
ARG BUILDTIME

RUN apk add --no-cache git make build-base tzdata

ENV SERVICE=syncyomi

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . ./

COPY --from=web-builder /web/dist ./web/dist
COPY --from=web-builder /web/build.go ./web

RUN go build -ldflags "-s -w -X main.version=${VERSION} -X main.commit=${REVISION} -X main.date=${BUILDTIME}" -o bin/syncyomi main.go

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

# ✅ config nginx propre via heredoc
RUN mkdir -p /etc/nginx/conf.d \
 && cat > /etc/nginx/conf.d/default.conf <<EOF
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

CMD ["/bin/sh", "-c", "/usr/local/bin/syncyomi --config /config & sleep 1; nginx -g 'daemon off;'"]
