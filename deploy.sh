#!/usr/bin/env bash
# Publica a versão mais recente na VPS. Ver docs/DEPLOY.md.
#
# Site estático: publicar é só trazer os arquivos. Não há build, não há
# serviço para reiniciar e não há porta para conferir.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> git pull"
git pull --ff-only

DOMINIO="$(grep -m1 -oP 'server_name \K[^;]+' deploy/nginx-imobiliario.conf)"

# Confere pelo HTTPS, resolvendo o domínio para a própria máquina: o nginx
# precisa do nome certo para escolher o bloco e o certificado. Pelo HTTP a
# resposta seria 301, porque o certbot redireciona tudo para o HTTPS.
echo "==> conferindo ${DOMINIO}"
CODIGO="$(curl -s -o /dev/null -w '%{http_code}' \
  --resolve "${DOMINIO}:443:127.0.0.1" "https://${DOMINIO}/")"
if [ "$CODIGO" != "200" ]; then
  echo "ERRO: https://${DOMINIO}/ respondeu ${CODIGO}, esperado 200" >&2
  echo "      confira: sudo nginx -t && sudo systemctl reload nginx" >&2
  exit 1
fi

# O rastreador do Umami vem de um include do repositório infra. Se faltar, o
# site continua no ar — por isso avisa, mas não falha o deploy.
RASTREADOR="$(curl -s -o /dev/null -w '%{http_code}' \
  --resolve "${DOMINIO}:443:127.0.0.1" "https://${DOMINIO}/stats/script.js")"
if [ "$RASTREADOR" != "200" ]; then
  echo "AVISO: /stats/script.js respondeu ${RASTREADOR}; a medição está fora." >&2
  echo "       ver docs/DEPLOY.md, passo 7.3" >&2
fi

echo "deploy concluido: ${DOMINIO} respondendo 200"
