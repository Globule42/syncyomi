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
# final image
# -----------------------------
FROM alpine:latest

LABEL org.opencontainers.image.source="https://github.com/SyncYomi/SyncYomi"

ENV HOME="/config" \
    XDG_CONFIG_HOME="/config" \
    XDG_DATA_HOME="/config"

RUN apk add --no-cache ca-certificates curl tzdata jq

WORKDIR /app

VOLUME /config

COPY --from=app-builder /src/bin/syncyomi /usr/local/bin/

EXPOSE 8282

ENTRYPOINT ["/usr/local/bin/syncyomi", "--config", "/config"]
