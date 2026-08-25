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
  avaliarLeituraBalanca,
  avaliarLeituraPressao,
  avaliarLeituraRotulo,
  calcularPrato,
  createHandler,
  criarChamadorGeminiComFallback,
  criarChamadorGeminiReal,
  encontrarAlimento,
  ErroHttp,
  encontrarMedida,
  normalizarTexto,
  parseRespostaGemini,
  parseRespostaGeminiBalanca,
  parseRespostaGeminiPrato,
  parseRespostaGeminiPressao,
  parseRespostaGeminiRotulo,
  resolverComBuscaSemantica,
  resolverModeloParaTipo,
  type AlimentoCatalogo,
  type AutenticadorLike,
  type BuscaSemanticaLike,
  type CatalogoAlimentosLike,
  type ChamadorEmbedding,
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
// (a.2) parseRespostaGeminiBalanca / avaliarLeituraBalanca (Passo 3)
// ============================================================================
Deno.test('parseRespostaGeminiBalanca: JSON limpo e legível', () => {
  const r = parseRespostaGeminiBalanca(
    '{"legivel":true,"peso_kg":72.4,"confianca":0.95,"possivel_foto_de_tela":false,"motivo":null}',
  );
  assertEquals(r.legivel, true);
  assertEquals(r.pesoKg, 72.4);
});

Deno.test('parseRespostaGeminiBalanca: texto sujo vira ilegível (não lança)', () => {
  const r = parseRespostaGeminiBalanca('desculpe, não consegui ler a balança');
  assertEquals(r.legivel, false);
  assertEquals(r.pesoKg, null);
  assertEquals(r.motivo, 'json_invalido');
});

Deno.test('avaliarLeituraBalanca: leitura boa é aceita e arredondada a 1 casa', () => {
  const a = avaliarLeituraBalanca({
    legivel: true,
    pesoKg: 72.45,
    confianca: 0.9,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, true);
  assertEquals(a.pesoKg, 72.5);
});

Deno.test('avaliarLeituraBalanca: confiança abaixo do piso -> rejeita', () => {
  const a = avaliarLeituraBalanca({
    legivel: true,
    pesoKg: 70,
    confianca: 0.5,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, false);
  assertEquals(a.motivo, 'confianca_baixa');
});

Deno.test('avaliarLeituraBalanca: peso fora da faixa plausível -> rejeita (ex.: erro de casa decimal)', () => {
  const a = avaliarLeituraBalanca({
    legivel: true,
    pesoKg: 705, // provável "70.5" lido sem o ponto
    confianca: 0.9,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, false);
  assertEquals(a.motivo, 'fora_da_faixa');
});

// ============================================================================
// (a.3) parseRespostaGeminiPressao / avaliarLeituraPressao (Passo 3)
// ============================================================================
Deno.test('parseRespostaGeminiPressao: JSON limpo e legível, com pulso', () => {
  const r = parseRespostaGeminiPressao(
    '{"legivel":true,"sistolica_mmhg":120,"diastolica_mmhg":80,"pulso_bpm":72,"confianca":0.9,"possivel_foto_de_tela":false,"motivo":null}',
  );
  assertEquals(r.sistolicaMmhg, 120);
  assertEquals(r.diastolicaMmhg, 80);
  assertEquals(r.pulsoBpm, 72);
});

Deno.test('parseRespostaGeminiPressao: pulso ausente vira null, não derruba os outros campos', () => {
  const r = parseRespostaGeminiPressao(
    '{"legivel":true,"sistolica_mmhg":120,"diastolica_mmhg":80,"pulso_bpm":null,"confianca":0.9,"possivel_foto_de_tela":false,"motivo":null}',
  );
  assertEquals(r.pulsoBpm, null);
  assertEquals(r.sistolicaMmhg, 120);
});

Deno.test('avaliarLeituraPressao: leitura boa com pulso é aceita e arredondada', () => {
  const a = avaliarLeituraPressao({
    legivel: true,
    sistolicaMmhg: 119.6,
    diastolicaMmhg: 79.4,
    pulsoBpm: 71.6,
    confianca: 0.9,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, true);
  assertEquals(a.sistolicaMmhg, 120);
  assertEquals(a.diastolicaMmhg, 79);
  assertEquals(a.pulsoBpm, 72);
});

Deno.test('avaliarLeituraPressao: sem pulso legível ainda aceita sistólica/diastólica (A.6 — não descarta dado bom por campo secundário ausente)', () => {
  const a = avaliarLeituraPressao({
    legivel: true,
    sistolicaMmhg: 120,
    diastolicaMmhg: 80,
    pulsoBpm: null,
    confianca: 0.9,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, true);
  assertEquals(a.pulsoBpm, undefined);
});

Deno.test('avaliarLeituraPressao: sistólica/diastólica ausentes -> rejeita', () => {
  const a = avaliarLeituraPressao({
    legivel: true,
    sistolicaMmhg: null,
    diastolicaMmhg: null,
    pulsoBpm: null,
    confianca: 0.9,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, false);
  assertEquals(a.motivo, 'sem_numero');
});

Deno.test('avaliarLeituraPressao: sistólica <= diastólica -> rejeita como inconsistente', () => {
  const a = avaliarLeituraPressao({
    legivel: true,
    sistolicaMmhg: 80,
    diastolicaMmhg: 120, // invertido — erro de leitura
    pulsoBpm: null,
    confianca: 0.9,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, false);
  assertEquals(a.motivo, 'inconsistente');
});

Deno.test('avaliarLeituraPressao: valores fora da faixa plausível -> rejeita', () => {
  const a = avaliarLeituraPressao({
    legivel: true,
    sistolicaMmhg: 500,
    diastolicaMmhg: 80,
    pulsoBpm: null,
    confianca: 0.9,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, false);
  assertEquals(a.motivo, 'fora_da_faixa');
});

// ============================================================================
// (a.4) parseRespostaGeminiRotulo / avaliarLeituraRotulo (Passo 3)
// ============================================================================
Deno.test('parseRespostaGeminiRotulo: JSON limpo com todos os campos', () => {
  const r = parseRespostaGeminiRotulo(
    '{"legivel":true,"porcao_descricao":"30 g","calorias_kcal":150,"proteinas_g":3,"carboidratos_g":20,"gorduras_g":6,"ingredientes_principais":["farinha de trigo","acucar","oleo de palma"],"confianca":0.9,"possivel_foto_de_tela":false,"motivo":null}',
  );
  assertEquals(r.caloriasKcal, 150);
  assertEquals(r.ingredientesPrincipais, ['farinha de trigo', 'acucar', 'oleo de palma']);
});

Deno.test('parseRespostaGeminiRotulo: ingredientes é capado em MAX_INGREDIENTES_ROTULO (10)', () => {
  const ingredientes = Array.from({ length: 25 }, (_, i) => `ingrediente${i}`);
  const r = parseRespostaGeminiRotulo(
    JSON.stringify({ legivel: true, confianca: 0.9, calorias_kcal: 100, ingredientes_principais: ingredientes }),
  );
  assertEquals(r.ingredientesPrincipais.length, 10);
  assertEquals(r.ingredientesPrincipais[0], 'ingrediente0');
});

Deno.test('parseRespostaGeminiRotulo: campo nutricional ausente no rótulo vira null, não derruba os outros', () => {
  const r = parseRespostaGeminiRotulo(
    '{"legivel":true,"calorias_kcal":150,"confianca":0.9}',
  );
  assertEquals(r.caloriasKcal, 150);
  assertEquals(r.gordurasG, null);
});

Deno.test('avaliarLeituraRotulo: leitura boa é aceita com macros arredondados', () => {
  const a = avaliarLeituraRotulo({
    legivel: true,
    porcaoDescricao: '30 g',
    caloriasKcal: 150.4,
    proteinasG: 3.26,
    carboidratosG: 20,
    gordurasG: 6,
    ingredientesPrincipais: ['acucar'],
    confianca: 0.9,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, true);
  assertEquals(a.caloriasKcal, 150);
  assertEquals(a.proteinasG, 3.3);
});

Deno.test('avaliarLeituraRotulo: legível mas sem nenhum macro numérico -> rejeita (extração não achou nada de verdade)', () => {
  const a = avaliarLeituraRotulo({
    legivel: true,
    porcaoDescricao: null,
    caloriasKcal: null,
    proteinasG: null,
    carboidratosG: null,
    gordurasG: null,
    ingredientesPrincipais: [],
    confianca: 0.9,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, false);
  assertEquals(a.motivo, 'sem_numero');
});

Deno.test('avaliarLeituraRotulo: calorias absurdas (fora do teto de sanidade) -> rejeita', () => {
  const a = avaliarLeituraRotulo({
    legivel: true,
    porcaoDescricao: null,
    caloriasKcal: 50000,
    proteinasG: null,
    carboidratosG: null,
    gordurasG: null,
    ingredientesPrincipais: [],
    confianca: 0.9,
    possivelFotoDeTela: false,
    motivo: null,
  });
  assertEquals(a.aceita, false);
  assertEquals(a.motivo, 'fora_da_faixa');
});

// ============================================================================
// (a.5) Model Routing — resolverModeloParaTipo (ver bloco no topo do arquivo)
// ============================================================================
Deno.test('resolverModeloParaTipo: OCR simples (glicosímetro/balança/pressão) usa o nível LITE', () => {
  assertEquals(resolverModeloParaTipo('glicosimetro'), 'gemini-flash-lite-latest');
  assertEquals(resolverModeloParaTipo('balanca'), 'gemini-flash-lite-latest');
  assertEquals(resolverModeloParaTipo('pressaoArterial'), 'gemini-flash-lite-latest');
});

// RELATÓRIO 20260825_0005 — foto do prato migrou de CORE pra LITE (achado
// em investigação ao vivo do RELATÓRIO 20260825_0004: CORE com
// disponibilidade instável no free tier, LITE nunca falhou nem com
// imagem real). Rótulo nutricional continua em CORE (OCR de macros
// impressos — dígito errado importa mais do que "esqueceu uma azeitona
// no prato").
Deno.test('resolverModeloParaTipo: foto do prato usa o nível LITE (disponibilidade > raciocínio de cena)', () => {
  assertEquals(resolverModeloParaTipo('pratoRefeicao'), 'gemini-flash-lite-latest');
});

Deno.test('resolverModeloParaTipo: rótulo nutricional (OCR estruturado) usa o nível CORE', () => {
  assertEquals(resolverModeloParaTipo('rotulo'), 'gemini-flash-latest');
});

Deno.test('resolverModeloParaTipo: tipo desconhecido cai em CORE por padrão (mais seguro que LITE)', () => {
  assertEquals(resolverModeloParaTipo('tipo-futuro-nao-classificado'), 'gemini-flash-latest');
});

Deno.test('resolverModeloParaTipo: GEMINI_MODEL_LITE sobrescreve o padrão do nível lite', () => {
  Deno.env.set('GEMINI_MODEL_LITE', 'modelo-lite-customizado');
  try {
    assertEquals(resolverModeloParaTipo('glicosimetro'), 'modelo-lite-customizado');
  } finally {
    Deno.env.delete('GEMINI_MODEL_LITE');
  }
});

Deno.test('resolverModeloParaTipo: GEMINI_MODEL_CORE sobrescreve o padrão do nível core', () => {
  Deno.env.set('GEMINI_MODEL_CORE', 'modelo-core-customizado');
  try {
    // 'rotulo' é o único tipo em CORE desde a migração de pratoRefeicao
    // pra LITE (RELATÓRIO 20260825_0005).
    assertEquals(resolverModeloParaTipo('rotulo'), 'modelo-core-customizado');
  } finally {
    Deno.env.delete('GEMINI_MODEL_CORE');
  }
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
  // feijão não tem "colher de sopa" cadastrada — cai no fallback do F46
  // ("FIX 31/jul": melhor usar a medida que o alimento TEM do que deixar
  // cair em não reconhecido), mas o fallback continua escopado ao PRÓPRIO
  // feijão (sua única medida, concha média = 80g) — nunca pega emprestado
  // o peso da colher de sopa do arroz (25g).
  const medidaFeijao = encontrarMedida(feijao, 'colher de sopa');
  assertEquals(medidaFeijao?.medida, 'concha média');
  assertEquals(medidaFeijao?.gramas, 80);
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

Deno.test('calcularPrato: medida não cadastrada mas o alimento tem outra -> resolve pelo fallback (F46), não vira não-reconhecido', () => {
  const r = calcularPrato(
    [itemExtraido({ nome: 'feijao', medida: 'xícara' })], // feijão só tem "concha média" no catálogo de teste
    CATALOGO_TESTE,
  );
  // F46 ("FIX 31/jul", `encontrarMedida`): melhor usar a única medida
  // cadastrada do alimento do que descartar o item inteiro — "xícara" cai
  // no fallback pra "concha média" (a única medida do feijão), não vira
  // itensNaoReconhecidos.
  assertEquals(r.itensNaoReconhecidos.length, 0);
  assertEquals(r.itens.length, 1);
  // `medida` no item calculado é o texto ORIGINAL pedido ("xícara") — só
  // o peso (`gramasEstimados`) reflete a medida real usada no fallback
  // (concha média, a única cadastrada do feijão).
  assertEquals(r.itens[0].medida, 'xícara');
  assertEquals(r.itens[0].gramasEstimados, 160); // quantidade padrão de itemExtraido() é 2: 2 conchas médias = 160g
});

Deno.test('calcularPrato: medida vazia (único caso em que encontrarMedida ainda retorna null) vai para itensNaoReconhecidos', () => {
  const r = calcularPrato([itemExtraido({ nome: 'feijao', medida: '' })], CATALOGO_TESTE);
  assertEquals(r.itens.length, 0);
  assertEquals(r.itensNaoReconhecidos[0].motivo, 'medida_nao_encontrada');
});

Deno.test('calcularPrato: prato sem itens dá totais zerados (não é erro)', () => {
  const r = calcularPrato([], CATALOGO_TESTE);
  assertEquals(r.itens.length, 0);
  assertEquals(r.totais.calorias, 0);
});

// ============================================================================
// (b.2) resolverComBuscaSemantica — fallback do casamento léxico (Missão F45)
// ============================================================================
function naoReconhecido(
  over: Partial<{ nome: string; medida: string; quantidade: number; confianca: number }> = {},
): { nome: string; medida: string; quantidade: number; confianca: number; motivo: 'alimento_nao_encontrado' } {
  return {
    nome: 'bifinho',
    medida: 'colher de sopa',
    quantidade: 2,
    confianca: 0.7,
    motivo: 'alimento_nao_encontrado',
    ...over,
  };
}

function chamadorEmbeddingFixo(vetor: number[] = [0.1]): ChamadorEmbedding {
  return () => Promise.resolve(vetor);
}

Deno.test('resolverComBuscaSemantica: sem match nenhum -> item continua não reconhecido', async () => {
  const semMatch: BuscaSemanticaLike = { buscar: () => Promise.resolve([]) };
  const r = await resolverComBuscaSemantica(
    [naoReconhecido()],
    CATALOGO_TESTE,
    chamadorEmbeddingFixo(),
    semMatch,
  );
  assertEquals(r.resolvidos.length, 0);
  assertEquals(r.aindaNaoReconhecidos.length, 1);
  assertEquals(r.aindaNaoReconhecidos[0].motivo, 'alimento_nao_encontrado');
});

Deno.test('resolverComBuscaSemantica: match encontrado e medida existe -> resolve com origem semântica', async () => {
  const comMatch: BuscaSemanticaLike = {
    buscar: () => Promise.resolve([{ id: 'arroz-id', similarity: 0.81 }]),
  };
  const r = await resolverComBuscaSemantica(
    [naoReconhecido({ nome: 'bifinho', medida: 'colher de sopa', quantidade: 2 })],
    CATALOGO_TESTE,
    chamadorEmbeddingFixo(),
    comMatch,
  );
  assertEquals(r.aindaNaoReconhecidos.length, 0);
  assertEquals(r.resolvidos.length, 1);
  const item = r.resolvidos[0];
  assertEquals(item.alimentoCasado, 'Arroz, branco, cozido');
  assertEquals(item.nomeIdentificado, 'bifinho');
  assertEquals(item.origemCasamento, 'semantico');
  assertEquals(item.similaridade, 0.81);
  assertEquals(item.gramasEstimados, 50);
  assertEquals(item.calorias, 64);
});

Deno.test('resolverComBuscaSemantica: id devolvido pela RPC não existe mais no catálogo carregado -> defensivo, não quebra', async () => {
  const idFantasma: BuscaSemanticaLike = {
    buscar: () => Promise.resolve([{ id: 'id-que-nao-existe', similarity: 0.9 }]),
  };
  const r = await resolverComBuscaSemantica(
    [naoReconhecido()],
    CATALOGO_TESTE,
    chamadorEmbeddingFixo(),
    idFantasma,
  );
  assertEquals(r.resolvidos.length, 0);
  assertEquals(r.aindaNaoReconhecidos.length, 1);
});

Deno.test('resolverComBuscaSemantica: match acha o alimento e a medida sem cadastro cai no fallback (F46), não fica não-reconhecido', async () => {
  const feijaoMatch: BuscaSemanticaLike = {
    buscar: () => Promise.resolve([{ id: 'feijao-id', similarity: 0.77 }]),
  };
  const r = await resolverComBuscaSemantica(
    [naoReconhecido({ nome: 'feijaozinho', medida: 'xícara' })], // feijão só tem "concha média"
    CATALOGO_TESTE,
    chamadorEmbeddingFixo(),
    feijaoMatch,
  );
  assertEquals(r.aindaNaoReconhecidos.length, 0);
  assertEquals(r.resolvidos.length, 1);
  assertEquals(r.resolvidos[0].alimentoCasado, 'Feijão, carioca, cozido');
  // `medida` é o texto ORIGINAL pedido ("xícara") — só o peso reflete a
  // medida real usada no fallback (concha média).
  assertEquals(r.resolvidos[0].medida, 'xícara');
  assertEquals(r.resolvidos[0].gramasEstimados, 160); // quantidade padrão de naoReconhecido() é 2: 2 conchas médias = 160g
});

Deno.test('resolverComBuscaSemantica: medida vazia (guard defensivo, exigido pelo TypeScript) -> aindaNaoReconhecidos', async () => {
  const feijaoMatch: BuscaSemanticaLike = {
    buscar: () => Promise.resolve([{ id: 'feijao-id', similarity: 0.77 }]),
  };
  const r = await resolverComBuscaSemantica(
    [naoReconhecido({ nome: 'feijaozinho', medida: '' })],
    CATALOGO_TESTE,
    chamadorEmbeddingFixo(),
    feijaoMatch,
  );
  assertEquals(r.resolvidos.length, 0);
  assertEquals(r.aindaNaoReconhecidos.length, 1);
});

Deno.test('resolverComBuscaSemantica: item com motivo medida_nao_encontrada nunca tenta busca semântica', async () => {
  let chamou = false;
  const buscaEspiada: BuscaSemanticaLike = {
    buscar: () => {
      chamou = true;
      return Promise.resolve([]);
    },
  };
  const r = await resolverComBuscaSemantica(
    [{ ...naoReconhecido(), motivo: 'medida_nao_encontrada' as const }],
    CATALOGO_TESTE,
    chamadorEmbeddingFixo(),
    buscaEspiada,
  );
  assertEquals(chamou, false);
  assertEquals(r.aindaNaoReconhecidos.length, 1);
  assertEquals(r.aindaNaoReconhecidos[0].motivo, 'medida_nao_encontrada');
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

// RELATÓRIO 20260824_0003 — Método 1 (descritivo): o corpo é a descrição
// digitada em UTF-8, não binário — diferente de `reqComImagem`.
function reqComTexto(headers: Record<string, string>, texto: string): Request {
  return new Request('http://localhost/extract-metric-photo', {
    method: 'POST',
    headers: { Authorization: 'Bearer x', ...headers },
    body: new TextEncoder().encode(texto),
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

// A antiga "tipo conhecido mas ainda não implementado -> 422" (usava
// 'balanca' como exemplo) não existe mais como caso possível: todo tipo em
// TIPOS_CONHECIDOS tem extrator implementado agora (Passo 3). O caminho
// 422 `extrator_nao_implementado` continua existindo no código para um
// tipo futuro que seja adicionado a TIPOS_CONHECIDOS antes do extrator
// correspondente — só não há, hoje, nenhum valor de X-Tipo-Aparelho que
// exercite esse caminho.

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
// (c.2) Handler HTTP — balanca (Passo 3)
// ============================================================================
Deno.test('handler: balança, leitura boa -> 200 com peso_kg', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo(
      '{"legivel":true,"peso_kg":72.4,"confianca":0.9,"possivel_foto_de_tela":false,"motivo":null}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'balanca' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.peso_kg, 72.4);
  assertEquals(body.tipo_captura, 'balanca');
});

Deno.test('handler: balança, leitura ilegível -> 422', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo(
      '{"legivel":false,"peso_kg":null,"confianca":0.1,"possivel_foto_de_tela":false,"motivo":"visor apagado"}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'balanca' }));

  assertEquals(res.status, 422);
  const body = await res.json();
  assertEquals(body.error, 'leitura_ilegivel');
});

Deno.test('handler: balança usa o modelo LITE (roteamento por complexidade)', async () => {
  let urlChamada = '';
  const restaurar = stubFetch(((input: RequestInfo | URL) => {
    urlChamada = String(input);
    return Promise.resolve(
      new Response(
        JSON.stringify({
          candidates: [
            {
              content: {
                parts: [
                  {
                    text: '{"legivel":true,"peso_kg":70,"confianca":0.9,"possivel_foto_de_tela":false,"motivo":null}',
                  },
                ],
              },
            },
          ],
        }),
        { status: 200 },
      ),
    );
  }) as typeof fetch);

  try {
    Deno.env.set('GEMINI_API_KEY', 'fake-key');
    const res = await createHandler({ autenticador: AUTH_OK })(
      reqComImagem({ 'X-Tipo-Aparelho': 'balanca' }),
    );
    assertEquals(res.status, 200);
    assertStringIncludes(urlChamada, 'gemini-flash-lite-latest:generateContent');
  } finally {
    Deno.env.delete('GEMINI_API_KEY');
    restaurar();
  }
});

// ============================================================================
// (c.3) Handler HTTP — pressaoArterial (Passo 3)
// ============================================================================
Deno.test('handler: pressão, leitura boa -> 200 com sistólica/diastólica/fc_repouso', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo(
      '{"legivel":true,"sistolica_mmhg":120,"diastolica_mmhg":80,"pulso_bpm":72,"confianca":0.9,"possivel_foto_de_tela":false,"motivo":null}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pressaoArterial' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.pressao_sistolica, 120);
  assertEquals(body.pressao_diastolica, 80);
  assertEquals(body.fc_repouso, 72);
  assertEquals(body.tipo_captura, 'pressaoArterial');
});

Deno.test('handler: pressão sem pulso legível -> 200 sem a chave fc_repouso (nunca null/zero inventado)', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo(
      '{"legivel":true,"sistolica_mmhg":120,"diastolica_mmhg":80,"pulso_bpm":null,"confianca":0.9,"possivel_foto_de_tela":false,"motivo":null}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pressaoArterial' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals('fc_repouso' in body, false);
});

Deno.test('handler: pressão, leitura ilegível -> 422', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo(
      '{"legivel":false,"sistolica_mmhg":null,"diastolica_mmhg":null,"pulso_bpm":null,"confianca":0.1,"possivel_foto_de_tela":false,"motivo":"reflexo no visor"}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pressaoArterial' }));

  assertEquals(res.status, 422);
});

// ============================================================================
// (c.4) Handler HTTP — rotulo (Passo 3)
// ============================================================================
Deno.test('handler: rótulo, leitura boa -> 200 com macros e ingredientes', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo(
      '{"legivel":true,"porcao_descricao":"30 g","calorias_kcal":150,"proteinas_g":3,"carboidratos_g":20,"gorduras_g":6,"ingredientes_principais":["acucar","farinha de trigo"],"confianca":0.9,"possivel_foto_de_tela":false,"motivo":null}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'rotulo' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.calorias_kcal, 150);
  assertEquals(body.ingredientes_principais, ['acucar', 'farinha de trigo']);
  assertEquals(body.tipo_captura, 'rotulo');
});

Deno.test('handler: rótulo, leitura ilegível -> 422', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    chamarGemini: geminiRespondendo(
      '{"legivel":false,"confianca":0.1,"possivel_foto_de_tela":false,"motivo":"nao e um rotulo nutricional","ingredientes_principais":[]}',
    ),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'rotulo' }));

  assertEquals(res.status, 422);
});

Deno.test('handler: rótulo usa o modelo CORE (roteamento por complexidade)', async () => {
  let urlChamada = '';
  const restaurar = stubFetch(((input: RequestInfo | URL) => {
    urlChamada = String(input);
    return Promise.resolve(
      new Response(
        JSON.stringify({
          candidates: [
            {
              content: {
                parts: [{ text: '{"legivel":true,"calorias_kcal":100,"confianca":0.9,"possivel_foto_de_tela":false,"motivo":null}' }],
              },
            },
          ],
        }),
        { status: 200 },
      ),
    );
  }) as typeof fetch);

  try {
    Deno.env.set('GEMINI_API_KEY', 'fake-key');
    const res = await createHandler({ autenticador: AUTH_OK })(
      reqComImagem({ 'X-Tipo-Aparelho': 'rotulo' }),
    );
    assertEquals(res.status, 200);
    assertStringIncludes(urlChamada, 'gemini-flash-latest:generateContent');
  } finally {
    Deno.env.delete('GEMINI_API_KEY');
    restaurar();
  }
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

// Busca semântica falsa: injetável tanto para "nenhum match" (fica em
// itens_nao_reconhecidos mesmo depois de tentar) quanto para "achou X"
// (resolve o item). `chamarEmbedding` falso nunca toca a rede — devolve um
// vetor fixo, o conteúdo não importa porque quem decide o casamento é
// `buscaSemantica.buscar`, também falso.
function chamarEmbeddingFalso(): ChamadorEmbedding {
  return () => Promise.resolve(new Array(768).fill(0.01));
}

const BUSCA_SEMANTICA_SEM_MATCH: BuscaSemanticaLike = {
  buscar: () => Promise.resolve([]),
};

function buscaSemanticaEncontrando(id: string, similarity: number): BuscaSemanticaLike {
  return { buscar: () => Promise.resolve([{ id, similarity }]) };
}

Deno.test('handler: alimento fora do catálogo (léxico E semântico) não derruba a requisição — vai para itens_nao_reconhecidos', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: geminiRespondendo(
      '{"itens":[{"nome":"lasanha","medida":"fatia","quantidade":1,"confianca":0.7}],"possivel_foto_de_tela":false}',
    ),
    chamarEmbedding: chamarEmbeddingFalso(),
    buscaSemantica: BUSCA_SEMANTICA_SEM_MATCH,
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pratoRefeicao' }));

  assertEquals(res.status, 200); // A.6: não é erro, o usuário decide depois (Passo 3)
  const body = await res.json();
  assertEquals(body.itens.length, 0);
  assertEquals(body.itens_nao_reconhecidos.length, 1);
  assertEquals(body.itens_nao_reconhecidos[0].motivo, 'alimento_nao_encontrado');
});

Deno.test('handler: casamento léxico falha mas busca semântica acha o alimento — item é calculado normalmente', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: geminiRespondendo(
      '{"itens":[{"nome":"bifinho","medida":"colher de sopa","quantidade":2,"confianca":0.7}],"possivel_foto_de_tela":false}',
    ),
    chamarEmbedding: chamarEmbeddingFalso(),
    // "bifinho" não bate com nada de CATALOGO_TESTE por alias/substring —
    // só a busca semântica (falsa aqui) resolve, apontando pro arroz-id
    // (escolha arbitrária de teste; o que importa é provar o fluxo).
    buscaSemantica: buscaSemanticaEncontrando('arroz-id', 0.81),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pratoRefeicao' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.itens.length, 1);
  assertEquals(body.itens_nao_reconhecidos.length, 0);
  const item = body.itens[0];
  assertEquals(item.nome, 'Arroz, branco, cozido');
  assertEquals(item.nome_identificado, 'bifinho');
  assertEquals(item.origem_casamento, 'semantico');
  assertEquals(item.similaridade, 0.81);
  // Mesma regra de três de sempre: 2 colheres de sopa = 50g de arroz.
  assertEquals(item.gramas_estimados, 50);
  assertEquals(item.calorias, 64);
  assertEquals(body.totais.calorias, 64);
});

Deno.test('handler: busca semântica acha o alimento e a medida sem cadastro cai no fallback (F46) — item entra normal, não em itens_nao_reconhecidos', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: geminiRespondendo(
      // "xícara" não está cadastrada nas medidas do feijão em CATALOGO_TESTE
      // — cai no fallback pra "concha média" (F46, "FIX 31/jul"), a única
      // medida cadastrada do feijão.
      '{"itens":[{"nome":"feijaozinho","medida":"xícara","quantidade":1,"confianca":0.7}],"possivel_foto_de_tela":false}',
    ),
    chamarEmbedding: chamarEmbeddingFalso(),
    buscaSemantica: buscaSemanticaEncontrando('feijao-id', 0.77),
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pratoRefeicao' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.itens_nao_reconhecidos.length, 0);
  assertEquals(body.itens.length, 1);
  assertEquals(body.itens[0].nome, 'Feijão, carioca, cozido');
  // `medida` é o texto ORIGINAL pedido ("xícara") — só o peso reflete a
  // medida real usada no fallback (concha média).
  assertEquals(body.itens[0].medida, 'xícara');
  assertEquals(body.itens[0].gramas_estimados, 80);
});

Deno.test('handler: tudo casa por alias — busca semântica nunca é chamada (caminho comum fica barato)', async () => {
  let chamouEmbedding = false;
  let chamouBusca = false;

  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: geminiRespondendo(
      '{"itens":[{"nome":"arroz","medida":"colher de sopa","quantidade":2,"confianca":0.9}],"possivel_foto_de_tela":false}',
    ),
    chamarEmbedding: () => {
      chamouEmbedding = true;
      return Promise.resolve(new Array(768).fill(0));
    },
    buscaSemantica: {
      buscar: () => {
        chamouBusca = true;
        return Promise.resolve([]);
      },
    },
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pratoRefeicao' }));

  assertEquals(res.status, 200);
  assertEquals(chamouEmbedding, false);
  assertEquals(chamouBusca, false);
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
// (d.2) Handler HTTP — Registro de Refeição por TEXTO e ÁUDIO (RELATÓRIO
// 20260824_0003, Documento Mestre — 4 métodos de captura). Mesmo cálculo/
// casamento de `pratoRefeicao` (não reduplicado) — só a entrada muda.
// ============================================================================

Deno.test('handler: prato por TEXTO reconhecido -> 200 com macros calculados pelo backend', async () => {
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: geminiRespondendo(
      '{"itens":[{"nome":"arroz","medida":"colher de sopa","quantidade":2,"confianca":0.9}]}',
    ),
  })(reqComTexto({ 'X-Tipo-Aparelho': 'pratoRefeicaoTexto' }, 'arroz 2 colheres'));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.tipo_captura, 'pratoRefeicaoTexto');
  assertEquals(body.itens.length, 1);
  assertEquals(body.itens[0].nome, 'Arroz, branco, cozido');
  assertEquals(body.itens[0].calorias, 64);
});

Deno.test('handler: prato por TEXTO com corpo vazio -> 400', async () => {
  const res = await createHandler({ autenticador: AUTH_OK, catalogoAlimentos: CATALOGO_FALSO })(
    reqComTexto({ 'X-Tipo-Aparelho': 'pratoRefeicaoTexto' }, '   '),
  );
  assertEquals(res.status, 400);
});

Deno.test('handler: prato por TEXTO nunca manda inlineData pro Gemini (sem imagem/áudio)', async () => {
  let recebeuBase64 = false;
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: (params) => {
      recebeuBase64 = params.base64 !== undefined;
      assertStringIncludes(params.userText, 'arroz e feijão');
      return Promise.resolve('{"itens":[]}');
    },
  })(reqComTexto({ 'X-Tipo-Aparelho': 'pratoRefeicaoTexto' }, 'arroz e feijão'));

  assertEquals(res.status, 200);
  assertEquals(recebeuBase64, false);
});

Deno.test('handler: prato por TEXTO usa o modelo LITE (nível de complexidade)', async () => {
  let urlChamada = '';
  const restaurar = stubFetch(((input: RequestInfo | URL) => {
    urlChamada = String(input);
    return Promise.resolve(
      new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: '{"itens":[]}' }] } }] }), { status: 200 }),
    );
  }) as typeof fetch);

  try {
    Deno.env.set('GEMINI_API_KEY', 'fake-key');
    const res = await createHandler({ autenticador: AUTH_OK, catalogoAlimentos: CATALOGO_FALSO })(
      reqComTexto({ 'X-Tipo-Aparelho': 'pratoRefeicaoTexto' }, 'arroz'),
    );
    assertEquals(res.status, 200);
    assertStringIncludes(urlChamada, 'gemini-flash-lite-latest:generateContent');
  } finally {
    Deno.env.delete('GEMINI_API_KEY');
    restaurar();
  }
});

Deno.test('handler: prato por ÁUDIO reconhecido -> 200, áudio manda inlineData (nunca gravado)', async () => {
  let mimeRecebido: string | undefined;
  const res = await createHandler({
    autenticador: AUTH_OK,
    catalogoAlimentos: CATALOGO_FALSO,
    chamarGemini: (params) => {
      mimeRecebido = params.mimeType;
      return Promise.resolve(
        '{"itens":[{"nome":"arroz","medida":"colher de sopa","quantidade":2,"confianca":0.9}]}',
      );
    },
  })(reqComImagem({ 'X-Tipo-Aparelho': 'pratoRefeicaoAudio', 'X-Image-Mime': 'audio/mp4' }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.tipo_captura, 'pratoRefeicaoAudio');
  assertEquals(body.itens[0].calorias, 64);
  assertEquals(mimeRecebido, 'audio/mp4');
});

Deno.test('resolverModeloParaTipo: registro de refeição por texto/áudio usa o nível LITE', () => {
  assertEquals(resolverModeloParaTipo('pratoRefeicaoTexto'), 'gemini-flash-lite-latest');
  assertEquals(resolverModeloParaTipo('pratoRefeicaoAudio'), 'gemini-flash-lite-latest');
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

// RELATÓRIO 20260824_0001 — achado real em device: 503 "high demand" do
// Gemini (modelo CORE) virava 502 definitivo na hora, sem nenhuma
// tentativa nova — mesmo erro transitório batido pela curadoria em massa
// do catálogo na véspera (RELATÓRIO 20260823_0004).
Deno.test('criarChamadorGeminiReal: 503 transitório retenta e devolve sucesso na 2ª tentativa', async () => {
  let chamadas = 0;
  const restaurar = stubFetch((() => {
    chamadas++;
    if (chamadas === 1) {
      return Promise.resolve(
        new Response('{"error":{"code":503,"message":"high demand"}}', { status: 503 }),
      );
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({ candidates: [{ content: { parts: [{ text: '{"ok":true}' }] } }] }),
        { status: 200 },
      ),
    );
  }) as typeof fetch);

  try {
    const chamar = criarChamadorGeminiReal('fake-key', 'gemini-flash-latest');
    const texto = await chamar({ base64: 'YQ==', mimeType: 'image/jpeg', systemPrompt: 'x', userText: 'y' });
    assertEquals(texto, '{"ok":true}');
    assertEquals(chamadas, 2);
  } finally {
    restaurar();
  }
});

// RELATÓRIO 20260824_0002 — CORREÇÃO DA CORREÇÃO: 429 é cota
// (`RESOURCE_EXHAUSTED`, geralmente diária no free tier — confirmado
// contra a chave real do projeto nesta tarefa), NUNCA instabilidade
// transitória. Retentar em segundos não ajuda uma cota diária — só
// desperdiça tempo e cota. Comportamento correto: falha na 1ª tentativa,
// sem sleep nenhum (ao contrário do 503, que continua retentando).
Deno.test('criarChamadorGeminiReal: 429 (cota) falha na 1ª tentativa, sem retry', async () => {
  let chamadas = 0;
  const restaurar = stubFetch((() => {
    chamadas++;
    return Promise.resolve(
      new Response(
        '{"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"quota exceeded"}}',
        { status: 429 },
      ),
    );
  }) as typeof fetch);

  try {
    const chamar = criarChamadorGeminiReal('fake-key', 'gemini-flash-latest');
    let erro: unknown;
    try {
      await chamar({ base64: 'YQ==', mimeType: 'image/jpeg', systemPrompt: 'x', userText: 'y' });
    } catch (e) {
      erro = e;
    }
    assertEquals(erro instanceof Error, true);
    assertStringIncludes((erro as Error).message, '429');
    assertEquals((erro as ErroHttp).status, 429);
    assertEquals(chamadas, 1); // nenhum retry — cota não se resolve em segundos
  } finally {
    restaurar();
  }
});

Deno.test('criarChamadorGeminiComFallback: cota no modelo primário cai pro fallback e devolve sucesso', async () => {
  const modelosChamados: string[] = [];
  const restaurar = stubFetch(((input: RequestInfo | URL) => {
    const url = String(input);
    if (url.includes('/models/gemini-flash-latest:')) {
      modelosChamados.push('gemini-flash-latest');
      return Promise.resolve(
        new Response('{"error":{"code":429,"status":"RESOURCE_EXHAUSTED"}}', { status: 429 }),
      );
    }
    modelosChamados.push('gemini-flash-lite-latest');
    return Promise.resolve(
      new Response(
        JSON.stringify({ candidates: [{ content: { parts: [{ text: '{"do_fallback":true}' }] } }] }),
        { status: 200 },
      ),
    );
  }) as typeof fetch);

  try {
    const chamar = criarChamadorGeminiComFallback('fake-key', 'gemini-flash-latest', 'gemini-flash-lite-latest');
    const texto = await chamar({ base64: 'YQ==', mimeType: 'image/jpeg', systemPrompt: 'x', userText: 'y' });
    assertEquals(texto, '{"do_fallback":true}');
    assertEquals(modelosChamados, ['gemini-flash-latest', 'gemini-flash-lite-latest']);
  } finally {
    restaurar();
  }
});

Deno.test('criarChamadorGeminiComFallback: sem fallback configurado (null), cota propaga direto', async () => {
  let chamadas = 0;
  const restaurar = stubFetch((() => {
    chamadas++;
    return Promise.resolve(
      new Response('{"error":{"code":429,"status":"RESOURCE_EXHAUSTED"}}', { status: 429 }),
    );
  }) as typeof fetch);

  try {
    const chamar = criarChamadorGeminiComFallback('fake-key', 'gemini-flash-lite-latest', null);
    let erro: unknown;
    try {
      await chamar({ base64: 'YQ==', mimeType: 'image/jpeg', systemPrompt: 'x', userText: 'y' });
    } catch (e) {
      erro = e;
    }
    assertEquals((erro as ErroHttp).status, 429);
    assertEquals(chamadas, 1);
  } finally {
    restaurar();
  }
});

// RELATÓRIO 20260825_0003 — substitui o teste antigo ("5xx esgotado nunca
// tenta o fallback"): achado real em device (foto ainda dava
// TimeoutException mesmo com os fixes de 20260824) mostrou que restringir
// o fallback só a cota deixava o CORE bater as 3 tentativas inteiras
// contra si mesmo (cada uma uma chamada de visão inteira) antes de
// desistir — tempo demais, e cota demais no free tier (20/dia). Agora
// QUALQUER falha do primário tenta o fallback, se configurado — e o
// primário ganha só 1 tentativa quando existe fallback (não retenta
// contra si mesmo, poupa cota e tempo).
Deno.test('criarChamadorGeminiComFallback: 5xx esgotado no primário cai pro fallback com sucesso (mesmo espírito da cota)', async () => {
  const modelosChamados: string[] = [];
  const restaurar = stubFetch(((input: RequestInfo | URL) => {
    const url = String(input);
    if (url.includes('/models/gemini-flash-latest:')) {
      modelosChamados.push('gemini-flash-latest');
      return Promise.resolve(new Response('{"error":{"code":503}}', { status: 503 }));
    }
    modelosChamados.push('gemini-flash-lite-latest');
    return Promise.resolve(
      new Response(
        JSON.stringify({ candidates: [{ content: { parts: [{ text: '{"do_fallback":true}' }] } }] }),
        { status: 200 },
      ),
    );
  }) as typeof fetch);

  try {
    const chamar = criarChamadorGeminiComFallback('fake-key', 'gemini-flash-latest', 'gemini-flash-lite-latest');
    const texto = await chamar({ base64: 'YQ==', mimeType: 'image/jpeg', systemPrompt: 'x', userText: 'y' });
    assertEquals(texto, '{"do_fallback":true}');
    // Só 1 chamada no primário (não retenta contra si mesmo quando existe
    // fallback — poupa cota do modelo restrito) + 1 no fallback.
    assertEquals(modelosChamados, ['gemini-flash-latest', 'gemini-flash-lite-latest']);
  } finally {
    restaurar();
  }
});

Deno.test('criarChamadorGeminiComFallback: primário E fallback falham (5xx) -> propaga o erro do fallback', async () => {
  let chamadasPrimario = 0;
  let chamadasFallback = 0;
  const restaurar = stubFetch(((input: RequestInfo | URL) => {
    const url = String(input);
    if (url.includes('/models/gemini-flash-latest:')) {
      chamadasPrimario++;
      return Promise.resolve(new Response('{"error":{"code":503}}', { status: 503 }));
    }
    chamadasFallback++;
    return Promise.resolve(new Response('{"error":{"code":503}}', { status: 503 }));
  }) as typeof fetch);

  try {
    const chamar = criarChamadorGeminiComFallback('fake-key', 'gemini-flash-latest', 'gemini-flash-lite-latest');
    let erro: unknown;
    try {
      await chamar({ base64: 'YQ==', mimeType: 'image/jpeg', systemPrompt: 'x', userText: 'y' });
    } catch (e) {
      erro = e;
    }
    assertEquals((erro as ErroHttp).status, 502);
    assertEquals(chamadasPrimario, 1); // não retenta o primário — já tinha fallback
    // Fallback é o "último recurso" — mantém o orçamento cheio de retry
    // (MAX_TENTATIVAS_VISAO) já que não sobra mais ninguém pra tentar.
    assertEquals(chamadasFallback, 3);
  } finally {
    restaurar();
  }
});

Deno.test('criarChamadorGeminiComFallback: sem fallback (null), 5xx retenta o orçamento cheio (último recurso)', async () => {
  let chamadas = 0;
  const restaurar = stubFetch((() => {
    chamadas++;
    return Promise.resolve(new Response('{"error":{"code":503}}', { status: 503 }));
  }) as typeof fetch);

  try {
    const chamar = criarChamadorGeminiComFallback('fake-key', 'gemini-flash-lite-latest', null);
    let erro: unknown;
    try {
      await chamar({ base64: 'YQ==', mimeType: 'image/jpeg', systemPrompt: 'x', userText: 'y' });
    } catch (e) {
      erro = e;
    }
    assertEquals((erro as ErroHttp).status, 502);
    // Sem fallback pra cair, o próprio primário é o "último recurso" —
    // mantém o orçamento cheio de retry, não só 1 tentativa.
    assertEquals(chamadas, 3);
  } finally {
    restaurar();
  }
});
