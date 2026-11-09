#!/usr/bin/env bash
# Publica a versão mais recente na VPS. Ver docs/DEPLOY.md.
#
# As páginas são estáticas: publicar é trazer os arquivos. O formulário tem um
# serviço próprio em lead/, que precisa de dependências e de restart.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> git pull"
git pull --ff-only

# O serviço do formulário só existe depois que .env foi criado na VPS a partir
# de lead/.env.example. Até lá, publicar as páginas continua funcionando: o
# formulário responde 502 e o visitante vê o aviso para usar WhatsApp.
if [ -f lead/.env ]; then
  echo "==> servico de leads"
  ( cd lead && npm ci --omit=dev )
  # A unidade declara ReadWritePaths em lead/data e o systemd monta esse
  # caminho antes de executar. Sem a pasta, o start morre em 226/NAMESPACE.
  mkdir -p lead/data && chmod 700 lead/data
  sudo systemctl restart imobiliario-lead
else
  echo "AVISO: lead/.env nao existe; o formulario fica fora do ar." >&2
  echo "       ver docs/DEPLOY.md, passo 8" >&2
fi

# O bloco da rota /api/lead mora num snippet do nginx. Se o arquivo do
# repositorio mudou, a mudanca sobe junto com as paginas — assim ninguem
# precisa editar a mao o arquivo do site, que o certbot tambem mexe.
SNIPPET=/etc/nginx/snippets/imobiliario-lead.conf
if [ -f "$SNIPPET" ] && ! cmp -s deploy/nginx-lead-location.conf "$SNIPPET"; then
  echo "==> atualizando a rota /api/lead no nginx"
  sudo install -m 644 deploy/nginx-lead-location.conf "$SNIPPET"
  sudo nginx -t
  sudo systemctl reload nginx
fi

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

# Confere que o formulário está de pé sem criar um lead falso: um POST vazio
# tem que ser RECUSADO com 422. Qualquer outra coisa — 502, 404, 200 — quer
# dizer que o caminho não chegou ao serviço ou que a validação não está ativa.
if [ -f lead/.env ]; then
  for tentativa in $(seq 1 10); do
    FORMULARIO="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
      -H 'Content-Type: application/json' -d '{}' \
      --resolve "${DOMINIO}:443:127.0.0.1" "https://${DOMINIO}/api/lead")"
    [ "$FORMULARIO" = "422" ] && break
    sleep 1
  done
  if [ "$FORMULARIO" != "422" ]; then
    echo "ERRO: /api/lead respondeu ${FORMULARIO}, esperado 422" >&2
    echo "      confira: sudo systemctl status imobiliario-lead" >&2
    echo "                sudo journalctl -u imobiliario-lead -n 30" >&2
    exit 1
  fi
  echo "    formulario respondendo"
fi

echo "deploy concluido: ${DOMINIO} respondendo 200"
