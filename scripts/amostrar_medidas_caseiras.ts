/**
 * RELATÓRIO 20260830_0001 (N28, Regra 26 — "amostragem de dado gerado por
 * IA"): sorteia uma amostra aleatória de `alimentos_medidas_caseiras` para
 * conferência humana de plausibilidade, em vez de confiar na autoavaliação
 * do próprio modelo que gerou os dados (a curadoria em massa de 23/ago —
 * `web_painel/scripts/curar_catalogo_alimentos_ia.ts` — só marcou 12 das
 * 1.056 linhas geradas como `revisao_necessaria`, 1%, o que a Regra 26
 * considera não-crível vindo do próprio gerador).
 *
 * Não corrige nada — só sorteia, imprime e deixa a decisão de correção em
 * massa (se necessária) para o fundador, com a taxa de erro medida.
 *
 * Uso:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *     deno run --allow-net --allow-env scripts/amostrar_medidas_caseiras.ts [TAMANHO_AMOSTRA]
 *
 * Precisa da service role key (não a anon): a policy de SELECT de
 * `alimentos_medidas_caseiras` é `to authenticated`, não `anon` — mesma
 * chave que `web_painel/scripts/curar_catalogo_alimentos_ia.ts` usa,
 * guardada em `web_painel/.env.local` (nunca commitada).
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const TAMANHO_AMOSTRA = Number(Deno.args[0]) || 50;

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('❌ Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente.');
  Deno.exit(1);
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY);

interface LinhaMedida {
  id: number;
  medida: string;
  gramas: number;
  revisao_necessaria: boolean;
  observacao_revisao: string | null;
  alimentos_referencia: { nome_taco: string; categoria_consumo: string | null } | null;
}

const { count, error: erroCount } = await admin
  .from('alimentos_medidas_caseiras')
  .select('id', { count: 'exact', head: true });
if (erroCount) throw erroCount;
console.log(`Total de linhas em alimentos_medidas_caseiras: ${count}`);

const { data, error } = await admin
  .from('alimentos_medidas_caseiras')
  .select(
    'id, medida, gramas, revisao_necessaria, observacao_revisao, alimentos_referencia(nome_taco, categoria_consumo)',
  )
  .order('id', { ascending: true });
if (error) throw error;
if (!data) throw new Error('sem dados');

// Fisher-Yates com Math.random — sem seed fixo (cada corrida é uma amostra
// nova, de propósito: o objetivo é auditoria periódica, não reproduzir a
// mesma amostra).
const universo = [...(data as unknown as LinhaMedida[])];
for (let i = universo.length - 1; i > 0; i--) {
  const j = Math.floor(Math.random() * (i + 1));
  [universo[i], universo[j]] = [universo[j], universo[i]];
}
const amostra = universo.slice(0, TAMANHO_AMOSTRA).sort((a, b) => a.id - b.id);

console.log(`\nAmostra de ${amostra.length} (ids em ordem crescente, pra facilitar auditoria):\n`);
console.log('id\talimento\tmedida\tgramas\tcategoria\trevisao_necessaria\tobservacao');
for (const linha of amostra) {
  const alimento = linha.alimentos_referencia;
  console.log(
    `${linha.id}\t${alimento?.nome_taco ?? '???'}\t${linha.medida}\t${linha.gramas}g\t${alimento?.categoria_consumo ?? 'null'}\t${linha.revisao_necessaria}\t${linha.observacao_revisao ?? ''}`,
  );
}
