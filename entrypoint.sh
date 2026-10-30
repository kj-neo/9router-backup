#!/usr/bin/env bash
# Inicia o 9Router e mantém o banco (providers, keys, combos) salvo
# (SQLite em /app/data/db/data.sqlite) em um repositório PRIVADO do GitHub, já que o disco do Render Free é efêmero.
set -uo pipefail

DB="${DATA_DIR:-/app/data}/db/data.sqlite"
SNAP=/tmp/snap.sqlite
API="https://api.github.com/repos/${BACKUP_REPO:-}/contents/${BACKUP_PATH:-data.sqlite}"
AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN:-}" -H "X-GitHub-Api-Version: 2022-11-28")
LAST_HASH=""

backup_enabled() { [[ -n "${GITHUB_TOKEN:-}" && -n "${BACKUP_REPO:-}" ]]; }

restore() {
  backup_enabled || { echo "[persist] backup desativado (defina GITHUB_TOKEN e BACKUP_REPO)"; return; }
  if curl -fsS "${AUTH[@]}" -H "Accept: application/vnd.github.raw" "$API" -o "$DB.tmp"; then
    mv "$DB.tmp" "$DB"; rm -f "$DB-wal" "$DB-shm"
    LAST_HASH=$(md5sum "$DB" | cut -d' ' -f1)
    echo "[persist] banco restaurado"
  else
    rm -f "$DB.tmp"; echo "[persist] nenhum backup encontrado (primeira execução)"
  fi
}

backup() {
  backup_enabled && [[ -f "$DB" ]] || return
  sqlite3 "$DB" ".backup $SNAP" || { echo "[persist] snapshot falhou"; return; }
  local h; h=$(md5sum "$SNAP" | cut -d' ' -f1)
  [[ "$h" == "$LAST_HASH" ]] && return
  local sha; sha=$(curl -fsS "${AUTH[@]}" "$API" 2>/dev/null | jq -r '.sha // empty')
  base64 -w0 "$SNAP" > /tmp/db.b64
  jq -n --rawfile c /tmp/db.b64 --arg s "$sha" --arg m "backup $(date -u +%FT%TZ)" \
     '{message:$m, content:$c} + (if $s != "" then {sha:$s} else {} end)' \
   | curl -fsS -X PUT "${AUTH[@]}" -d @- "$API" >/dev/null \
   && { LAST_HASH="$h"; echo "[persist] backup enviado"; } \
   || echo "[persist] falha no backup"
}

mkdir -p "$(dirname "$DB")"
restore

node custom-server.js --port "${PORT:-10000}" &
APP_PID=$!

shutdown() { echo "[persist] encerrando..."; backup; kill "$APP_PID" 2>/dev/null; wait "$APP_PID"; exit 0; }
trap shutdown SIGTERM SIGINT

( while sleep 300; do backup; done ) &

wait "$APP_PID"
