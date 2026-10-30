FROM node:20-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl jq sqlite3 ca-certificates python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

# Opcional: tag/commit para fixar a versão. Vazio = branch padrão do repositório.
ARG NINE_ROUTER_REF=

WORKDIR /app
RUN git clone https://github.com/decolua/9router.git . \
 && if [ -n "${NINE_ROUTER_REF}" ]; then git checkout "${NINE_ROUTER_REF}"; fi \
 && npm install \
 && npm install better-sqlite3 \
 && NODE_OPTIONS=--max-old-space-size=4096 npm run build

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /app/data

ENV NODE_ENV=production \
    HOSTNAME=0.0.0.0 \
    DATA_DIR=/app/data

ENTRYPOINT ["/entrypoint.sh"]
