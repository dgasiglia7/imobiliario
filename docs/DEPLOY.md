# Deploy na VPS

Site **estático**: um `index.html` e a pasta `assets/`. O nginx serve os
arquivos direto do disco.

## Porta

**Nenhuma.** O registro de portas de todos os projetos é
[`../../infra/PORTAS.md`](../../infra/PORTAS.md), e lá o `imobiliario` já consta
como site estático que não sobe servidor e não ocupa porta — junto com o
`medijur` e o `prevjur`. Não há `-p`, não há `proxy_pass`, não há systemd.

Isso vale tanto em desenvolvimento quanto em produção. Localmente, abrir o
`index.html` no navegador basta. Se precisar de um servidor local para testar
caminhos absolutos, use a faixa de teste `39xxx` da tabela, nunca a faixa `30xx`
dos projetos Next.

## Antes de começar: escolha o domínio

O site precisa de um nome que **não esteja servindo outra coisa hoje**. Em
outubro de 2026 o estado era:

| Domínio | O que faz hoje |
| --- | --- |
| `gasigliaadvocacia.com` | Serve o site WordPress do escritório (HTTP 200) |
| `gasigliaadvocacia.com.br` | Redireciona 301 para o `.com` |

Apontar o `.com` para a VPS **derruba o site WordPress**. Confirme a escolha
antes de mexer no DNS.

## 1. DNS (no painel da Hostinger)

O DNS dos dois domínios é administrado pela Hostinger (`ns1.dns-parking.com` e
`ns2.dns-parking.com`). Em *hPanel → Domínios → DNS / Nameservers → Gerenciar
registros DNS*.

**Servidor de DNS não se divide por serviço.** Uma única zona atende site e
e-mail ao mesmo tempo: o registro `A` leva o visitante à VPS, os registros `MX`
levam o e-mail à Hostinger. Não é preciso mexer nos servidores de DNS.

Trocar, para apontar o site à VPS:

| Tipo | Nome | Valor | Ação |
| --- | --- | --- | --- |
| `ALIAS` | `@` | `...cdn.hstgr.net` | **apagar** |
| `CNAME` | `www` | `www....cdn.hstgr.net` | **apagar** |
| `A` | `@` | IP da VPS | **criar** |
| `A` | `www` | IP da VPS | **criar** |

O IP sai com `curl -4 ifconfig.me`, rodado na VPS. Se ela tiver IPv6
(`curl -6 ifconfig.me` responde), crie também os dois `AAAA`; se não tiver, não
crie — um `AAAA` errado quebra o site para quem tem IPv6.

Não crie redirecionamento nem "URL forwarding" no painel: quem decide que o
`www` vai para o endereço principal é o nginx, no passo 4. Um redirecionamento
na Hostinger brigaria com ele e com o certificado.

**Não tocar** (é o que mantém o e-mail funcionando):

| Tipo | Nome | Para que serve |
| --- | --- | --- |
| `MX` | `@` | Entrega do e-mail (`mx1` e `mx2.hostinger.com`) |
| `TXT` | `@` | SPF (`v=spf1 include:_spf.mail.hostinger.com ~all`) |
| `TXT` | `_dmarc` | DMARC |
| `CNAME` | `hostingermail-a/b/c._domainkey` | DKIM, assina os e-mails enviados |
| `CNAME` | `autodiscover`, `autoconfig` | Configuração automática no cliente de e-mail |
| `TXT` | `@` | Verificação de domínio do Facebook |

> **Nunca use "Redefinir registros DNS".** Esse botão devolve a zona ao padrão e
> leva junto MX, SPF, DKIM e DMARC. O e-mail para na hora, e o DKIM perdido faz
> as mensagens caírem em spam depois.

O `A ftp` aponta para a hospedagem compartilhada e deixa de ter uso quando o
site sai de lá. Apagar é opcional e não afeta nada.

Os registros do site têm TTL de 300 segundos, então a troca vale em minutos.
Confira com `nslookup DOMINIO` de qualquer máquina: pronto quando responder o IP
da VPS. **Os passos 2 a 4 não dependem do DNS**; o certificado (passo 5) depende.

## 2. Código

```bash
cd /home/dgasiglia
git clone git@github.com:dgasiglia7/imobiliario.git
```

O repositório é público, então não precisa de deploy key.

## 3. Permissão de leitura para o nginx

```bash
chmod o+x /home/dgasiglia
```

O nginx roda como `www-data` e precisa atravessar a pasta do usuário para
alcançar os arquivos. **Sem isso o site responde 403**, e é de longe o erro mais
comum neste desenho. Os projetos Next não passam por isso porque o nginx fala
com eles por `proxy_pass`, não pelo disco.

## 4. nginx

Troque `TROQUE-PELO-DOMINIO` nos dois blocos do arquivo antes de copiar.

```bash
nano /home/dgasiglia/imobiliario/deploy/nginx-imobiliario.conf
sudo cp /home/dgasiglia/imobiliario/deploy/nginx-imobiliario.conf /etc/nginx/sites-available/imobiliario
sudo ln -s /etc/nginx/sites-available/imobiliario /etc/nginx/sites-enabled/
sudo nginx -t          # valida ANTES de recarregar
sudo systemctl reload nginx
curl -sI -H 'Host: DOMINIO' http://127.0.0.1/ | head -1        # esperado: 200
curl -sI -H 'Host: www.DOMINIO' http://127.0.0.1/ | head -1    # esperado: 301
```

> **`nginx -t` antes de qualquer `reload` não é formalidade.** O nginx é o
> recurso que todos os projetos da VPS dividem: uma diretiva inválida neste
> bloco impede o reload e derruba o Ultra Distância e o Backhand junto.

## 5. HTTPS (depois que o DNS propagar)

```bash
sudo certbot --nginx -d DOMINIO -d www.DOMINIO
```

O certbot acrescenta a porta 443, o certificado e o redirecionamento de HTTP aos
mesmos blocos, e renova sozinho. É o mesmo certbot dos outros projetos.

## 6. Publicar atualizações

```bash
cd /home/dgasiglia/imobiliario && ./deploy.sh
```

O script faz `git pull` e confere que o nginx voltou 200. Não há build nem
serviço para reiniciar.

## Pendente depois de escolher o domínio

Três etiquetas no `index.html` ainda apontam para o WordPress e precisam do
endereço final:

| Linha | Etiqueta | Hoje |
| --- | --- | --- |
| 15 | `canonical` | `.../imobiliario/` |
| 23 | `og:url` | `.../imobiliario/` |
| 24, 28, 55 | `og:image`, `twitter:image`, `image` do Schema | logotipo em `/wp-content/` |

A imagem de compartilhamento ganha mais se apontar para
`assets/equipe-gasiglia-advocacia.jpg`: o logotipo tem fundo transparente e
formato alongado, o que rende uma prévia ruim no WhatsApp.

Os links da Política de Privacidade (linhas 990 e 1083) apontam para
`gasigliaadvocacia.com/politica-de-privacidade/`. Se o WordPress sair desse
endereço, eles precisam ser atualizados.
