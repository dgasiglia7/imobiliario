#!/usr/bin/env bash
# Liga a rota /api/lead no nginx. Ver docs/DEPLOY.md, passo 8.4.
#
# Roda quantas vezes quiser: se o `include` já estiver no lugar, só atualiza os
# arquivos e recarrega. O arquivo do site é tocado uma vez só, para acrescentar
# uma linha — o resto mora em /etc/nginx/snippets, longe do certbot.
#
# Se o `nginx -t` reprovar, o arquivo do site volta ao que era antes e nada é
# recarregado: um site fora do ar é pior do que um formulário fora do ar.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

AQUI="$(cd "$(dirname "$0")" && pwd)"
SITE=/etc/nginx/sites-available/imobiliario
SNIPPET=/etc/nginx/snippets/imobiliario-lead.conf
ZONA=/etc/nginx/conf.d/imobiliario-lead-ratelimit.conf
DOMINIO=gasigliaadvocacia.com.br
LINHA="    include ${SNIPPET};"

[ -f "$SITE" ] || { echo "ERRO: $SITE nao existe; ver docs/DEPLOY.md, passo 4." >&2; exit 1; }

echo "==> arquivos do nginx"
install -D -m 644 "${AQUI}/nginx-lead-ratelimit.conf" "$ZONA"
install -D -m 644 "${AQUI}/nginx-lead-location.conf" "$SNIPPET"

if grep -qF "$SNIPPET" "$SITE"; then
  echo "    o include ja estava no bloco do site"
else
  echo "==> acrescentando o include ao bloco do site"

  # Acha o `server { … }` que escuta na 443 E atende o domínio sem www, e
  # insere a linha logo depois da chave de abertura. Conta chaves ignorando o
  # que vem depois de `#`, senão um `{` dentro de comentário desalinharia tudo.
  awk -v linha="$LINHA" -v dominio="$DOMINIO" '
    function chaves(s,   t) { t = s; sub(/#.*/, "", t); return t }
    function conta(s, c,   n, i) {
      n = 0
      for (i = 1; i <= length(s); i++) if (substr(s, i, 1) == c) n++
      return n
    }
    FNR == NR {
      codigo = chaves($0)
      if (prof == 0 && codigo ~ /server[[:space:]]*\{/) {
        inicio = FNR; tem443 = 0; temnome = 0
      }
      if (prof > 0 || inicio == FNR) {
        if (codigo ~ /listen[^;]*443/) tem443 = 1
        if (codigo ~ ("server_name[[:space:]]+" dominio "[[:space:]]*;")) temnome = 1
      }
      prof += conta(codigo, "{") - conta(codigo, "}")
      if (prof == 0 && inicio > 0) {
        if (tem443 && temnome) alvo = inicio
        inicio = 0
      }
      next
    }
    FNR == 1 && alvo == 0 {
      print "ERRO: nao achei o server da porta 443 de " dominio " em " FILENAME > "/dev/stderr"
      saida = 1
      exit 1
    }
    { print }
    FNR == alvo { print linha }
    END { exit saida }
  ' "$SITE" "$SITE" > "${SITE}.novo" || {
    rm -f "${SITE}.novo"
    echo "      insira a linha a mao: $LINHA" >&2
    exit 1
  }

  # So agora o arquivo do site muda: ate aqui nada foi tocado.
  COPIA="${SITE}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$SITE" "$COPIA"
  echo "    copia do anterior em $COPIA"
  cat "${SITE}.novo" > "$SITE"
  rm -f "${SITE}.novo"

  if ! nginx -t; then
    echo "ERRO: nginx -t reprovou; desfazendo." >&2
    cat "$COPIA" > "$SITE"
    exit 1
  fi
fi

nginx -t
systemctl reload nginx
echo "==> nginx recarregado"

# Um POST vazio tem que ser RECUSADO com 422, sem criar lead nenhum. Resolve o
# dominio para a propria maquina: o nginx precisa do nome certo para escolher
# o bloco e o certificado.
CODIGO="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' -d '{}' \
  --resolve "${DOMINIO}:443:127.0.0.1" "https://${DOMINIO}/api/lead")"

if [ "$CODIGO" != "422" ]; then
  echo "ERRO: /api/lead respondeu ${CODIGO}, esperado 422" >&2
  case "$CODIGO" in
    404) echo "      o include caiu no bloco errado; confira $SITE" >&2 ;;
    502) echo "      o nginx achou a rota, mas o servico nao responde:" >&2
         echo "      systemctl status imobiliario-lead --no-pager" >&2 ;;
  esac
  exit 1
fi

echo "pronto: /api/lead respondendo 422 a POST vazio"
