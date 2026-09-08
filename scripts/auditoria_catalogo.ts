/**
 * RELATÓRIO 20260902_0003 (Regra 23 — Falhar Visível, Regra 26 — Curadoria
 * Humana): auditoria 100% READ-ONLY do catálogo (`alimentos_referencia` +
 * `alimentos_medidas_caseiras`) — nenhum UPDATE/DELETE/INSERT em lugar
 * nenhum deste arquivo. Não decide nada sozinho: só levanta e prioriza os
 * achados para revisão manual do fundador (Regra 26).
 *
 * Motivado pelo bug confirmado em produção: o alias genérico "suco"
 * (cadastrado sozinho, sem contexto, em 3 linhas de suco de laranja/uva)
 * faz `encontrarAlimento` casar "suco de abacaxi" com suco de LARANJA por
 * substring — sem erro, sem aviso, calorias/macros errados silenciosamente
 * (achado do RELATÓRIO 20260902_0002).
 *
 * 3 partes:
 *   1. Colisão de aliases — reproduz `encontrarAlimento` (importado direto
 *      de `supabase/functions/extract-metric-photo/index.ts`, não uma
 *      reimplementação) contra o alias/nome de CADA alimento consigo mesmo
 *      — se o alimento não encontra A SI PRÓPRIO, é prova concreta de que
 *      outro alias mais curto está roubando o match. Complementado por um
 *      levantamento de aliases de 1 palavra só (risco latente, mesmo sem
 *      colisão comprovada ainda).
 *   2. Cobertura de medidas — líquidos sem nenhuma medida de recipiente
 *      plausível (copo/xícara/taça/lata/etc. — "ml"/"litro" já são
 *      universais via FATORES_UNIDADE_BRUTA, não entram nesta conta);
 *      itens de unidade/fatia sem NENHUMA medida cadastrada.
 *   3. Cruzamento — alimentos que aparecem nas duas listas (risco máximo).
 *
 * Uso:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *     deno run --allow-net --allow-env --allow-read scripts/auditoria_catalogo.ts
 *
 * Mesma service role key que os outros scripts em scripts/ e
 * web_painel/scripts/ (guardada em web_painel/.env.local, nunca commitada)
 * — a policy de SELECT das duas tabelas é `to authenticated`, não `anon`.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import {
  encontrarAlimento,
  type AlimentoCatalogo,
} from '../supabase/functions/extract-metric-photo/index.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('❌ Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente.');
  Deno.exit(1);
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY);

// Mesma normalização de `index.ts` (duplicada de propósito — script
// descartável de auditoria, não vale importar uma função `not exported`).
function normalizarTexto(texto: string): string {
  return texto
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .trim();
}

interface LinhaAlimento {
  id: string;
  nome_taco: string;
  aliases: string[] | null;
  calorias_kcal_100g: number;
  proteinas_g_100g: number;
  carboidratos_g_100g: number;
  gorduras_g_100g: number;
  categoria_consumo: string | null;
  unidade_medida_padrao: string | null;
  medida_padrao_nome: string | null;
  medida_padrao_qtd: number | null;
}

interface LinhaMedida {
  alimento_id: string;
  medida: string;
  gramas: number;
}

console.log('📥 Baixando alimentos_referencia + alimentos_medidas_caseiras (1 leitura cada)...\n');

const { data: alimentosBrutos, error: erroAlimentos } = await admin
  .from('alimentos_referencia')
  .select(
    'id, nome_taco, aliases, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g, categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd',
  )
  .order('nome_taco', { ascending: true });
if (erroAlimentos) throw erroAlimentos;
if (!alimentosBrutos) throw new Error('sem dados em alimentos_referencia');

// ACHADO (nesta própria auditoria): o PostgREST tem um teto padrão de 1000
// linhas por resposta — sem paginar, esta tabela (1000+ linhas desde a
// curadoria de 23/ago, RELATÓRIO 20260823_0004) vinha TRUNCADA em
// silêncio, sem erro nenhum, fazendo "Uva, suco concentrado, envasado" (que
// TEM "copo"/"copo americano" cadastrados, confirmado por consulta manual)
// aparecer como "zero medidas" na Parte 2. Corrigido com paginação real via
// `.range()` até a página vir mais curta que `TAMANHO_PAGINA`.
const TAMANHO_PAGINA = 1000;
const linhasMedidas: LinhaMedida[] = [];
for (let offset = 0; ; offset += TAMANHO_PAGINA) {
  const { data: pagina, error: erroMedidas } = await admin
    .from('alimentos_medidas_caseiras')
    .select('alimento_id, medida, gramas')
    .range(offset, offset + TAMANHO_PAGINA - 1);
  if (erroMedidas) throw erroMedidas;
  if (!pagina || pagina.length === 0) break;
  linhasMedidas.push(...(pagina as unknown as LinhaMedida[]));
  if (pagina.length < TAMANHO_PAGINA) break;
}

const linhasAlimentos = alimentosBrutos as unknown as LinhaAlimento[];

// Agrupa medidas por alimento_id — O(1) lookup, não O(n) por alimento.
const medidasPorAlimento = new Map<string, LinhaMedida[]>();
for (const m of linhasMedidas) {
  const lista = medidasPorAlimento.get(m.alimento_id) ?? [];
  lista.push(m);
  medidasPorAlimento.set(m.alimento_id, lista);
}

// Monta o MESMO shape que `criarCatalogoAlimentosReal` monta em produção —
// pra `encontrarAlimento` rodar exatamente como roda no servidor de verdade.
const catalogo: AlimentoCatalogo[] = linhasAlimentos.map((l) => ({
  id: l.id,
  nomeTaco: l.nome_taco,
  aliases: l.aliases ?? [],
  caloriasKcal100g: Number(l.calorias_kcal_100g),
  proteinasG100g: Number(l.proteinas_g_100g),
  carboidratosG100g: Number(l.carboidratos_g_100g),
  gordurasG100g: Number(l.gorduras_g_100g),
  categoriaConsumo: l.categoria_consumo ?? undefined,
  unidadeMedidaPadrao: l.unidade_medida_padrao ?? undefined,
  medidaPadraoNome: l.medida_padrao_nome ?? undefined,
  medidaPadraoQtd: l.medida_padrao_qtd ?? undefined,
  medidas: (medidasPorAlimento.get(l.id) ?? []).map((m) => ({ medida: m.medida, gramas: Number(m.gramas) })),
}));

console.log(`Catálogo: ${catalogo.length} alimentos, ${linhasMedidas.length} medidas caseiras.\n`);

// ═══════════════════════════════════════════════════════════════════════
// PARTE 1 — Colisão de aliases
// ═══════════════════════════════════════════════════════════════════════
console.log('═══ PARTE 1 — Colisão de aliases ═══\n');

// 1a. Autoconsistência: buscar CADA alias/nome de CADA alimento contra o
// catálogo inteiro (a mesma função de produção) e conferir se ele SE
// ACHA. Se não, é prova concreta — não hipótese — de que outro alimento
// com um alias mais curto/genérico está roubando o match.
interface FalhaAutoconsistencia {
  alimentoEsperado: string;
  termoBuscado: string;
  alimentoAchado: string;
}
const falhasAutoconsistencia: FalhaAutoconsistencia[] = [];

for (const alimento of catalogo) {
  const termos = [alimento.nomeTaco, ...alimento.aliases];
  for (const termo of termos) {
    const achado = encontrarAlimento(catalogo, termo);
    if (achado && achado.id !== alimento.id) {
      falhasAutoconsistencia.push({
        alimentoEsperado: alimento.nomeTaco,
        termoBuscado: termo,
        alimentoAchado: achado.nomeTaco,
      });
    }
  }
}

console.log(
  `🔴 Falhas de autoconsistência (termo do PRÓPRIO alimento resolve pra OUTRO): ${falhasAutoconsistencia.length}\n`,
);
for (const f of falhasAutoconsistencia) {
  console.log(`   "${f.termoBuscado}" (de "${f.alimentoEsperado}") -> achou "${f.alimentoAchado}"`);
}

// 1b. Aliases de 1 palavra só (sem espaço) — risco latente de substring,
// mesmo quando ainda não colidiram com nada hoje (podem colidir amanhã,
// com uma fruta/prato que ainda não existe no catálogo — caso "abacaxi").
interface AliasCurto {
  alias: string;
  donos: string[]; // nomes dos alimentos que têm esse alias
}
const donosPoAliasCurto = new Map<string, Set<string>>();
for (const alimento of catalogo) {
  for (const aliasOriginal of alimento.aliases) {
    const norm = normalizarTexto(aliasOriginal);
    if (norm.includes(' ')) continue; // só interessa alias de 1 palavra
    if (norm.length < 3) continue; // "l"/"kg" etc. não são nomes de comida
    const set = donosPoAliasCurto.get(norm) ?? new Set<string>();
    set.add(alimento.nomeTaco);
    donosPoAliasCurto.set(norm, set);
  }
}
const aliasesCurtos: AliasCurto[] = [...donosPoAliasCurto.entries()]
  .map(([alias, donos]) => ({ alias, donos: [...donos].sort() }))
  .sort((a, b) => b.donos.length - a.donos.length || a.alias.localeCompare(b.alias));

const colisoesReais = aliasesCurtos.filter((a) => a.donos.length > 1);
const soloRisco = aliasesCurtos.filter((a) => a.donos.length === 1);

console.log(`\n🟠 Aliases de 1 palavra compartilhados por 2+ alimentos (colisão JÁ existe): ${colisoesReais.length}\n`);
for (const c of colisoesReais) {
  console.log(`   "${c.alias}" -> ${c.donos.join(' | ')}`);
}

console.log(
  `\n🟡 Aliases de 1 palavra usados por só 1 alimento (risco latente pra fruta/prato ainda não cadastrado): ${soloRisco.length}\n`,
);
for (const s of soloRisco) {
  console.log(`   "${s.alias}" -> ${s.donos[0]}`);
}

// ═══════════════════════════════════════════════════════════════════════
// PARTE 2 — Cobertura de medidas
// ═══════════════════════════════════════════════════════════════════════
console.log('\n═══ PARTE 2 — Cobertura de medidas ═══\n');

// "ml"/"litro"/"l"/"mililitro" já são universais (FATORES_UNIDADE_BRUTA em
// index.ts, resolvidos ANTES de qualquer medida caseira) — não contam
// aqui. O que importa é ter pelo menos UM recipiente NOMEADO cadastrado
// (é isso que falha quando o usuário diz "copo", não "300ml").
const PALAVRAS_RECIPIENTE = ['copo', 'xicara', 'taca', 'lata', 'garrafinha', 'garrafa', 'dose', 'calice', 'caneca'];

function temRecipienteNomeado(alimento: AlimentoCatalogo): boolean {
  return alimento.medidas.some((m) => {
    const norm = normalizarTexto(m.medida);
    return PALAVRAS_RECIPIENTE.some((p) => norm.includes(p));
  });
}

const liquidosSemRecipiente = catalogo.filter(
  (a) =>
    (a.categoriaConsumo === 'liquido_frio' || a.categoriaConsumo === 'liquido_quente') &&
    !temRecipienteNomeado(a),
);

console.log(
  `🔴 Líquidos (liquido_frio/liquido_quente) SEM nenhuma medida de recipiente nomeado cadastrada: ${liquidosSemRecipiente.length}\n`,
);
for (const a of liquidosSemRecipiente) {
  const medidas = a.medidas.map((m) => `${m.medida} (${m.gramas}g)`).join(', ') || '(nenhuma medida cadastrada)';
  console.log(`   [${a.categoriaConsumo}] ${a.nomeTaco} — medidas: ${medidas}`);
}

const unidadeOuFatiaSemMedida = catalogo.filter(
  (a) => (a.categoriaConsumo === 'unidade' || a.categoriaConsumo === 'fatia') && a.medidas.length === 0,
);

console.log(
  `\n🟠 Itens de unidade/fatia SEM NENHUMA medida caseira cadastrada: ${unidadeOuFatiaSemMedida.length}\n`,
);
for (const a of unidadeOuFatiaSemMedida) {
  console.log(`   [${a.categoriaConsumo}] ${a.nomeTaco}`);
}

const semNenhumaMedida = catalogo.filter((a) => a.medidas.length === 0);
console.log(
  `\n🟡 Total de alimentos SEM NENHUMA medida caseira cadastrada (qualquer categoria): ${semNenhumaMedida.length}`,
);

// ═══════════════════════════════════════════════════════════════════════
// PARTE 3 — Cruzamento (risco máximo)
// ═══════════════════════════════════════════════════════════════════════
console.log('\n═══ PARTE 3 — Cruzamento (alias perigoso + medida ausente) ═══\n');

const nomesEmRiscoDeAlias = new Set<string>([
  ...falhasAutoconsistencia.map((f) => f.alimentoEsperado),
  ...colisoesReais.flatMap((c) => c.donos),
]);
const nomesComMedidaAusente = new Set<string>([
  ...liquidosSemRecipiente.map((a) => a.nomeTaco),
  ...unidadeOuFatiaSemMedida.map((a) => a.nomeTaco),
]);

const cruzamento = [...nomesEmRiscoDeAlias].filter((nome) => nomesComMedidaAusente.has(nome));

console.log(`⚠️  Alimentos com AS DUAS vulnerabilidades ao mesmo tempo: ${cruzamento.length}\n`);
for (const nome of cruzamento) {
  console.log(`   ${nome}`);
}

console.log('\n✅ Auditoria concluída — nenhuma linha do banco foi alterada.');
