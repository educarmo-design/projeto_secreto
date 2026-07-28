/**
 * Carga mínima de validação — Nutrição Semântica (Adendo v5.1 §A.3).
 *
 * 5 alimentos (base brasileira + industrializados/suplemento) para testar
 * o pipeline de embeddings ponta a ponta (este script -> seed_food_embeddings.ts
 * -> futura busca por similaridade) sem gastar tokens de verdade na carga
 * massiva da TACO completa (Missão F45, ainda não feita).
 *
 * DESVIO REGISTRADO (ver RELATÓRIO): a tarefa partiu da premissa de que
 * `alimentos_referencia` estava vazia. Não está — a migration
 * 20260716120000_alimentos_referencia_taco.sql já semeou 5 linhas
 * (Arroz/Feijão/Carne/Ovo/Alface), e dois dos cinco itens pedidos aqui
 * ("Arroz branco cozido", "Feijão carioca cozido") são o MESMO alimento que
 * já existe lá. Inserir de novo criaria duas linhas para o mesmo alimento —
 * o casamento de sinônimos por `aliases`/embedding ficaria ambíguo (duas
 * candidatas pra "arroz"). Por isso este script confere por `nome_taco`
 * antes de inserir cada item: os 2 que já existem são pulados (já estão lá,
 * já com embedding NULL, já servem pro teste); só os 3 genuinamente novos
 * (Pão de queijo, Refrigerante de Cola, Whey Protein) são inseridos.
 *
 * `embedding` nunca aparece no payload de insert — a coluna não tem NOT
 * NULL, então fica NULL por padrão, exatamente o que o próximo passo
 * (seed_food_embeddings.ts) precisa encontrar pra processar.
 *
 * Como rodar:
 *   1. cd web_painel
 *   2. .env já configurado (VITE_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY —
 *      ver scripts/seed_cloud.ts) cobre este script também, nenhuma
 *      variável nova é necessária.
 *   3. npm run seed:teste-alimentos
 */
import 'dotenv/config';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

interface AlimentoTeste {
  nomeTaco: string;
  aliases: string[];
  fonte: 'taco' | 'usda';
  caloriasKcal100g: number;
  proteinasG100g: number;
  carboidratosG100g: number;
  gordurasG100g: number;
}

// Macros aproximados por 100g — melhor esforço para destravar o teste do
// pipeline, não substituem uma importação oficial (mesma ressalva já
// registrada em 20260716120000 para o seed original).
const ALIMENTOS_TESTE: AlimentoTeste[] = [
  {
    nomeTaco: 'Arroz, branco, cozido',
    aliases: ['arroz', 'arroz branco', 'arroz cozido', 'arroz branco cozido'],
    fonte: 'taco',
    caloriasKcal100g: 128,
    proteinasG100g: 2.5,
    carboidratosG100g: 28.1,
    gordurasG100g: 0.2,
  },
  {
    nomeTaco: 'Feijão, carioca, cozido',
    aliases: ['feijao', 'feijão', 'feijao carioca', 'feijão carioca', 'feijao cozido'],
    fonte: 'taco',
    caloriasKcal100g: 76,
    proteinasG100g: 4.8,
    carboidratosG100g: 13.6,
    gordurasG100g: 0.5,
  },
  {
    nomeTaco: 'Pão de queijo',
    aliases: ['pao de queijo', 'pão de queijo', 'paozinho de queijo', 'bolinha de queijo'],
    fonte: 'taco',
    caloriasKcal100g: 364,
    proteinasG100g: 7.4,
    carboidratosG100g: 34.1,
    gordurasG100g: 21.5,
  },
  {
    nomeTaco: 'Refrigerante, cola',
    aliases: ['refrigerante', 'coca cola', 'refrigerante de cola', 'coca', 'refri', 'guarana'],
    fonte: 'usda',
    caloriasKcal100g: 42,
    proteinasG100g: 0,
    carboidratosG100g: 10.6,
    gordurasG100g: 0,
  },
  {
    nomeTaco: 'Whey Protein, pó',
    aliases: ['whey', 'whey protein', 'proteina em po', 'proteína em pó', 'suplemento proteico'],
    fonte: 'usda',
    caloriasKcal100g: 400,
    proteinasG100g: 80,
    carboidratosG100g: 8,
    gordurasG100g: 7,
  },
];

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Variável de ambiente ${name} não configurada — veja as instruções no topo de scripts/seed_teste_alimentos.ts.`,
    );
  }
  return value;
}

/** Mesma lógica de seed_cloud.ts/seed_food_embeddings.ts: VITE_SUPABASE_URL no .env já vem com `/rest/v1/`; o client admin precisa só da origem. */
function baseSupabaseUrl(): string {
  return new URL(requireEnv('VITE_SUPABASE_URL')).origin;
}

async function buscarNomesExistentes(admin: SupabaseClient, nomes: string[]): Promise<Set<string>> {
  const { data, error } = await admin.from('alimentos_referencia').select('nome_taco').in('nome_taco', nomes);
  if (error) throw new Error(`select alimentos_referencia: ${error.message}`);
  return new Set((data ?? []).map((row) => row.nome_taco as string));
}

async function main() {
  const admin = createClient(baseSupabaseUrl(), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const nomesExistentes = await buscarNomesExistentes(
    admin,
    ALIMENTOS_TESTE.map((a) => a.nomeTaco),
  );

  let inseridos = 0;
  let pulados = 0;

  for (const alimento of ALIMENTOS_TESTE) {
    if (nomesExistentes.has(alimento.nomeTaco)) {
      console.log(`  JÁ EXISTE: "${alimento.nomeTaco}" — pulando (evita duplicar o catálogo).`);
      pulados += 1;
      continue;
    }

    const { error } = await admin.from('alimentos_referencia').insert({
      nome_taco: alimento.nomeTaco,
      aliases: alimento.aliases,
      fonte: alimento.fonte,
      calorias_kcal_100g: alimento.caloriasKcal100g,
      proteinas_g_100g: alimento.proteinasG100g,
      carboidratos_g_100g: alimento.carboidratosG100g,
      gorduras_g_100g: alimento.gordurasG100g,
      // embedding deliberadamente ausente — coluna fica NULL, pronta para
      // seed_food_embeddings.ts processar.
    });
    if (error) throw new Error(`insert alimentos_referencia (${alimento.nomeTaco}): ${error.message}`);

    console.log(`  OK: "${alimento.nomeTaco}" inserido (embedding NULL).`);
    inseridos += 1;
  }

  console.log(`\nConcluído: ${inseridos} alimento(s) inserido(s), ${pulados} já existiam e foram pulados.`);
}

main().catch((err) => {
  console.error('Seed de teste de alimentos falhou:', err instanceof Error ? err.message : err);
  process.exit(1);
});
