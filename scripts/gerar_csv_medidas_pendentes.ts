/**
 * Script: Gerar CSV de Alimentos Pendentes para Auditoria TACO
 *
 * Propósito: Consultar `alimentos_referencia` e gerar arquivo CSV com alimentos
 * que NÃO têm `categoria_consumo` definida, para que o fundador audite e preencha.
 *
 * Uso:
 *   deno run --allow-all scripts/gerar_csv_medidas_pendentes.ts
 *
 * Saída:
 *   docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA_GERADA_$(data).csv
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY');

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error('❌ Erro: SUPABASE_URL ou SUPABASE_ANON_KEY não definidos no env');
  console.error('   Defina com: export SUPABASE_URL=... export SUPABASE_ANON_KEY=...');
  Deno.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

interface AlimentoAuditoria {
  id: string;
  nome_taco: string;
  aliases: string[];
  fonte: string;
  calorias_kcal_100g: number;
  proteinas_g_100g: number;
  carboidratos_g_100g: number;
  gorduras_g_100g: number;
  categoria_consumo: string | null;
  unidade_medida_padrao: string | null;
  medida_padrao_nome: string | null;
  medida_padrao_qtd: number | null;
}

async function gerarCSV() {
  console.log('📊 Consultando alimentos_referencia...');

  // Query 1: Alimentos JÁ categorizados (para referência)
  const { data: categorizados, error: erroCateg } = await supabase
    .from('alimentos_referencia')
    .select('id, nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g, categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd')
    .not('categoria_consumo', 'is', null)
    .order('nome_taco', { ascending: true });

  if (erroCateg) {
    console.error('❌ Erro ao buscar categorizados:', erroCateg);
    Deno.exit(1);
  }

  // Query 2: Alimentos SEM categoria (pendentes)
  const { data: pendentes, error: erroPend } = await supabase
    .from('alimentos_referencia')
    .select('id, nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g, categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd')
    .is('categoria_consumo', null)
    .order('nome_taco', { ascending: true });

  if (erroPend) {
    console.error('❌ Erro ao buscar pendentes:', erroPend);
    Deno.exit(1);
  }

  console.log(`✅ Encontrados ${categorizados?.length || 0} alimentos categorizados`);
  console.log(`⏳ Encontrados ${pendentes?.length || 0} alimentos PENDENTES de categorização`);

  // Montar CSV
  const linhas: string[] = [];

  // Header
  linhas.push(
    'id,nome_taco,aliases,fonte,categoria_consumo_CONFIRMADA,unidade_medida_CONFIRMADA,medida_padrao_nome_CONFIRMADA,medida_padrao_qtd_CONFIRMADA,calorias_100g,proteinas_g_100g,carboidratos_g_100g,gorduras_g_100g,REVISADO_POR_FUNDADOR,DATA_REVISAO,NOTAS'
  );

  // Instruções (linhas começam com empty id)
  linhas.push(
    ',,,"","","","","",,,,,"N","","INSTRUÇÕES: Use este CSV para auditar alimentos PENDENTES (categoria_consumo=null)"'
  );
  linhas.push(
    ',,,"","","","","",,,,,"N","","Coluna categoria_consumo_CONFIRMADA: unidade, fatia, peso_livre, liquido_frio, liquido_quente"'
  );
  linhas.push(
    ',,,"","","","","",,,,,"N","","Se unidade/fatia: preencher medida_padrao_qtd em gramas. Se liquido_*: em ml."'
  );
  linhas.push(
    ',,,"","","","","",,,,,"N","","Marcar REVISADO_POR_FUNDADOR=S apenas após validação no TACO/USDA"'
  );
  linhas.push(',,,"","","","","",,,,,"N","","');

  // Seção: Alimentos Categorizados (apenas como referência, read-only)
  linhas.push(',,,"","","","","",,,,,"S","","[REFERÊNCIA] Alimentos já categorizados (não editar)');
  if (categorizados && categorizados.length > 0) {
    for (const al of categorizados as AlimentoAuditoria[]) {
      const aliasesStr = al.aliases ? `"${al.aliases.join(', ')}"` : '';
      linhas.push(
        `"${al.id}","${escaparCSV(al.nome_taco)}",${aliasesStr},"${al.fonte}","${al.categoria_consumo}","${al.unidade_medida_padrao || ''}","${al.medida_padrao_nome || ''}","${al.medida_padrao_qtd || ''}",${al.calorias_kcal_100g},${al.proteinas_g_100g},${al.carboidratos_g_100g},${al.gorduras_g_100g},"S","${new Date().toISOString().split('T')[0]}","Já categorizado"`
      );
    }
  }
  linhas.push(',,,"","","","","",,,,,"N","","');

  // Seção: Alimentos Pendentes (editar aqui)
  linhas.push(',,,"","","","","",,,,,"N","","[PENDENTES] Preencher categoria_consumo e medida_padrao_qtd');
  if (pendentes && pendentes.length > 0) {
    for (const al of pendentes as AlimentoAuditoria[]) {
      const aliasesStr = al.aliases ? `"${al.aliases.join(', ')}"` : '';
      linhas.push(
        `"${al.id}","${escaparCSV(al.nome_taco)}",${aliasesStr},"${al.fonte}","","","","",${al.calorias_kcal_100g},${al.proteinas_g_100g},${al.carboidratos_g_100g},${al.gorduras_g_100g},"N","","Auditar: preencher categoria_consumo"`
      );
    }
  } else {
    linhas.push(',,,"","","","","",,,,,"N","","✅ Parabéns! Nenhum alimento pendente — catálogo 100% categorizado!');
  }

  // Timestamp para unicidade
  const agora = new Date();
  const timestamp = agora.toISOString().replace(/[:.]/g, '-').slice(0, -5); // 2026-08-02T14-35-22
  const nomeArquivo = `docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA_GERADA_${timestamp}.csv`;

  // Gravar arquivo
  const csvContent = linhas.join('\n');
  await Deno.writeTextFile(nomeArquivo, csvContent, { encoding: 'utf-8' });

  console.log(`\n✅ CSV gerado com sucesso!`);
  console.log(`📄 Arquivo: ${nomeArquivo}`);
  console.log(`📊 Resumo:`);
  console.log(`   - Total de alimentos: ${(categorizados?.length || 0) + (pendentes?.length || 0)}`);
  console.log(`   - Categorizados: ${categorizados?.length || 0} ✅`);
  console.log(`   - Pendentes: ${pendentes?.length || 0} ⏳`);
  console.log(`\n📋 Próximos passos:`);
  console.log(`   1. Abrir ${nomeArquivo} em Excel/Google Sheets`);
  console.log(`   2. Preencher coluna "categoria_consumo_CONFIRMADA" para cada alimento pendente`);
  console.log(`   3. Se categoria for unidade/fatia, preencher "medida_padrao_qtd_CONFIRMADA" em gramas`);
  console.log(`   4. Se categoria for liquido_*, preencher em ml (ex: 200 para xícara de café)`);
  console.log(`   5. Marcar REVISADO_POR_FUNDADOR='S' para cada linha validada`);
  console.log(`   6. Salvar como CSV e submeter para PR de nova migration`);
}

function escaparCSV(texto: string): string {
  if (!texto) return '';
  // Se contém aspas, duplicar e envolver em aspas
  if (texto.includes('"') || texto.includes(',') || texto.includes('\n')) {
    return `"${texto.replace(/"/g, '""')}"`;
  }
  return texto;
}

await gerarCSV().catch((err) => {
  console.error('❌ Erro fatal:', err);
  Deno.exit(1);
});
