# Landing page – Direito Imobiliário (imóveis na planta)

Landing page da **Gasiglia Advocacia** voltada a compradores de imóveis na planta que enfrentam atraso na entrega, defeitos, cobranças, distrato ou problemas contratuais.

- Página publicada: https://dgasiglia7.github.io/imobiliario/
- Arquivo único: [`index.html`](index.html) (HTML5, Bootstrap 5, Bootstrap Icons, JavaScript puro)

## Como usar

Abra `index.html` no navegador ou publique o arquivo em qualquer hospedagem estática.

## Configuração

No bloco `CONFIG`, dentro do `<script>` no final do arquivo:

| Chave | Descrição |
|---|---|
| `WHATSAPP_NUMBER` | Número no formato internacional, somente dígitos |
| `WHATSAPP_MESSAGE` | Mensagem inicial enviada ao abrir o WhatsApp |
| `FORM_ENDPOINT` | URL da API, CRM ou serviço de e-mail que receberá o formulário (POST JSON). Vazio: o formulário não simula envio |
| `CONTACT_EMAIL` | E-mail exibido como alternativa quando não há endpoint |

O array `TESTIMONIALS` controla a seção de depoimentos. Enquanto estiver vazio, a seção fica oculta. Preencha apenas com relatos autênticos e previamente autorizados.

## Seção de vídeos

Os três vídeos ficam na seção `#videos`, na ordem em que aparecem no HTML. O player do YouTube só é carregado depois que a pessoa clica, então a página não carrega nada do YouTube de início.

Para trocar um vídeo, edite no bloco correspondente:

- `data-id` do botão, com o identificador do vídeo
- `src` da miniatura, no padrão `https://i.ytimg.com/vi/<ID>/oardefault.jpg`
- `alt` da imagem, `data-title` e `aria-label` do botão
- a etiqueta (`video-tag`) e o título (`video-title`)

## Pendências

- Confirmar o horário de atendimento (rodapé, seção de contato e Schema.org).
- Substituir o link de Termos de Uso quando a página existir.
- Opcional: trocar a imagem ilustrativa do hero por uma foto própria.
