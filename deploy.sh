#!/usr/bin/env bash
# Publica a versão mais recente na VPS. Ver docs/DEPLOY.md.
#
# Site estático: publicar é só trazer os arquivos. Não há build, não há
# serviço para reiniciar e não há porta para conferir.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> git pull"
git pull --ff-only

echo "==> conferindo que o nginx serve a versão nova"
DOMINIO="$(grep -m1 -oP 'server_name \K[^;]+' deploy/nginx-imobiliario.conf)"
CODIGO="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${DOMINIO}" http://127.0.0.1/)"
if [ "$CODIGO" != "200" ]; then
  echo "ERRO: http://${DOMINIO}/ respondeu ${CODIGO}, esperado 200" >&2
  echo "      confira: sudo nginx -t && sudo systemctl reload nginx" >&2
  exit 1
fi

echo "deploy concluido: ${DOMINIO} respondendo 200"
