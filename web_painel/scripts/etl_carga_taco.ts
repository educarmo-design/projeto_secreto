/**
 * ETL — Carga Massiva da Tabela TACO (Missão F45, Adendo v5.1 §A.2/§A.3/§D).
 *
 * Popula `alimentos_referencia` com a base nutricional primária (596
 * alimentos reais, composição por 100g) — a mesma tabela que hoje só tem 8
 * linhas (5 do seed original + 3 de teste, ver 20260716120000/
 * seed_teste_alimentos.ts). Depois desta carga, o cálculo determinístico de
 * calorias/macros de `extract-metric-photo` (A.2: "IA traduz, backend
 * calcula") passa a ter um catálogo de verdade para casar, não só 8 itens de
 * amostra.
 *
 * FONTE DOS DADOS (`scripts/data/taco.json`): digitalização de terceiros da
 * Tabela Brasileira de Composição de Alimentos (TACO, NEPA/UNICAMP, 4ª
 * edição) — github.com/marcelosanto/tabela_taco (MIT). Não é o PDF oficial
 * baixado diretamente; validei antes de usar comparando várias linhas contra
 * valores já conhecidos (ex.: "Feijão, carioca, cozido" nesta fonte bate,
 * até a segunda casa decimal, com o valor já seedado em
 * 20260716120000_alimentos_referencia_taco.sql, que veio de uma fonte
 * independente). Arquivo já vem TRIMADO para só os 4 campos que
 * `alimentos_referencia` usa (nome/calorias/proteínas/carboidratos/
 * gorduras) — a tabela original tinha ~70 colunas (aminoácidos, perfil de
 * ácidos graxos, vitaminas...) que este schema não modela; carregar tudo
 * seria dado morto. 1 nome duplicado no dataset original ("Maria mole",
 * dois alimentos reais com o mesmo nome em categorias diferentes) foi
 * descartado na geração deste arquivo — fica registrado aqui, não é um bug
 * deste script.
 *
 * Idempotente por nome (mesmo padrão de seed_teste_alimentos.ts, não
 * `ON CONFLICT`): `alimentos_referencia.nome_taco` não tem constraint
 * `unique` no schema atual, então um upsert de banco não tem em cima de que
 * mirar — a checagem de duplicata é feita aqui, antes do insert. Reexecutar
 * este script não duplica nada: só insere os nomes que ainda não existem.
 *
 * `embedding` nunca aparece no payload de insert — fica NULL, pronto para
 * `seed_food_embeddings.ts` processar depois (é o próximo passo manual,
 * não disparado automaticamente por este ETL, para manter as
 * responsabilidades separadas e não gastar tokens do Gemini como
 * efeito colateral de rodar uma carga de dados).
 *
 * Como rodar:
 *   1. cd web_painel
 *   2. .env já configurado (VITE_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY —
 *      ver scripts/seed_cloud.ts) cobre este script também.
 *   3. npm run etl:carga-taco
 */
import 'dotenv/config';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import taco from './data/taco.json' with { type: 'json' };

const TAMANHO_LOTE = 200;

interface AlimentoTaco {
  nome: string;
  calorias: number;
  proteinas: number;
  carboidratos: number;
  gorduras: number;
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Variável de ambiente ${name} não configurada — veja as instruções no topo de scripts/etl_carga_taco.ts.`,
    );
  }
  return value;
}

/** Mesma lógica de seed_cloud.ts/seed_food_embeddings.ts: VITE_SUPABASE_URL no .env já vem com `/rest/v1/`; o client admin precisa só da origem. */
function baseSupabaseUrl(): string {
  return new URL(requireEnv('VITE_SUPABASE_URL')).origin;
}

/**
 * Busca só o que já existe entre os nomes da TACO — não a tabela inteira,
 * para não crescer sem necessidade conforme o catálogo aumenta em cargas
 * futuras. Em pedaços de `TAMANHO_LOTE`: um `.in()` com os ~600 nomes de uma
 * vez só estourou o limite de 16KB de headers do PostgREST na prática
 * (`HeadersOverflowError`, URL de 22KB) — erro só visível rodando de
 * verdade, não em typecheck/lint.
 */
async function buscarNomesExistentes(admin: SupabaseClient, nomes: string[]): Promise<Set<string>> {
  const existentes = new Set<string>();
  for (let i = 0; i < nomes.length; i += TAMANHO_LOTE) {
    const pedaco = nomes.slice(i, i + TAMANHO_LOTE);
    const { data, error } = await admin.from('alimentos_referencia').select('nome_taco').in('nome_taco', pedaco);
    if (error) throw new Error(`select alimentos_referencia: ${error.message}`);
    for (const row of data ?? []) {
      existentes.add(row.nome_taco as string);
    }
  }
  return existentes;
}

async function inserirLote(admin: SupabaseClient, alimentos: AlimentoTaco[]): Promise<void> {
  const { error } = await admin.from('alimentos_referencia').insert(
    alimentos.map((a) => ({
      nome_taco: a.nome,
      aliases: [],
      fonte: 'taco',
      calorias_kcal_100g: a.calorias,
      proteinas_g_100g: a.proteinas,
      carboidratos_g_100g: a.carboidratos,
      gorduras_g_100g: a.gorduras,
      // embedding deliberadamente ausente — fica NULL, ver cabeçalho.
    })),
  );
  if (error) throw new Error(`insert alimentos_referencia: ${error.message}`);
}

async function main() {
  const admin = createClient(baseSupabaseUrl(), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const todos = taco as AlimentoTaco[];
  console.log(`Dataset TACO: ${todos.length} alimento(s) no arquivo fonte.`);

  const nomesExistentes = await buscarNomesExistentes(
    admin,
    todos.map((a) => a.nome),
  );
  const pendentes = todos.filter((a) => !nomesExistentes.has(a.nome));
  const jaExistiam = todos.length - pendentes.length;

  if (pendentes.length === 0) {
    console.log(`Nenhum alimento novo — os ${jaExistiam} já existem em alimentos_referencia.`);
    return;
  }

  const totalLotes = Math.ceil(pendentes.length / TAMANHO_LOTE);
  console.log(
    `${pendentes.length} alimento(s) novo(s) para inserir (${jaExistiam} já existiam e serão pulados). Processando em ${totalLotes} lote(s) de até ${TAMANHO_LOTE}.`,
  );

  let inseridos = 0;
  for (let numeroLote = 1; numeroLote <= totalLotes; numeroLote += 1) {
    const inicio = (numeroLote - 1) * TAMANHO_LOTE;
    const lote = pendentes.slice(inicio, inicio + TAMANHO_LOTE);

    console.log(`Processando lote ${numeroLote}/${totalLotes} (${lote.length} alimento(s))...`);
    await inserirLote(admin, lote);
    inseridos += lote.length;
    console.log(`  OK: lote ${numeroLote}/${totalLotes} inserido (${inseridos}/${pendentes.length} até agora).`);
  }

  console.log(
    `\nConcluído: ${inseridos} alimento(s) inserido(s), ${jaExistiam} já existiam e foram pulados. Total no dataset: ${todos.length}.`,
  );
  console.log('Próximo passo manual: npm run seed:food-embeddings (popula o embedding dos novos alimentos).');
}

main().catch((err) => {
  console.error('ETL de carga da TACO falhou:', err instanceof Error ? err.message : err);
  console.error(
    'O script é idempotente (só insere nomes que ainda não existem) — corrija o problema e rode de novo; ele retoma de onde parou.',
  );
  process.exit(1);
});
