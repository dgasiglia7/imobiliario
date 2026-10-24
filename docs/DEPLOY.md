# Deploy na VPS

Site **estático**: um `index.html` e a pasta `assets/`. O nginx serve os
arquivos direto do disco.

Endereço de produção: **`https://gasigliaadvocacia.com.br`**.

## Os dois domínios do escritório

| Domínio | Papel |
| --- | --- |
| `gasigliaadvocacia.com` | Site institucional WordPress, na Hostinger. **Não se mexe nele.** |
| `gasigliaadvocacia.com.br` | Esta landing page, na VPS. Hoje só redireciona para o `.com`. |

O `.com.br` é registrado no Registro.br, mas o **DNS dele é administrado pela
Hostinger** (`byte.dns-parking.com` e `pixel.dns-parking.com`). Por isso todos os
registros se editam no painel da Hostinger, em *hPanel → Domínios →
gasigliaadvocacia.com.br → DNS / Nameservers*. **No Registro.br não se mexe em
nada.**

## Porta

**Nenhuma.** O registro de portas de todos os projetos é
[`../../infra/PORTAS.md`](../../infra/PORTAS.md), e lá o `imobiliario` já consta
como site estático que não sobe servidor e não ocupa porta — junto com o
`medijur` e o `prevjur`. Não há `-p`, não há `proxy_pass`, não há systemd.

Isso vale em desenvolvimento e em produção. Localmente, abrir o `index.html` no
navegador basta. Se precisar de um servidor local, use a faixa de teste `39xxx`
da tabela, nunca a faixa `30xx` dos projetos Next.

## 1. DNS (no painel da Hostinger)

**Servidor de DNS não se divide por serviço.** Uma zona só atende site e e-mail
ao mesmo tempo: o registro `A` leva o visitante à VPS e os `MX` levam o e-mail à
Hostinger. Não é preciso trocar os servidores de DNS.

O IP sai com `curl -4 ifconfig.me`, rodado na VPS.

### Alterar

| Tipo | Nome | Hoje | Passa a ser |
| --- | --- | --- | --- |
| `A` | `@` | `89.117.7.39` (hospedagem compartilhada) | IP v4 da VPS |
| `AAAA` | `@` | `2a02:4780:13:983:0:382c:4065:2` (Hostinger) | IPv6 da VPS, **ou apagar** |

**O `AAAA` é a pegadinha deste caso.** Se ele continuar apontando para a
Hostinger, quem tem IPv6 — a maioria das operadoras móveis — continua caindo no
redirecionamento antigo, enquanto quem tem só IPv4 vê o site novo. O sintoma é
"o site abre no computador e não no celular", e some e volta sem explicação.

Rode `curl -6 ifconfig.me` na VPS:

- **respondeu um endereço** → edite o `AAAA` para esse valor;
- **falhou** → **apague o registro `AAAA`**. A VPS não tem IPv6, e um `AAAA`
  errado quebra o site para quem tem.

### Manter como está

| Tipo | Nome | Para que serve |
| --- | --- | --- |
| `CNAME` | `www` | Aponta para `gasigliaadvocacia.com.br`, então **segue o `A` sozinho** e chega à VPS. Quem redireciona o `www` para o endereço principal é o nginx, no passo 4. |
| `MX` | `@` | Entrega do e-mail (`mx1` prioridade 5, `mx2` prioridade 10) |
| `TXT` | `@` | SPF (`v=spf1 include:_spf.mail.hostinger.com ~all`) |
| `TXT` | `_dmarc` | DMARC |
| `CNAME` | `hostingermail-a/b/c._domainkey` | DKIM, assina os e-mails enviados |
| `CNAME` | `autodiscover`, `autoconfig` | Configuração automática no cliente de e-mail |

> **Nunca use "Redefinir registros DNS".** Esse botão devolve a zona ao padrão e
> leva junto MX, SPF, DKIM e DMARC. O e-mail para na hora, e o DKIM perdido faz
> as mensagens caírem em spam depois. Antes de qualquer edição, use **Exportar**
> no topo da tela e guarde o arquivo.

### Onde mora o redirecionamento

O 301 de `.com.br` para `.com` **não está no DNS**: ele é servido pela
hospedagem no `89.117.7.39`. Assim que o `A` apontar para a VPS, aquele servidor
sai do caminho e o redirecionamento deixa de acontecer sozinho.

Ainda assim, vale remover o `.com.br` da lista de domínios/redirecionamentos do
plano de hospedagem (*hPanel → Sites*), para a Hostinger não recriar registros
nem avisar que o domínio está apontado para fora.

### Propagação

O `A` tem TTL de 1800 segundos, então a troca leva até meia hora. Confira de
qualquer máquina:

```bash
nslookup gasigliaadvocacia.com.br        # tem de responder o IP da VPS
nslookup www.gasigliaadvocacia.com.br    # idem
nslookup -type=MX gasigliaadvocacia.com.br   # tem de continuar mx1/mx2.hostinger.com
```

**Os passos 2 a 4 não dependem do DNS**; o certificado (passo 5) depende.

## 2. Código

```bash
cd /home/dgasiglia
git clone git@github.com:dgasiglia7/imobiliario.git
```

O repositório é público: não precisa de deploy key.

## 3. Permissão de leitura para o nginx

```bash
chmod o+x /home/dgasiglia
```

O nginx roda como `www-data` e precisa atravessar a pasta do usuário para
alcançar os arquivos. **Sem isso o site responde 403**, e é de longe o erro mais
comum neste desenho. Os projetos Next não passam por isso porque o nginx fala
com eles por `proxy_pass`, não pelo disco.

## 4. nginx

```bash
sudo cp /home/dgasiglia/imobiliario/deploy/nginx-imobiliario.conf /etc/nginx/sites-available/imobiliario
sudo ln -s /etc/nginx/sites-available/imobiliario /etc/nginx/sites-enabled/
sudo nginx -t          # valida ANTES de recarregar
sudo systemctl reload nginx
curl -sI -H 'Host: gasigliaadvocacia.com.br' http://127.0.0.1/ | head -1        # esperado: 200
curl -sI -H 'Host: www.gasigliaadvocacia.com.br' http://127.0.0.1/ | head -1    # esperado: 301
```

> **`nginx -t` antes de qualquer `reload` não é formalidade.** O nginx é o
> recurso que todos os projetos da VPS dividem: uma diretiva inválida neste
> bloco impede o reload e derruba o Ultra Distância e o Backhand junto.

## 5. HTTPS (depois que o DNS propagar)

```bash
sudo certbot --nginx -d gasigliaadvocacia.com.br -d www.gasigliaadvocacia.com.br
```

O certbot acrescenta a porta 443, o certificado e o redirecionamento de HTTP aos
mesmos blocos, e renova sozinho. É o mesmo certbot dos outros projetos.

## 6. Publicar atualizações

```bash
cd /home/dgasiglia/imobiliario && ./deploy.sh
```

O script faz `git pull` e confere que o nginx voltou 200. Não há build nem
serviço para reiniciar.

## Conferência depois de publicar

- `https://gasigliaadvocacia.com.br` abre a landing page, com cadeado.
- `http://www.gasigliaadvocacia.com.br` termina em `https://gasigliaadvocacia.com.br`.
- `https://gasigliaadvocacia.com` continua abrindo o WordPress, intocado.
- Enviar e receber um e-mail em `@gasigliaadvocacia.com.br`.
- Colar o link no WhatsApp: a prévia mostra a foto da equipe.

## O que a página ainda busca de fora

Só as miniaturas dos vídeos, em `i.ytimg.com`, que é o CDN do YouTube e não
depende de nenhum domínio do escritório. Logotipo e fotos estão em `assets/`,
servidos pela própria VPS.

Os links da Política de Privacidade apontam para
`gasigliaadvocacia.com/politica-de-privacidade/`, que continua no WordPress.
