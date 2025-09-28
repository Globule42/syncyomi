# -----------------------------
# build web (frontend)
# -----------------------------
FROM node:20-alpine3.18 AS web-builder
WORKDIR /web

# outils nécessaires pour compiler certaines dépendances Node
RUN apk add --no-cache python3 make g++

# copier les fichiers de dépendances
COPY web/package.json web/pnpm-lock.yaml ./

# installer pnpm et dépendances
RUN npm install -g pnpm
RUN pnpm install --frozen-lockfile

# copier le reste du code
COPY web/ .

# build du frontend
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

# copier le frontend déjà buildé
COPY --from=web-builder /web/dist ./web/dist
COPY --from=web-builder /web/build.go ./web

# build binaire Go
RUN go build -ldflags "-s -w -X main.version=${VERSION} -X main.commit=${REVISION} -X main.date=${BUILDTIME}" -o bin/syncyomi main.go

# -----------------------------
# final image with Nginx
# -----------------------------
FROM alpine:latest

LABEL org.opencontainers.image.source="https://github.com/SyncYomi/SyncYomi"

ENV HOME="/config" \
    XDG_CONFIG_HOME="/config" \
    XDG_DATA_HOME="/config"

# installer dépendances + nginx
RUN apk add --no-cache ca-certificates curl tzdata jq nginx bash

WORKDIR /app

VOLUME /config

# copier le binaire Go
COPY --from=app-builder /src/bin/syncyomi /usr/local/bin/

# config nginx : reverse proxy vers syncyomi
RUN mkdir -p /etc/nginx/conf.d
RUN echo 'server { \
    listen 8282; \
    location / { \
        proxy_pass http://127.0.0.1:8282; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 8282

# lancer syncyomi en background puis nginx en foreground
CMD ["/bin/sh", "-c", "/usr/local/bin/syncyomi --config /config & nginx -g 'daemon off;'"]
