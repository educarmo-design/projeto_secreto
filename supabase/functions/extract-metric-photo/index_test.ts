// Suíte de testes de extract-metric-photo — Passo 1 do F10 (extrator de
// glicosímetro + tubulação Zero Storage) e Passo 2 (extrator de prato de
// comida — "IA traduz, backend calcula", A.2).
//
// Rodar com:
//   deno test --allow-env supabase/functions/extract-metric-photo/index_test.ts
//
// Camadas, como nas irmãs (garmin-gateway / calculate-recovery-mode):
//   (a) as funções puras de glicosímetro (`parseRespostaGemini`/
//       `avaliarLeitura`) — sem I/O, 100% determinísticas;
//   (b) as funções puras de prato (`parseRespostaGeminiPrato`,
//       `encontrarAlimento`/`encontrarMedida`, `calcularPrato`) — idem, com
//       um catálogo fixo em memória, sem tocar o banco;
//   (c) o handler HTTP completo, com autenticador/Gemini/catálogo falsos —
//       rede (fetch), GEMINI_API_KEY e banco nunca são tocados.

import { assertEquals, assertAlmostEquals, assertStringIncludes } from '@std/assert';
import {
  avaliarLeitura,
  calcularPrato,
  createHandler,
  criarChamadorGeminiReal,
  encontrarAlimento,
  encontrarMedida,
  normalizarTexto,
  parseRespostaGemini,
  parseRespostaGeminiPrato,
  type AlimentoCatalogo,
  type AutenticadorLike,
  type CatalogoAlimentosLike,
  type ChamadorGemini,
  type ExtracaoGlicose,
  type ExtracaoItemPrato,
} from './index.ts';

// ============================================================================
// (a) parseRespostaGemini — parsing robusto de saída não-confiável (A.5)
// ============================================================================
Deno.test('parseRespostaGemini: JSON limpo e legível', () => {
  const r = parseRespostaGemini(
    '{"legivel":true,"valor_mg_dl":117,"confianca":0.96,"possivel_foto_de_tela":false,"motivo":null}',
  );
  assertEquals(r.legivel, true);
  assertEquals(r.valorMgDl, 117);
  assertEquals(r.confianca, 0.96);
  assertEquals(r.possivelFotoDeTela, false);
});

Deno.test('parseRespostaGemini: remove cercas de markdown ```json```', () => {
  const r = parseRespostaGemini(
    '```json\n{"legivel":true,"valor_mg_dl":90,"confianca":0.8,"possivel_foto_de_tela":false,"motivo":null}\n```',
  );
  assertEquals(r.legivel, true);
  assertEquals(r.valorMgDl, 90);
});

Deno.test('parseRespostaGemini: texto sujo/não-JSON vira ilegível (não lança)', () => {
  const r = parseRespostaGemini('desculpe, não consegui analisar a imagem');
  assertEquals(r.legivel, false);
  assertEquals(r.valorMgDl, null);
  assertEquals(r.motivo, 'json_invalido');
});

Deno.test('parseRespostaGemini: confiança fora de 0..1 é grampeada', () => {
  assertEquals(parseRespostaGemini('{"legivel":true,"confianca":5}').confianca, 1);
  assertEquals(parseRespostaGemini('{"legivel":true,"confianca":-3}').confianca, 0);
  assertEquals(parseRespostaGemini('{"legivel":true}').confianca, 0);
});

Deno.test('parseRespostaGemini: valor não-numérico é descartado (nunca chuta)', () => {
  const r = parseRespostaGemini('{"legivel":true,"valor_mg_dl":"cento e dez","confianca":0.9}');
  assertEquals(r.valorMgDl, null);
});

// ============================================================================
// (b) avaliarLeitura — a palavra final é do backend (A.2/A.5)
// ============================================================================
function extracao(over: Partial<ExtracaoGlicose> = {}): ExtracaoGlicose {
  return {
    legivel: true,
    valorMgDl: 117,
    confianca: 0.95,
    possivelFotoDeTela: false,
    motivo: null,
    ...over,
  };
}

Deno.test('avaliarLeitura: leitura boa é aceita e arredondada', () => {
  const a = avaliarLeitura(extracao({ valorMgDl: 116.7 }));
  assertEquals(a.aceita, true);
  assertEquals(a.glicoseMgDl, 117);
});

Deno.test('avaliarLeitura: modelo declara ilegível -> rejeita', () => {
  const a = avaliarLeitura(extracao({ legivel: false, motivo: 'foto borrada' }));
  assertEquals(a.aceita, false);
  assertEquals(a.motivo, 'foto borrada');
});

Deno.test('avaliarLeitura: confiança abaixo do piso -> rejeita', () => {
  const a = avaliarLeitura(extracao({ confianca: 0.5 }));
  assertEquals(a.aceita, false);
  assertEquals(a.motivo, 'confianca_baixa');
});

Deno.test('avaliarLeitura: número fora da faixa plausível -> rejeita', () => {
  assertEquals(avaliarLeitura(extracao({ valorMgDl: 1100 })).aceita, false);
  assertEquals(avaliarLeitura(extracao({ valorMgDl: 1100 })).motivo, 'fora_da_faixa');
  // 5.5 mmol/L confundido com mg/dL cairia abaixo de 20 -> rejeitado (seguro).
  assertEquals(avaliarLeitura(extracao({ valorMgDl: 5.5 })).aceita, false);
});

Deno.test('avaliarLeitura: legível sem número -> rejeita', () => {
  const a = avaliarLeitura(extracao({ valorMgDl: null }));
  assertEquals(a.aceita, false);
  assertEquals(a.motivo, 'sem_numero');
});

Deno.test('avaliarLeitura: foto de tela é propagada, não bloqueia (Passo 1)', () => {
  const a = avaliarLeitura(extracao({ possivelFotoDeTela: true }));
  assertEquals(a.aceita, true);
  assertEquals(a.possivelFotoDeTela, true);
});

// ============================================================================
// (b) parseRespostaGeminiPrato — parsing robusto (A.5, aplicado ao prato)
// ============================================================================
Deno.test('parseRespostaGeminiPrato: JSON limpo com itens', () => {
  const r = parseRespostaGeminiPrato(
    '{"itens":[{"nome":"arroz","medida":"colher de sopa","quantidade":2,"confianca":0.9}],"possivel_foto_de_tela":false}',
  );
  assertEquals(r.itens.length, 1);
  assertEquals(r.itens[0].nome, 'arroz');
  assertEquals(r.itens[0].medida, 'colher de sopa');
  assertEquals(r.itens[0].quantidade, 2);
  assertEquals(r.itens[0].confianca, 0.9);
});

Deno.test('parseRespostaGeminiPrato: prato vazio é resultado legítimo (não erro)', () => {
  const r = parseRespostaGeminiPrato('{"itens":[],"possivel_foto_de_tela":false}');
  assertEquals(r.itens.length, 0);
});

Deno.test('parseRespostaGeminiPrato: texto sujo vira lista vazia (não lança)', () => {
  const r = parseRespostaGeminiPrato('desculpe, não é uma foto de comida');
  assertEquals(r.itens.length, 0);
  assertEquals(r.possivelFotoDeTela, false);
});

Deno.test('parseRespostaGeminiPrato: item sem nome ou sem medida é descartado', () => {
  const r = parseRespostaGeminiPrato(
    '{"itens":[{"nome":"","medida":"unidade","quantidade":1,"confianca":0.9},{"nome":"ovo","medida":"","quantidade":1,"confianca":0.9}]}',
  );
  assertEquals(r.itens.length, 0);
});

Deno.test('parseRespostaGeminiPrato: quantidade ausente/inválida assume 1', () => {
  const r = parseRespostaGeminiPrato(
    '{"itens":[{"nome":"ovo","medida":"unidade","confianca":0.9}]}',
  );
  assertEquals(r.itens[0].quantidade, 1);
});

Deno.test('parseRespostaGeminiPrato: quantidade absurda é grampeada (teto de sanidade)', () => {
  const r = parseRespostaGeminiPrato(
    '{"itens":[{"nome":"arroz","medida":"colher de sopa","quantidade":500,"confianca":0.9}]}',
  );
  assertEquals(r.itens[0].quantidade, 20);
});

Deno.test('parseRespostaGeminiPrato: nunca inclui campo de calorias/gramas do Gemini (A.2)', () => {
  // Mesmo que o modelo desobedeça e mande "calorias" no item, o parser só lê
  // nome/medida/quantidade/confianca — o campo extra é ignorado, nunca usado.
  const r = parseRespostaGeminiPrato(
    '{"itens":[{"nome":"arroz","medida":"colher de sopa","quantidade":1,"confianca":0.9,"calorias":9999}]}',
  );
  assertEquals(Object.keys(r.itens[0]).includes('calorias'), false);
});

// ============================================================================
// (b) normalizarTexto / encontrarAlimento / encontrarMedida
// ============================================================================
Deno.test('normalizarTexto: remove acento e caixa', () => {
  assertEquals(normalizarTexto('Arroz Branco'), 'arroz branco');
  assertEquals(normalizarTexto('Concha Média'), 'concha media');
  assertEquals(normalizarTexto('  Feijão  '), 'feijao');
});

const CATALOGO_TESTE: AlimentoCatalogo[] = [
  {
    id: 'arroz-id',
    nomeTaco: 'Arroz, branco, cozido',
    aliases: ['arroz', 'arroz branco', 'arroz cozido'],
    caloriasKcal100g: 128,
    proteinasG100g: 2.5,
    carboidratosG100g: 28.1,
    gordurasG100g: 0.2,
    medidas: [
      { medida: 'colher de sopa', gramas: 25 },
      { medida: 'escumadeira', gramas: 90 },
    ],
  },
  {
    id: 'feijao-id',
    nomeTaco: 'Feijão, carioca, cozido',
    aliases: ['feijao', 'feijao carioca'],
    caloriasKcal100g: 76,
    proteinasG100g: 4.8,
    carboidratosG100g: 13.6,
    gordurasG100g: 0.5,
    medidas: [{ medida: 'concha média', gramas: 80 }],
  },
];

Deno.test('encontrarAlimento: casa por alias exato, ignorando acento/caixa', () => {
  const a = encontrarAlimento(CATALOGO_TESTE, 'Arroz');
  assertEquals(a?.id, 'arroz-id');
});

Deno.test('encontrarAlimento: casa por substring quando não há exato', () => {
  const a = encontrarAlimento(CATALOGO_TESTE, 'arroz branco soltinho');
  assertEquals(a?.id, 'arroz-id');
});

Deno.test('encontrarAlimento: alimento fora do catálogo -> null (nunca chuta)', () => {
  assertEquals(encontrarAlimento(CATALOGO_TESTE, 'lasanha'), null);
});

Deno.test('encontrarMedida: medida é escopada ao alimento (mesma "colher" pesa diferente)', () => {
  const arroz = CATALOGO_TESTE[0];
  const feijao = CATALOGO_TESTE[1];
  assertEquals(encontrarMedida(arroz, 'colher de sopa')?.gramas, 25);
  assertEquals(encontrarMedida(feijao, 'colher de sopa'), null); // feijão só tem "concha média"
});

// ============================================================================
// (b) calcularPrato — o ÚNICO lugar que produz um número nutricional (A.2)
// ============================================================================
function itemExtraido(over: Partial<ExtracaoItemPrato> = {}): ExtracaoItemPrato {
  return { nome: 'arroz', medida: 'colher de sopa', quantidade: 2, confianca: 0.9, ...over };
}

Deno.test('calcularPrato: regra de três exata para um item casado', () => {
  const r = calcularPrato([itemExtraido()], CATALOGO_TESTE);
  assertEquals(r.itens.length, 1);
  const item = r.itens[0];
  // 2 colheres de sopa = 50g de arroz. 128 kcal/100g * 50g = 64 kcal.
  // Macros arredondados a 1 casa decimal (arredondar(v, 1)).
  assertEquals(item.gramasEstimados, 50);
  assertEquals(item.calorias, 64);
  assertAlmostEquals(item.proteinasG, 1.3, 0.001); // 2.5/100 * 50 = 1.25 -> 1.3
  assertAlmostEquals(item.carboidratosG, 14.1, 0.001); // 28.1/100 * 50 = 14.05 -> 14.1
  assertAlmostEquals(item.gordurasG, 0.1, 0.001); // 0.2/100 * 50 = 0.1
});

Deno.test('calcularPrato: soma totais de múltiplos itens casados', () => {
  const r = calcularPrato(
    [itemExtraido({ nome: 'arroz', medida: 'colher de sopa', quantidade: 2 }),
     itemExtraido({ nome: 'feijao', medida: 'concha média', quantidade: 1 })],
    CATALOGO_TESTE,
  );
  // arroz: 64 kcal (acima) + feijão: 80g * 76/100 = 60.8 -> arredonda p/ 61
  assertEquals(r.totais.calorias, 64 + 61);
  assertEquals(r.itensNaoReconhecidos.length, 0);
});

Deno.test('calcularPrato: alimento não encontrado vai para itensNaoReconhecidos, não é inventado', () => {
  const r = calcularPrato([itemExtraido({ nome: 'lasanha', medida: 'fatia' })], CATALOGO_TESTE);
  assertEquals(r.itens.length, 0);
  assertEquals(r.itensNaoReconhecidos.length, 1);
  assertEquals(r.itensNaoReconhecidos[0].motivo, 'alimento_nao_encontrado');
  assertEquals(r.totais.calorias, 0);
});

Deno.test('calcularPrato: medida não cadastrada para aquele alimento vai para itensNaoReconhecidos', () => {
  const r = calcularPrato(
    [itemExtraido({ nome: 'feijao', medida: 'xícara' })], // feijão só tem "concha média" no catálogo de teste
    CATALOGO_TESTE,
  );
  assertEquals(r.itens.length, 0);
  assertEquals(r.itensNaoReconhecidos[0].motivo, 'medida_nao_encontrada');
});

Deno.test('calcularPrato: prato sem itens dá totais zerados (não é erro)', () => {
  const r = calcularPrato([], CATALOGO_TESTE);
  assertEquals(r.itens.length, 0);
  assertEquals(r.totais.calorias, 0);
});

// ============================================================================
// (c) Handler HTTP — com auth/Gemini/catálogo falsos (sem rede, sem API key)
// ============================================================================
const AUTH_OK: AutenticadorLike = {
  auth: {
    getUser: () =>
      Promise.resolve({ data: { user: { id: 'user-1' } }, error: null }),
  },
};

const AUTH_FALHA: AutenticadorLike = {
  auth: {
    getUser: () =>
      Promise.resolve({ data: { user: null }, error: { message: 'jwt inválido' } }),
  },
};

function geminiRespondendo(json: string): ChamadorGemini {
  return () => Promise.resolve(json);
}

const CATALOGO_FALSO: CatalogoAlimentosLike = {
  carregar: () => Promise.resolve(CATALOGO_TESTE),
};

function reqComImagem(headers: Record<string, string>): Request {
  // Corpo mínimo não-vazio; o conteúdo real não importa porque o Gemini é fake.
  return new Request('http://localhost/extract-metric-photo', {
    method: 'POST',
    headers: { Authorization: 'Bearer x', ...headers },
    body: new Uint8Array([1, 2, 3, 4]),
  });
}

Deno.test('handler: OPTIONS responde CORS', async () => {
  const res = await createHandler()(
    new Request('http://localhost', { method: 'OPTIONS' }),
  );
  assertEquals(res.status, 200);
  assertEquals(res.headers.get('Access-Control-Allow-Methods'), 'POST, OPTIONS');
});

Deno.test('handler: sem Authorization -> 401', async () => {
  const res = await createHandler({ autenticador: AUTH_OK })(
    new Request('http://localhost', {
      method: 'POST',
      headers: { 'X-Tipo-Aparelho': 'glicosimetro' },
      body: new Uint8Array([1]),
    }),
  );
  assertEquals(res.status, 401);
});

Deno.test('handler: JWT inválido -> 401', async () => {
  const res = await createHandler({ autenticador: AUTH_FALHA })(
    reqComImagem({ 'X-Tipo-Aparelho': 'glicosimetro' }),
  );
  assertEquals(res.status, 401);
});

Deno.test('handler: tipo desconhecido -> 400', async () => {
  const res = await createHandler({ autenticador: AUTH_OK })(
    reqComImagem({ 'X-Tipo-Aparelho': 'termometro' }),
  );
  assertEquals(res.status, 400);
});

Deno.test('handler: tipo conhecido mas ainda não implementado -> 422', async () => {
  const res = await createHandler({ autenticador: AUTH_OK })(
    reqComImagem({ 'X-Tipo-Aparelho': 'balanca' }),
  );
  assertEquals(res.status, 422);
  const body = await res.json();
  assertEquals(body.error, 'extrator_nao_implementado');
});

Deno.test('handler: corpo vazio -> 400', async () => {
  const res = await createHandler({ autenticador: AUTH_OK })(
    new Request('http://localhost', {
      method: 'POST',
      headers: { Authorization: 'Bearer x', 'X-Tipo-Aparelho': 'glicosimetro' },
      body: new Uint8Array([]),
    }),
  );
  assertEquals(res.status, 400);
});

Deno.test('handler: leitura boa -> 200 com glicose_jejum', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo(
      '{"legivel":true,"valor_mg_dl":117,"confianca":0.96,"possivel_foto_de_tela":false,"motivo":null}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'glicosimetro' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.glicose_jejum, 117);
  assertEquals(body.confianca, 0.96);
  assertEquals(body.tipo_captura, 'glicosimetro');
});

Deno.test('handler: leitura duvidosa -> 422 leitura_ilegivel (pede outra foto)', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo(
      '{"legivel":false,"valor_mg_dl":null,"confianca":0.2,"possivel_foto_de_tela":false,"motivo":"reflexo no visor"}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'glicosimetro' }));

  assertEquals(res.status, 422);
  const body = await res.json();
  assertEquals(body.error, 'leitura_ilegivel');
});

Deno.test('handler: número absurdo do modelo -> 422 (não grava dado errado)', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo(
      '{"legivel":true,"valor_mg_dl":9999,"confianca":0.99,"possivel_foto_de_tela":false,"motivo":null}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'glicosimetro' }));

  assertEquals(res.status, 422);
});

Deno.test('handler: Gemini devolve texto sujo -> 422 (fallback de parsing)', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo('não foi possível ler a imagem'),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'glicosimetro' }));

  assertEquals(res.status, 422);
});

// ============================================================================
// (d) Handler HTTP — pratoRefeicao (Passo 2 do F10)
// ============================================================================
Deno.test('handler: prato reconhecido -> 200 com macros calculados pelo backend', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: geminiRespondendo(
      '{"itens":[{"nome":"arroz","medida":"colher de sopa","quantidade":2,"confianca":0.9}],"possivel_foto_de_tela":false}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pratoRefeicao' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.tipo_captura, 'pratoRefeicao');
  assertEquals(body.itens.length, 1);
  assertEquals(body.itens[0].nome, 'Arroz, branco, cozido');
  assertEquals(body.itens[0].gramas_estimados, 50);
  assertEquals(body.itens[0].calorias, 64);
  assertEquals(body.totais.calorias, 64);
  assertEquals(body.itens_nao_reconhecidos.length, 0);
});

Deno.test('handler: prato com múltiplos itens soma totais corretamente', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: geminiRespondendo(
      '{"itens":[' +
        '{"nome":"arroz","medida":"colher de sopa","quantidade":2,"confianca":0.9},' +
        '{"nome":"feijao","medida":"concha média","quantidade":1,"confianca":0.85}' +
        '],"possivel_foto_de_tela":false}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pratoRefeicao' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.itens.length, 2);
  assertEquals(body.totais.calorias, 64 + 61);
});

Deno.test('handler: alimento fora do catálogo não derruba a requisição — vai para itens_nao_reconhecidos', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: geminiRespondendo(
      '{"itens":[{"nome":"lasanha","medida":"fatia","quantidade":1,"confianca":0.7}],"possivel_foto_de_tela":false}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pratoRefeicao' }));

  assertEquals(res.status, 200); // A.6: não é erro, o usuário decide depois (Passo 3)
  const body = await res.json();
  assertEquals(body.itens.length, 0);
  assertEquals(body.itens_nao_reconhecidos.length, 1);
  assertEquals(body.itens_nao_reconhecidos[0].motivo, 'alimento_nao_encontrado');
});

Deno.test('handler: prato vazio (Gemini não identificou nada) -> 200 com listas vazias', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: geminiRespondendo('{"itens":[],"possivel_foto_de_tela":false}'),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pratoRefeicao' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.itens.length, 0);
  assertEquals(body.totais.calorias, 0);
});

Deno.test('handler: Gemini nunca recebe/usa o catálogo — prompt não muda por alimento', async () => {
  // Guarda de regressão para A.2: o chamador do Gemini não recebe o catálogo
  // como parâmetro em nenhum lugar da assinatura ChamadorGemini — só
  // base64/mimeType/systemPrompt/userText. Este teste falha de compilação
  // (não de asserção) se algum dia alguém tentar passar o catálogo para lá.
  let prompts = 0;
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: (params) => {
      prompts += 1;
      // O prompt de prato PROÍBE calorias/gramas — checagem de regressão de
      // que o servidor está usando o prompt certo para este tipo.
      if (!params.systemPrompt.toLowerCase().includes('forbidden')) {
        throw new Error('prompt de prato deveria proibir cálculo nutricional');
      }
      return Promise.resolve('{"itens":[],"possivel_foto_de_tela":false}');
    },
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pratoRefeicao' }));

  assertEquals(res.status, 200);
  assertEquals(prompts, 1);
});

// ============================================================================
// (e) Regressão do bug de 22/jul/2026 — 404 "model not found" (ver
// RELATÓRIO DE FIM DE TAREFA). criarChamadorGeminiReal é a única função que
// monta a URL de verdade contra a API do Gemini; stuba `fetch` global para
// confirmar (1) que o nome do modelo passado entra na URL — nunca um valor
// fixo esquecido em outro lugar do arquivo — e (2) que um 404 vem com o
// nome do modelo na mensagem de erro, para o próximo bug desse tipo aparecer
// já com a causa no log, sem precisar caçar no corpo da resposta.
// ============================================================================
function stubFetch(handler: typeof fetch): () => void {
  const original = globalThis.fetch;
  globalThis.fetch = handler;
  return () => {
    globalThis.fetch = original;
  };
}

Deno.test('criarChamadorGeminiReal: usa o modelo recebido por parâmetro na URL (nunca hardcoded)', async () => {
  let urlChamada = '';
  const restaurar = stubFetch(((input: RequestInfo | URL) => {
    urlChamada = String(input);
    return Promise.resolve(
      new Response(
        JSON.stringify({ candidates: [{ content: { parts: [{ text: '{}' }] } }] }),
        { status: 200 },
      ),
    );
  }) as typeof fetch);

  try {
    const chamar = criarChamadorGeminiReal('fake-key', 'gemini-1.5-flash');
    await chamar({ base64: 'YQ==', mimeType: 'image/jpeg', systemPrompt: 'x', userText: 'y' });
    assertStringIncludes(urlChamada, '/models/gemini-1.5-flash:generateContent');
  } finally {
    restaurar();
  }
});

Deno.test('criarChamadorGeminiReal: 404 do Gemini vira ErroHttp 502 com o nome do modelo na mensagem', async () => {
  const restaurar = stubFetch((() =>
    Promise.resolve(
      new Response(
        '{"error":{"code":404,"message":"models/gemini-pro-vision is not found"}}',
        { status: 404 },
      ),
    )) as typeof fetch);

  try {
    const chamar = criarChamadorGeminiReal('fake-key', 'gemini-pro-vision');
    let erro: unknown;
    try {
      await chamar({ base64: 'YQ==', mimeType: 'image/jpeg', systemPrompt: 'x', userText: 'y' });
    } catch (e) {
      erro = e;
    }
    assertEquals(erro instanceof Error, true);
    assertStringIncludes((erro as Error).message, 'gemini-pro-vision');
    assertStringIncludes((erro as Error).message, '404');
  } finally {
    restaurar();
  }
});
