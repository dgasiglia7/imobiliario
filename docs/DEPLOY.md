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

**3006**, só para o formulário. O registro de portas de todos os projetos é
[`../../infra/PORTAS.md`](../../infra/PORTAS.md), e a linha está reservada lá.

As páginas continuam estáticas: o nginx as serve direto do disco, sem passar
por processo nenhum. A única exceção é `/api/lead`, que vai para o serviço em
`lead/` — ver o passo 8.

Localmente, abrir o `index.html` no navegador basta para mexer no visual. Se
precisar de um servidor local, use a faixa de teste `39xxx` da tabela, nunca a
faixa `30xx` dos projetos Next.

## 1. DNS (no painel da Hostinger)

**Servidor de DNS não se divide por serviço.** Uma zona só atende site e e-mail
ao mesmo tempo: o registro `A` leva o visitante à VPS e os `MX` levam o e-mail à
Hostinger. Não é preciso trocar os servidores de DNS.

### O IP da VPS

A VPS (`srv1924518`) atende pelos dois protocolos:

| | Endereço | Vai no registro |
| --- | --- | --- |
| IPv4 | `2.25.116.130` | `A` |
| IPv6 | `2a02:4780:95:faa9::1` | `AAAA` |

Os dois saíram de `curl -4 ifconfig.me` e `curl -6 ifconfig.me` rodados na VPS.
O IPv4 foi conferido de fora: responde com `nginx/1.24.0 (Ubuntu)` e já atende
`ultradistancia.com.br` e `backhand.com.br`, os dois projetos que moram lá.

```bash
curl -sI -H "Host: ultradistancia.com.br" http://2.25.116.130/   # 301 para https
```

O nginx já escuta nos dois protocolos: os blocos de
[`deploy/nginx-imobiliario.conf`](../deploy/nginx-imobiliario.conf) trazem
`listen 80` e `listen [::]:80`.

Se a VPS for trocada ou recriada, os dois endereços mudam: rode os dois comandos
nela de novo e atualize esta tabela junto com os registros.

### Alterar

| Tipo | Nome | Hoje | Passa a ser |
| --- | --- | --- | --- |
| `A` | `@` | `89.117.7.39` (hospedagem compartilhada) | **`2.25.116.130`** |
| `AAAA` | `@` | `2a02:4780:13:983:0:382c:4065:2` (Hostinger) | **`2a02:4780:95:faa9::1`** |

**O `AAAA` é a pegadinha deste caso, e muda junto com o `A`.** Se ele
continuar apontando para a Hostinger, quem tem IPv6 — a maioria das operadoras
móveis — continua caindo no redirecionamento antigo, enquanto quem tem só IPv4
vê o site novo. O sintoma é "o site abre no computador e não no celular", e some
e volta sem explicação.

Os dois endereços IPv6 estão no mesmo bloco `2a02:4780::/32`, porque a VPS também
é da Hostinger. Confira dígito por dígito ao colar: a mudança inteira é trocar
`13:983:0:382c:4065:2` por `95:faa9::1`.

> **O `AAAA` também decide o certificado.** O Let's Encrypt prefere IPv6 quando
> existe um `AAAA`. Se ele ainda apontar para a Hostinger no passo 5, a
> validação bate lá e o `certbot` falha, mesmo com o `A` já correto.

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
nslookup -type=A gasigliaadvocacia.com.br         # 2.25.116.130
nslookup -type=AAAA gasigliaadvocacia.com.br      # 2a02:4780:95:faa9::1
nslookup -type=A www.gasigliaadvocacia.com.br     # 2.25.116.130
nslookup -type=MX gasigliaadvocacia.com.br        # mx1 e mx2.hostinger.com, inalterados
```

Antes da mudança, os dois primeiros respondem `89.117.7.39` e
`2a02:4780:13:983:0:382c:4065:2`. Se o `AAAA` continuar nesse valor depois de
salvar, a edição dele não pegou — volte ao painel antes de seguir para o passo 5.

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

O script faz `git pull`, confere pelo HTTPS que o nginx voltou 200 e avisa se o
rastreador do Umami parou de responder, sem falhar por isso.

Se `lead/.env` existir, ele também instala as dependências do serviço de leads,
reinicia o `imobiliario-lead` e confere o formulário — um POST vazio em
`/api/lead` tem que voltar `422`. Qualquer outra resposta falha o deploy, porque
um formulário quebrado perde cliente em silêncio.

Se o `./deploy.sh` responder `Permission denied`, o bit de execução não chegou
na VPS. Traga de novo e rode:

```bash
cd /home/dgasiglia/imobiliario && git pull && chmod +x deploy.sh && ./deploy.sh
```


## 7. Medição (Umami)

O site é medido pelo **mesmo painel do Ultra Distância**,
`https://stats.ultradistancia.com.br`. Não sobe contêiner novo e não se aloca
porta: um painel atende quantos sites você quiser, cada um com seu `Website ID`.

O rastreador é servido **pelo próprio domínio**, em
`https://gasigliaadvocacia.com.br/stats/script.js`, e não pelo subdomínio do
painel. É isso que mantém a medição em primeira parte, fora do alcance dos
bloqueadores. O desenho e o porquê estão em
[`../../infra/UMAMI.md`](../../infra/UMAMI.md).

O Umami não usa cookies nem coleta dado pessoal, o que evita a exigência de
banner de consentimento.

### 7.1 Criar o site no painel

Em `https://stats.ultradistancia.com.br` → *Settings* → *Websites* →
*Add website*:

| Campo | Valor |
| --- | --- |
| Name | `Imobiliário` |
| Domain | `gasigliaadvocacia.com.br` |

Feito em outubro de 2026. O `Website ID` gerado foi
`550d19d0-b832-4380-bb1a-5dd45f5c3a53`, e já está no `index.html`.

O painel mostra um *Tracking code* apontando para
`https://stats.ultradistancia.com.br/script.js`. **Não use esse endereço.** Ele
faria a medição depender de outro domínio e cair nos bloqueadores. O que vale é
o `/stats/script.js` do passo 7.3.

### 7.2 Pôr o ID na página

Diferente do Ultra Distância, aqui **não há variável de ambiente nem build**: o
site é estático, então o ID fica escrito no HTML. A tag já está no `<head>` do
`index.html`:

```html
<script defer src="/stats/script.js"
        data-website-id="550d19d0-b832-4380-bb1a-5dd45f5c3a53"></script>
```

Para medir outro site estático um dia, é esta linha que muda — o `src` continua
igual, só o ID troca. Depois de editar, comite e rode `./deploy.sh` na VPS.

### 7.3 Publicar o rastreador no nginx

**Não copie o arquivo do repositório por cima do que está na VPS.** O
`certbot` já acrescentou a porta 443, o certificado e o redirecionamento ao
arquivo em produção; recopiar desfaria tudo isso e o site voltaria a ser só
HTTP. O arquivo versionado serve para uma instalação nova.

Acrescente **uma linha** ao arquivo que já está rodando:

```bash
sudo cp /etc/nginx/sites-available/imobiliario \
        /etc/nginx/sites-available/imobiliario.bak
sudo nano /etc/nginx/sites-available/imobiliario
```

A linha é esta, e vai **dentro** do bloco que tem o `root` e o `location /`,
que depois do certbot é o bloco do 443:

```nginx
    include /home/dgasiglia/infra/umami/nginx-stats.conf;
```

Um bom lugar é logo depois que o `location ~ /\. { … }` fechar. A ordem das
diretivas dentro do `server` não importa para o nginx; o que importa é estar
dentro das chaves do bloco certo.

O `include` puxa o arquivo de onde ele está, em vez de duplicar o conteúdo.
Uma correção futura no `nginx-stats.conf` chega à produção com `git pull` no
repositório `infra` e um reload, sem reabrir o arquivo do nginx.

Se o repositório `infra` ainda não estiver na VPS:

```bash
cd /home/dgasiglia && git clone git@github.com:dgasiglia7/infra.git
```

Valide e recarregue:

```bash
sudo nginx -t            # valida ANTES de recarregar
sudo systemctl reload nginx
```

Para desistir e voltar ao estado anterior:

```bash
sudo cp /etc/nginx/sites-available/imobiliario.bak \
        /etc/nginx/sites-available/imobiliario
```

### 7.4 Conferir

```bash
curl -sI https://gasigliaadvocacia.com.br/stats/script.js | head -1
curl -s https://gasigliaadvocacia.com.br/ | grep -o 'data-website-id="[^"]*"'
```

| Resposta | O que significa |
| --- | --- |
| `200` e o ID preenchido | certo — abra o site e a visita aparece no painel em segundos |
| `200` mas o ID vem vazio | a tag saiu do `head` — confira o `index.html` |
| `404` | o `include` não entrou no bloco que tem o `location /` |
| `502` | o nginx está certo, mas o contêiner do Umami não responde: `docker compose ps` na pasta `infra/umami` |

## 8. Formulário de avaliação (envio do lead)

Até aqui o formulário validava os campos e mostrava um aviso pedindo que a
pessoa usasse o WhatsApp: não havia para onde mandar. Este passo liga o envio.

**Traga o código primeiro.** A pasta `lead/` é nova; sem isto, os comandos
abaixo falham com `No such file or directory`:

```bash
cd /home/dgasiglia/imobiliario && git pull --ff-only && ls
```

`lead` tem que aparecer na listagem antes de seguir.

### Como funciona

O navegador faz `POST` para `/api/lead`, **no próprio domínio**. O nginx aplica
o limite de taxa e repassa para o serviço em `127.0.0.1:3006`, que valida de
novo, grava o lead em disco e dispara o e-mail pelo SMTP da Hostinger.

Mesma origem é o ponto do desenho: não há CORS, e nenhuma credencial existe no
lado do cliente. A senha de aplicativo do SMTP fica em `lead/.env`, na VPS.

A ordem importa: **grava antes de enviar**. Se o SMTP estiver fora do ar, o
lead está salvo em `lead/data/leads.jsonl` e dá para recuperar. Na ordem
inversa, uma falha de envio seria um cliente perdido achando que foi atendido.

### 8.1 A caixa e a senha de aplicativo

O remetente é `contato@gasigliaadvocacia.com.br`, caixa da Hostinger. A senha
é uma **senha de aplicativo**, não a senha de login:

hPanel → **E-mails** → `gasigliaadvocacia.com.br` → **Mailboxes** → os três
pontos ao lado da caixa → **App passwords** → **Generate**.

Dê um nome que se explique daqui a um ano, como `smtp-site-imobiliario`, e
copie na hora: ela aparece **uma única vez**. Se perder, gere outra e revogue a
anterior — é justamente para isso que existem várias por caixa.

Usar senha de aplicativo em vez da senha da caixa não é formalidade. Se a VPS
for comprometida, você revoga aquela entrada e o acesso ao e-mail do escritório
continua intacto.

> A caixa fica numa conta Hostinger diferente da que hospeda a VPS. Isso não
> atrapalha: SMTP autenticado não sabe de onde parte a conexão. O que muda é
> que só quem tem acesso àquela conta consegue gerar ou revogar a senha.

### 8.2 Arquivo de ambiente

```bash
cd /home/dgasiglia/imobiliario/lead
cp .env.example .env
chmod 600 .env
nano .env
```

Preencha `SMTP_PASS` com a senha de aplicativo e confira `MAIL_TO`. O `.env`
está no `.gitignore` e nunca vai para o GitHub.

### 8.3 Dependências e serviço

```bash
cd /home/dgasiglia/imobiliario/lead && npm ci --omit=dev
mkdir -p data && chmod 700 data
sudo cp /home/dgasiglia/imobiliario/deploy/imobiliario-lead.service         /etc/systemd/system/imobiliario-lead.service
sudo systemctl daemon-reload
sudo systemctl enable --now imobiliario-lead
sudo systemctl status imobiliario-lead --no-pager
```

O serviço se recusa a subir se faltar qualquer variável de ambiente. É
proposital: falhar alto é melhor do que subir e descartar lead em silêncio.

O `mkdir` não é detalhe: a unidade declara `ReadWritePaths=.../lead/data`, e o
systemd monta esse caminho **antes** de executar o processo. Se a pasta não
existir, o serviço nem chega a rodar — morre com `status=226/NAMESPACE` e fica
reiniciando. Criar a pasta e dar `systemctl restart` resolve.

### 8.4 nginx

```bash
/home/dgasiglia/imobiliario/deploy/instalar-nginx-lead.sh
```

Pede `sudo` sozinho. Ele instala a zona do limite de taxa em `conf.d/` e o
bloco da rota em `/etc/nginx/snippets/imobiliario-lead.conf`, acrescenta o
`include` ao `server` certo, roda `nginx -t`, recarrega e confere que um POST
vazio em `/api/lead` responde `422`. Pode rodar de novo quantas vezes quiser.

O que ele faz que a mão erra: achar o `server` certo. O certbot deixou três
blocos neste arquivo — o do domínio na 443, o do `www` na 443 e o da porta 80
que só redireciona. A rota tem que entrar no primeiro; nos outros dois ela não
serviria para nada. O script procura o bloco que escuta na **443** e atende
`gasigliaadvocacia.com.br` **sem `www`**, e se não achar, recusa em vez de
chutar.

Antes de mexer no arquivo do site ele guarda uma cópia com data no nome. Se o
`nginx -t` reprovar, a cópia volta e nada é recarregado: um site fora do ar é
pior do que um formulário fora do ar.

A zona do limite de taxa vai em `conf.d/`, e não junto do site, porque
`limit_req_zone` só vale no contexto `http` — dentro de um `server { … }` o
nginx recusa a configuração inteira.

O bloco da rota mora num snippet pelo mesmo motivo de higiene: daí em diante,
mudar a rota é trocar [`../deploy/nginx-lead-location.conf`](../deploy/nginx-lead-location.conf)
e publicar. O `deploy.sh` copia o snippet quando ele muda e recarrega o nginx
sozinho — ninguém volta a editar à mão o arquivo em que o certbot também mexe.
### 8.5 Conferir

Um POST vazio tem que ser **recusado**, sem criar lead nenhum:

```bash
curl -s -o /dev/null -w '%{http_code}
' -X POST   -H 'Content-Type: application/json' -d '{}'   https://gasigliaadvocacia.com.br/api/lead
```

| Resposta | O que significa |
| --- | --- |
| `422` | certo — chegou ao serviço e a validação recusou |
| `502` | o nginx está certo, mas o serviço não responde: `systemctl status imobiliario-lead` |
| `404` | o `location = /api/lead` não entrou no bloco da porta 443 |
| `429` | limite de taxa; espere um minuto |

Depois faça um envio de verdade pelo site e confirme que o e-mail chega. Se
não chegar, o lead ainda está gravado:

```bash
tail -n 5 /home/dgasiglia/imobiliario/lead/data/leads.jsonl
sudo journalctl -u imobiliario-lead -n 50 --no-pager
```

A linha `GRAVADO MAS NAO ENVIADO` no log é o sinal de que o SMTP falhou e há
lead esperando resgate.

### 8.6 Dados pessoais

O lead é nome, telefone, e-mail e o relato de um conflito jurídico: matéria de
sigilo profissional e dado pessoal sob a LGPD.

`lead/data/` está no `.gitignore` e o arquivo é gravado com `chmod 600`. Depois
que o lead virou e-mail e entrou no fluxo do escritório, a cópia na VPS é risco
sem benefício — vale definir de quanto em quanto tempo limpar o arquivo.

## 9. Prévia do link no WhatsApp e nas redes

A imagem que aparece quando alguém cola o endereço do site vem das metatags
`og:image` e `twitter:image`, no `<head>` do `index.html`. O arquivo é
`assets/og-gasiglia-advocacia.jpg`, em 1200x630 — proporção que o Facebook
recomenda e que o WhatsApp usa para mostrar a prévia grande, em vez da
miniatura quadrada.

**Trocar a foto do topo não troca essa imagem.** São arquivos diferentes, de
propósito: o topo é 3:2 e a prévia é 1.91:1, e o mesmo recorte não serve nos
dois. Se a foto do escritório mudar, gere a prévia de novo a partir da mesma
origem e publique.

### 9.1 Por que a antiga continua aparecendo

Quem guarda a prévia é a Meta, não o site. Publicar a mudança não avisa
ninguém: o WhatsApp continua mostrando o que leu da última vez, por semanas.
São duas camadas de cache, e a ordem importa.

**Primeiro, o cache da Meta.** Abra o
[Sharing Debugger](https://developers.facebook.com/tools/debug/), cole
`https://gasigliaadvocacia.com.br/` e clique em **Scrape Again**. A tela mostra
qual imagem o robô está vendo — se já for a nova, a origem está correta. O
WhatsApp lê desse mesmo cache.

**Depois, o cache do aparelho.** A conversa onde o link já foi mandado guarda a
miniatura antiga, e ela não se atualiza. Para conferir de verdade, mande o link
numa conversa onde ele nunca apareceu — o "recado para mim mesmo" serve.

Se precisar de uma prova imediata, sem esperar nada: mande
`https://gasigliaadvocacia.com.br/?v=2`. O endereço é outro, então não há cache
nenhum, e a página é a mesma. Serve para conferir, não para divulgar.

### 9.2 Gerar a imagem de prévia

Não há ImageMagick nem PIL nesta máquina. O recorte foi feito com o Chrome em
modo headless desenhando num `canvas` — origem `assets/escritorio-equipe-origem.png`
(1536x1024), recorte de 1536x806 a partir de `y=70`, reduzido para 1200x630 e
salvo em JPEG a 86%.

O `y=70` não é arbitrário: centralizar o recorte cortaria as cabeças da fila de
trás. Se a foto mudar, confira o resultado antes de publicar — num retrato de
equipe, o erro aparece como gente decapitada na prévia.

## Conferência depois de publicar

- `https://gasigliaadvocacia.com.br` abre a landing page, com cadeado.
- `http://www.gasigliaadvocacia.com.br` termina em `https://gasigliaadvocacia.com.br`.
- `https://gasigliaadvocacia.com` continua abrindo o WordPress, intocado.
- Enviar e receber um e-mail em `@gasigliaadvocacia.com.br`.
- Colar o link no WhatsApp: a prévia mostra a foto da equipe.
- A visita aparece em `https://stats.ultradistancia.com.br`, no site `Imobiliário`.
- Um POST vazio em `/api/lead` responde `422`, e um envio pelo formulário chega por e-mail.

## O que a página ainda busca de fora

Só as miniaturas dos vídeos, em `i.ytimg.com`, que é o CDN do YouTube e não
depende de nenhum domínio do escritório. Logotipo e fotos estão em `assets/`,
servidos pela própria VPS.

Os links da Política de Privacidade apontam para
`gasigliaadvocacia.com/politica-de-privacidade/`, que continua no WordPress.
