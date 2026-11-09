// Recebe o formulário da landing page e entrega o lead por e-mail.
//
// Escuta SÓ em 127.0.0.1: quem fala com a internet é o nginx, que expõe este
// serviço como /api/lead no próprio domínio do site. Mesma origem, então não
// há CORS, e nenhuma credencial chega ao navegador — ver docs/DEPLOY.md.
//
// A ordem das operações importa: grava o lead em disco ANTES de tentar o
// e-mail. Se o SMTP estiver fora do ar, o lead está salvo e dá para recuperar;
// na ordem inversa, uma falha de envio seria um cliente perdido que achou que
// tinha sido atendido.

import { createServer } from "node:http";
import { appendFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import nodemailer from "nodemailer";

const RAIZ = dirname(fileURLToPath(import.meta.url));
const ARQUIVO_LEADS = join(RAIZ, "data", "leads.jsonl");

const PORTA = Number(process.env.PORT || 3006);

// Corpo maior que isto é descartado sem parse. O formulário cheio não passa de
// uns 2 KB; o limite existe para que um POST gigante não consuma memória.
const LIMITE_CORPO = 32 * 1024;

// Segunda camada de limite de taxa. A primeira está no nginx, por IP e por
// minuto; esta pega quem passa devagar o bastante para escapar de lá.
const LIMITE_POR_IP = 5;
const JANELA_MS = 60 * 60 * 1000;
const envios = new Map();

const CAMPOS = {
  nome: { obrigatorio: true, min: 3, max: 120 },
  telefone: { obrigatorio: true, min: 10, max: 20 },
  email: { obrigatorio: true, min: 5, max: 160 },
  cidade: { obrigatorio: true, min: 2, max: 120 },
  empreendimento: { obrigatorio: true, min: 2, max: 160 },
  construtora: { obrigatorio: false, max: 160 },
  tipo_problema: { obrigatorio: true, min: 2, max: 120 },
  data_entrega: { obrigatorio: false, max: 20 },
  descricao: { obrigatorio: true, min: 20, max: 1500 },
  preferencia_contato: { obrigatorio: true, min: 2, max: 20 },
};

const ROTULOS = {
  nome: "Nome",
  telefone: "Telefone",
  email: "E-mail",
  cidade: "Cidade",
  empreendimento: "Empreendimento",
  construtora: "Construtora",
  tipo_problema: "Tipo de problema",
  data_entrega: "Data prevista para entrega",
  descricao: "Descrição da situação",
  preferencia_contato: "Preferência de contato",
};

function exigirEnv(nome) {
  const valor = process.env[nome];
  if (!valor) {
    console.error(`[lead] falta a variavel de ambiente ${nome}`);
    process.exit(1);
  }
  return valor;
}

const SMTP_HOST = exigirEnv("SMTP_HOST");
const SMTP_PORT = Number(exigirEnv("SMTP_PORT"));
const SMTP_USER = exigirEnv("SMTP_USER");
const SMTP_PASS = exigirEnv("SMTP_PASS");
const MAIL_FROM = exigirEnv("MAIL_FROM");
const MAIL_TO = exigirEnv("MAIL_TO");

// `secure` é a diferença entre 465 e 587: a 465 é TLS desde o primeiro byte,
// a 587 começa em claro e sobe para TLS com STARTTLS.
const transporte = nodemailer.createTransport({
  host: SMTP_HOST,
  port: SMTP_PORT,
  secure: SMTP_PORT === 465,
  auth: { user: SMTP_USER, pass: SMTP_PASS },
  connectionTimeout: 10000,
  greetingTimeout: 10000,
  socketTimeout: 20000,
});

function dentroDoLimite(ip) {
  const agora = Date.now();
  const recentes = (envios.get(ip) || []).filter((t) => agora - t < JANELA_MS);
  if (recentes.length >= LIMITE_POR_IP) {
    envios.set(ip, recentes);
    return false;
  }
  recentes.push(agora);
  envios.set(ip, recentes);
  return true;
}

// A cada hora, descarta os IPs que não voltaram. Sem isso o Map cresceria para
// sempre num processo que fica meses no ar.
setInterval(() => {
  const agora = Date.now();
  for (const [ip, marcas] of envios) {
    const vivos = marcas.filter((t) => agora - t < JANELA_MS);
    if (vivos.length === 0) envios.delete(ip);
    else envios.set(ip, vivos);
  }
}, JANELA_MS).unref();

function limpar(valor) {
  if (typeof valor !== "string") return "";
  // Remove controles (inclusive CR e LF) para que nada injete cabeçalho de
  // e-mail no assunto, e colapsa espaço repetido.
  return valor.replace(/[\u0000-\u001F\u007F]/g, " ").replace(/\s+/g, " ").trim();
}

function validar(bruto) {
  const erros = [];
  const dados = {};

  for (const [campo, regra] of Object.entries(CAMPOS)) {
    // A descrição é o único campo onde a quebra de linha é conteúdo, não ruído.
    const valor =
      campo === "descricao"
        ? String(bruto[campo] ?? "").replace(/\r\n/g, "\n").trim()
        : limpar(bruto[campo]);

    if (!valor) {
      if (regra.obrigatorio) erros.push(`${ROTULOS[campo]} é obrigatório`);
      continue;
    }
    if (regra.min && valor.length < regra.min) {
      erros.push(`${ROTULOS[campo]} está curto demais`);
      continue;
    }
    if (regra.max && valor.length > regra.max) {
      erros.push(`${ROTULOS[campo]} está longo demais`);
      continue;
    }
    dados[campo] = valor;
  }

  if (dados.email && !/^[^@\s]+@[^@\s.]+\.[^@\s]+$/.test(dados.email)) {
    erros.push("E-mail inválido");
  }

  // O aceite é o que autoriza o tratamento dos dados: sem ele não há lead.
  const consentimento = bruto.consentimento;
  if (consentimento !== true && consentimento !== "on" && consentimento !== "true") {
    erros.push("É necessário autorizar o tratamento dos dados");
  }

  return { dados, erros };
}

function montarEmail(dados, meta) {
  const linhas = Object.keys(ROTULOS)
    .filter((campo) => dados[campo])
    .map((campo) => `${ROTULOS[campo]}: ${dados[campo]}`);

  const texto = [
    "Nova solicitação de avaliação inicial pelo site.",
    "",
    ...linhas,
    "",
    "---",
    `Origem: ${meta.origem}`,
    `Recebido em: ${meta.recebido_em}`,
  ].join("\n");

  return {
    from: MAIL_FROM,
    to: MAIL_TO,
    // O cliente responde a partir daqui. O remetente continua sendo a caixa do
    // domínio: enviar "em nome" do visitante quebraria o SPF e mandaria o
    // aviso direto para o spam.
    replyTo: `${dados.nome} <${dados.email}>`,
    subject: `Nova avaliação — ${dados.nome} — ${dados.tipo_problema}`,
    text: texto,
  };
}

function responder(res, codigo, corpo) {
  const json = JSON.stringify(corpo);
  res.writeHead(codigo, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(json),
    "Cache-Control": "no-store",
  });
  res.end(json);
}

function lerCorpo(req) {
  return new Promise((resolve, reject) => {
    let total = 0;
    const partes = [];
    req.on("data", (pedaco) => {
      total += pedaco.length;
      if (total > LIMITE_CORPO) {
        reject(new Error("corpo grande demais"));
        req.destroy();
        return;
      }
      partes.push(pedaco);
    });
    req.on("end", () => resolve(Buffer.concat(partes).toString("utf8")));
    req.on("error", reject);
  });
}

const servidor = createServer(async (req, res) => {
  if (req.method !== "POST" || req.url !== "/lead") {
    responder(res, 404, { erro: "nao encontrado" });
    return;
  }

  // O nginx substitui este cabeçalho pelo IP real de quem abriu a conexão, em
  // vez de anexar ao que o visitante mandou — ver nginx-imobiliario.conf.
  const ip = (req.headers["x-forwarded-for"] || "").split(",")[0].trim() || "desconhecido";

  let bruto;
  try {
    bruto = JSON.parse(await lerCorpo(req));
  } catch {
    responder(res, 400, { erro: "corpo invalido" });
    return;
  }

  // Campo-armadilha, invisível na página. Gente não preenche; robô preenche.
  // Responde 200 de propósito: avisar que foi barrado ensina o robô a tentar
  // de novo sem o campo.
  if (typeof bruto.website === "string" && bruto.website.trim() !== "") {
    console.warn(`[lead] honeypot de ${ip}`);
    responder(res, 200, { ok: true });
    return;
  }

  const { dados, erros } = validar(bruto);
  if (erros.length > 0) {
    responder(res, 422, { erro: erros.join("; ") });
    return;
  }

  // O limite conta só o que PASSOU na validação, e por isso vem depois dela.
  // O que enche a caixa do escritório é lead válido; um POST malformado não
  // gera e-mail nem grava nada, e o volume bruto já é contido pelo nginx.
  // Contando as tentativas recusadas, quem errasse o formulário cinco vezes
  // ficaria uma hora sem conseguir enviar — castigo para a pessoa errada.
  if (!dentroDoLimite(ip)) {
    console.warn(`[lead] limite por IP atingido: ${ip}`);
    responder(res, 429, { erro: "muitas solicitacoes" });
    return;
  }

  const meta = {
    origem: limpar(bruto.origem) || "landing-page-imoveis-na-planta",
    recebido_em: new Date().toISOString(),
    ip,
  };

  const registro = { ...dados, ...meta, email_enviado: null };

  try {
    await mkdir(dirname(ARQUIVO_LEADS), { recursive: true });
    await appendFile(ARQUIVO_LEADS, JSON.stringify(registro) + "\n", { mode: 0o600 });
  } catch (err) {
    // Sem gravação não há rede de segurança, então aqui o erro vai para o
    // visitante: melhor ele usar o WhatsApp do que achar que foi atendido.
    console.error("[lead] falha ao gravar:", err);
    responder(res, 500, { erro: "falha ao registrar" });
    return;
  }

  try {
    await transporte.sendMail(montarEmail(dados, meta));
    console.log(`[lead] recebido e enviado — ${dados.nome} (${ip})`);
  } catch (err) {
    // O lead está em disco, então a promessa feita ao visitante é verdadeira:
    // o escritório recebeu. Quem precisa ser avisado é o operador, pelo log.
    console.error(`[lead] GRAVADO MAS NAO ENVIADO — ${dados.nome}:`, err.message);
    await appendFile(ARQUIVO_LEADS, JSON.stringify({ ...registro, email_enviado: false }) + "\n", { mode: 0o600 }).catch(() => {});
  }

  responder(res, 200, { ok: true });
});

servidor.listen(PORTA, "127.0.0.1", () => {
  console.log(`[lead] ouvindo em 127.0.0.1:${PORTA}`);
});

for (const sinal of ["SIGTERM", "SIGINT"]) {
  process.on(sinal, () => servidor.close(() => process.exit(0)));
}
