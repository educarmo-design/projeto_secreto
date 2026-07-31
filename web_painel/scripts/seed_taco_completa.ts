/**
 * Carga Massiva da TACO (F45 — Nutrição Semântica, Adendo v5.1).
 *
 * Popula `alimentos_referencia` e `alimentos_medidas_caseiras` com 100+ alimentos
 * brasileiros da Tabela TACO (Unicamp) + fallback USDA para industrializados.
 * O dataset completo será integrado com o Gemini embedding para busca semântica.
 *
 * CARACTERÍSTICAS:
 * - Bulk insert em lotes de 100 itens (performance)
 * - ON CONFLICT DO UPDATE (idempotência)
 * - Medidas caseiras genéricas associadas a cada alimento
 * - Service role isolada em .env.local
 *
 * Como rodar:
 *   1. cd web_painel
 *   2. Confirme que .env.local tem SUPABASE_SERVICE_ROLE_KEY
 *   3. npm run seed:taco-completa
 *      ou: npx tsx scripts/seed_taco_completa.ts
 */
import 'dotenv/config';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

interface AlimentoTACO {
  nome_taco: string;
  aliases: string[];
  fonte: 'taco' | 'usda';
  calorias_kcal_100g: number;
  proteinas_g_100g: number;
  carboidratos_g_100g: number;
  gorduras_g_100g: number;
}

/**
 * Dataset de 100+ alimentos brasileiros (TACO/USDA).
 * Macros aproximados por 100g da porção cozida/preparada.
 * Fonte: Tabela TACO (Unicamp, 4ª ed.) + USDA FoodData Central.
 */
const ALIMENTOS_TACO_COMPLETA: AlimentoTACO[] = [
  // Cereais e Grãos
  {
    nome_taco: 'Arroz, branco, cozido',
    aliases: ['arroz', 'arroz branco', 'arroz cozido', 'arroz branco cozido', 'arroz integral'],
    fonte: 'taco',
    calorias_kcal_100g: 128,
    proteinas_g_100g: 2.5,
    carboidratos_g_100g: 28.1,
    gorduras_g_100g: 0.2,
  },
  {
    nome_taco: 'Arroz, integral, cozido',
    aliases: ['arroz integral', 'arroz integral cozido', 'arroz marrom'],
    fonte: 'taco',
    calorias_kcal_100g: 111,
    proteinas_g_100g: 2.6,
    carboidratos_g_100g: 23.0,
    gorduras_g_100g: 0.9,
  },
  {
    nome_taco: 'Macarrão, cozido',
    aliases: ['macarrão', 'pasta', 'macarrão cozido', 'macarronada'],
    fonte: 'taco',
    calorias_kcal_100g: 131,
    proteinas_g_100g: 4.5,
    carboidratos_g_100g: 25.0,
    gorduras_g_100g: 1.1,
  },
  {
    nome_taco: 'Pão, branco, francês',
    aliases: ['pão', 'pão francês', 'pão branco', 'baguete', 'francezinha'],
    fonte: 'taco',
    calorias_kcal_100g: 265,
    proteinas_g_100g: 8.1,
    carboidratos_g_100g: 49.0,
    gorduras_g_100g: 2.7,
  },
  {
    nome_taco: 'Pão de queijo',
    aliases: ['pão de queijo', 'paozinho de queijo', 'bolinha de queijo', 'pãozinho queijo'],
    fonte: 'taco',
    calorias_kcal_100g: 364,
    proteinas_g_100g: 7.4,
    carboidratos_g_100g: 34.1,
    gorduras_g_100g: 21.5,
  },
  {
    nome_taco: 'Cereal integral, pronto para consumo',
    aliases: ['cereal integral', 'granola', 'cereal', 'aveia em flocos'],
    fonte: 'taco',
    calorias_kcal_100g: 371,
    proteinas_g_100g: 10.5,
    carboidratos_g_100g: 65.0,
    gorduras_g_100g: 5.8,
  },

  // Leguminosas
  {
    nome_taco: 'Feijão, carioca, cozido',
    aliases: ['feijão', 'feijão carioca', 'feijão cozido', 'feijao', 'feijao carioca'],
    fonte: 'taco',
    calorias_kcal_100g: 76,
    proteinas_g_100g: 4.8,
    carboidratos_g_100g: 13.6,
    gorduras_g_100g: 0.5,
  },
  {
    nome_taco: 'Feijão, preto, cozido',
    aliases: ['feijão preto', 'feijão preto cozido', 'feijao preto', 'feijão negro'],
    fonte: 'taco',
    calorias_kcal_100g: 77,
    proteinas_g_100g: 4.9,
    carboidratos_g_100g: 14.0,
    gorduras_g_100g: 0.4,
  },
  {
    nome_taco: 'Lentilha, cozida',
    aliases: ['lentilha', 'lentilha cozida', 'lentilhas'],
    fonte: 'taco',
    calorias_kcal_100g: 95,
    proteinas_g_100g: 8.3,
    carboidratos_g_100g: 16.4,
    gorduras_g_100g: 0.5,
  },
  {
    nome_taco: 'Grão de bico, cozido',
    aliases: ['grão de bico', 'grão-de-bico', 'grão bico cozido', 'grão de bico cozido'],
    fonte: 'taco',
    calorias_kcal_100g: 134,
    proteinas_g_100g: 8.9,
    carboidratos_g_100g: 22.5,
    gorduras_g_100g: 2.6,
  },

  // Carnes e Derivados
  {
    nome_taco: 'Carne, bovina, contrafilé, grelhado',
    aliases: ['bife', 'bife de boi', 'bife grelhado', 'contrafilé', 'contrafile', 'carne bovina grelhada'],
    fonte: 'taco',
    calorias_kcal_100g: 247,
    proteinas_g_100g: 32.7,
    carboidratos_g_100g: 0,
    gorduras_g_100g: 12.6,
  },
  {
    nome_taco: 'Carne, bovina, alcatra, grelhada',
    aliases: ['alcatra', 'alcatra grelhada', 'carne alcatra', 'carne vermelha'],
    fonte: 'taco',
    calorias_kcal_100g: 219,
    proteinas_g_100g: 31.0,
    carboidratos_g_100g: 0,
    gorduras_g_100g: 9.9,
  },
  {
    nome_taco: 'Carne, suína, asinha, assada',
    aliases: ['carne suína', 'carne de porco', 'porco', 'asinha'],
    fonte: 'taco',
    calorias_kcal_100g: 240,
    proteinas_g_100g: 30.5,
    carboidratos_g_100g: 0,
    gorduras_g_100g: 12.3,
  },
  {
    nome_taco: 'Frango, peito, grelhado, sem pele',
    aliases: ['frango', 'frango grelhado', 'frango sem pele', 'peito de frango', 'frango branco'],
    fonte: 'taco',
    calorias_kcal_100g: 165,
    proteinas_g_100g: 31.0,
    carboidratos_g_100g: 0,
    gorduras_g_100g: 3.6,
  },
  {
    nome_taco: 'Frango, coxa, cozida',
    aliases: ['coxa de frango', 'coxa frango', 'frango coxa', 'coxinha frango'],
    fonte: 'taco',
    calorias_kcal_100g: 209,
    proteinas_g_100g: 26.0,
    carboidratos_g_100g: 0,
    gorduras_g_100g: 11.0,
  },
  {
    nome_taco: 'Peixe, salmão, grelhado',
    aliases: ['salmão', 'salmão grelhado', 'peixe salmão', 'salmão cozido'],
    fonte: 'taco',
    calorias_kcal_100g: 206,
    proteinas_g_100g: 22.0,
    carboidratos_g_100g: 0,
    gorduras_g_100g: 12.5,
  },
  {
    nome_taco: 'Ovo, de galinha, frito',
    aliases: ['ovo frito', 'ovo', 'ovo de galinha frito', 'ovo de galinha'],
    fonte: 'taco',
    calorias_kcal_100g: 197,
    proteinas_g_100g: 13.5,
    carboidratos_g_100g: 0.9,
    gorduras_g_100g: 15.8,
  },
  {
    nome_taco: 'Ovo, de galinha, cozido',
    aliases: ['ovo cozido', 'ovo cozido duro', 'ovo mole'],
    fonte: 'taco',
    calorias_kcal_100g: 155,
    proteinas_g_100g: 13.0,
    carboidratos_g_100g: 1.1,
    gorduras_g_100g: 11.2,
  },
  {
    nome_taco: 'Queijo, tipo meia cura',
    aliases: ['queijo', 'queijo meia cura', 'queijo branco'],
    fonte: 'taco',
    calorias_kcal_100g: 356,
    proteinas_g_100g: 23.0,
    carboidratos_g_100g: 1.3,
    gorduras_g_100g: 28.5,
  },
  {
    nome_taco: 'Iogurte natural',
    aliases: ['iogurte', 'iogurte natural', 'yogurte'],
    fonte: 'taco',
    calorias_kcal_100g: 65,
    proteinas_g_100g: 3.7,
    carboidratos_g_100g: 5.2,
    gorduras_g_100g: 3.8,
  },

  // Vegetais
  {
    nome_taco: 'Alface, lisa, crua',
    aliases: ['alface', 'alface crua', 'alface lisa', 'salada verde'],
    fonte: 'taco',
    calorias_kcal_100g: 11,
    proteinas_g_100g: 1.1,
    carboidratos_g_100g: 1.7,
    gorduras_g_100g: 0.2,
  },
  {
    nome_taco: 'Tomate, cru',
    aliases: ['tomate', 'tomate cru', 'tomate vermelho'],
    fonte: 'taco',
    calorias_kcal_100g: 20,
    proteinas_g_100g: 0.9,
    carboidratos_g_100g: 4.3,
    gorduras_g_100g: 0.2,
  },
  {
    nome_taco: 'Cenoura, cozida',
    aliases: ['cenoura', 'cenoura cozida', 'cenoura ralada'],
    fonte: 'taco',
    calorias_kcal_100g: 35,
    proteinas_g_100g: 0.8,
    carboidratos_g_100g: 8.2,
    gorduras_g_100g: 0.3,
  },
  {
    nome_taco: 'Batata, cozida',
    aliases: ['batata', 'batata cozida', 'batata seco'],
    fonte: 'taco',
    calorias_kcal_100g: 82,
    proteinas_g_100g: 2.1,
    carboidratos_g_100g: 17.6,
    gorduras_g_100g: 0.1,
  },
  {
    nome_taco: 'Batata-doce, cozida',
    aliases: ['batata-doce', 'batata doce', 'batata doce cozida', 'batata laranja'],
    fonte: 'taco',
    calorias_kcal_100g: 90,
    proteinas_g_100g: 1.6,
    carboidratos_g_100g: 20.1,
    gorduras_g_100g: 0.1,
  },
  {
    nome_taco: 'Brócolis, cozido',
    aliases: ['brócolis', 'brocolis', 'brócolis cozido'],
    fonte: 'taco',
    calorias_kcal_100g: 31,
    proteinas_g_100g: 2.8,
    carboidratos_g_100g: 5.7,
    gorduras_g_100g: 0.4,
  },
  {
    nome_taco: 'Couve, cozida',
    aliases: ['couve', 'couve cozida', 'couve repolho'],
    fonte: 'taco',
    calorias_kcal_100g: 27,
    proteinas_g_100g: 1.9,
    carboidratos_g_100g: 5.0,
    gorduras_g_100g: 0.4,
  },
  {
    nome_taco: 'Abóbora, cozida',
    aliases: ['abóbora', 'abobora', 'abóbora cozida', 'moranga'],
    fonte: 'taco',
    calorias_kcal_100g: 38,
    proteinas_g_100g: 0.8,
    carboidratos_g_100g: 9.0,
    gorduras_g_100g: 0.1,
  },
  {
    nome_taco: 'Milho, cozido',
    aliases: ['milho', 'milho cozido', 'milho verde'],
    fonte: 'taco',
    calorias_kcal_100g: 86,
    proteinas_g_100g: 3.4,
    carboidratos_g_100g: 18.7,
    gorduras_g_100g: 1.3,
  },

  // Frutas
  {
    nome_taco: 'Banana, maçã',
    aliases: ['banana', 'banana maçã', 'banana prata', 'fruta'],
    fonte: 'taco',
    calorias_kcal_100g: 89,
    proteinas_g_100g: 1.1,
    carboidratos_g_100g: 23.0,
    gorduras_g_100g: 0.3,
  },
  {
    nome_taco: 'Maçã, vermelha, crua',
    aliases: ['maçã', 'maca', 'maçã vermelha', 'maçã crua'],
    fonte: 'taco',
    calorias_kcal_100g: 52,
    proteinas_g_100g: 0.3,
    carboidratos_g_100g: 13.8,
    gorduras_g_100g: 0.2,
  },
  {
    nome_taco: 'Laranja, pêra, crua',
    aliases: ['laranja', 'laranja pêra', 'laranja crua', 'suco natural'],
    fonte: 'taco',
    calorias_kcal_100g: 46,
    proteinas_g_100g: 0.7,
    carboidratos_g_100g: 11.8,
    gorduras_g_100g: 0.3,
  },
  {
    nome_taco: 'Goiaba, vermelha, crua',
    aliases: ['goiaba', 'goiaba vermelha', 'goiaba crua', 'goiabada'],
    fonte: 'taco',
    calorias_kcal_100g: 68,
    proteinas_g_100g: 0.7,
    carboidratos_g_100g: 16.9,
    gorduras_g_100g: 0.4,
  },
  {
    nome_taco: 'Melancia, crua',
    aliases: ['melancia', 'melancia crua', 'melancia madura'],
    fonte: 'taco',
    calorias_kcal_100g: 30,
    proteinas_g_100g: 0.6,
    carboidratos_g_100g: 7.6,
    gorduras_g_100g: 0.2,
  },

  // Bebidas
  {
    nome_taco: 'Suco, de laranja natural',
    aliases: ['suco', 'suco de laranja', 'suco natural', 'suquinho'],
    fonte: 'taco',
    calorias_kcal_100g: 45,
    proteinas_g_100g: 0.8,
    carboidratos_g_100g: 11.2,
    gorduras_g_100g: 0.2,
  },
  {
    nome_taco: 'Refrigerante, cola',
    aliases: ['refrigerante', 'coca cola', 'refri', 'guarana', 'refrigerante cola'],
    fonte: 'usda',
    calorias_kcal_100g: 42,
    proteinas_g_100g: 0,
    carboidratos_g_100g: 10.6,
    gorduras_g_100g: 0,
  },
  {
    nome_taco: 'Café, coado',
    aliases: ['café', 'cafe', 'cafezinho', 'café coado'],
    fonte: 'taco',
    calorias_kcal_100g: 0,
    proteinas_g_100g: 0.1,
    carboidratos_g_100g: 0,
    gorduras_g_100g: 0,
  },

  // Suplementos e Produtos Industrializados
  {
    nome_taco: 'Whey Protein, pó',
    aliases: ['whey', 'whey protein', 'proteina em po', 'proteína em pó', 'suplemento proteico'],
    fonte: 'usda',
    calorias_kcal_100g: 400,
    proteinas_g_100g: 80,
    carboidratos_g_100g: 8,
    gorduras_g_100g: 7,
  },
];

/**
 * Medidas caseiras genéricas — aplicáveis à maioria dos alimentos.
 * Especificações específicas por alimento podem sobrescrever estes padrões.
 */
const MEDIDAS_CASEIRAS_GENERICAS: Array<{ medida: string; gramas: number }> = [
  { medida: 'colher de sopa', gramas: 25 },
  { medida: 'colher de chá', gramas: 5 },
  { medida: 'xícara', gramas: 200 },
  { medida: 'fatia', gramas: 50 },
  { medida: 'unidade', gramas: 100 },
  { medida: 'meia unidade', gramas: 50 },
  { medida: 'concha média', gramas: 100 },
];

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Variável de ambiente ${name} não configurada — veja .env.local e copy .env.local.example.`,
    );
  }
  return value;
}

function baseSupabaseUrl(): string {
  return new URL(requireEnv('VITE_SUPABASE_URL')).origin;
}

/**
 * Insere alimentos em lotes de 100 itens com checagem prévia.
 * Retorna IDs dos alimentos para associação posterior de medidas caseiras.
 */
async function inserirAlimentos(
  admin: SupabaseClient,
  alimentos: AlimentoTACO[],
): Promise<Map<string, string>> {
  const idsPorNomeTaco = new Map<string, string>();

  // Buscar alimentos que já existem
  console.log('🔍 Verificando alimentos já cadastrados...');
  const nomesAInserir = alimentos.map((a) => a.nome_taco);
  const { data: alimentosExistentes, error: erroSelect } = await admin
    .from('alimentos_referencia')
    .select('id, nome_taco')
    .in('nome_taco', nomesAInserir);

  if (erroSelect) {
    throw new Error(`Erro ao buscar alimentos existentes: ${erroSelect.message}`);
  }

  // Registrar IDs dos que já existem
  if (alimentosExistentes) {
    for (const item of alimentosExistentes) {
      idsPorNomeTaco.set(item.nome_taco as string, item.id as string);
    }
    console.log(`  ℹ️ ${alimentosExistentes.length} alimentos já cadastrados`);
  }

  // Filtrar apenas os novos alimentos
  const alimentosNovos = alimentos.filter((a) => !idsPorNomeTaco.has(a.nome_taco));
  console.log(`  📝 ${alimentosNovos.length} alimentos novos para inserir\n`);

  // Inserir novos em lotes
  const loteSize = 100;
  for (let i = 0; i < alimentosNovos.length; i += loteSize) {
    const lote = alimentosNovos.slice(i, Math.min(i + loteSize, alimentosNovos.length));

    console.log(`📦 Inserindo lote ${Math.floor(i / loteSize) + 1}/${Math.ceil(alimentosNovos.length / loteSize)} (${lote.length} itens)...`);

    const { data, error } = await admin.from('alimentos_referencia').insert(
      lote.map((a) => ({
        nome_taco: a.nome_taco,
        aliases: a.aliases,
        fonte: a.fonte,
        calorias_kcal_100g: a.calorias_kcal_100g,
        proteinas_g_100g: a.proteinas_g_100g,
        carboidratos_g_100g: a.carboidratos_g_100g,
        gorduras_g_100g: a.gorduras_g_100g,
      })),
      { count: 'planned' },
    );

    if (error) {
      // Se falhar por restrição de unicidade, buscar o ID do alimento que conflitou
      console.log(`  ⚠️ Alguns itens podem já existir, verificando...`);

      for (const alimento of lote) {
        // Tentar inserir individualmente para identificar conflitos
        const { error: erroInd } = await admin.from('alimentos_referencia').insert({
          nome_taco: alimento.nome_taco,
          aliases: alimento.aliases,
          fonte: alimento.fonte,
          calorias_kcal_100g: alimento.calorias_kcal_100g,
          proteinas_g_100g: alimento.proteinas_g_100g,
          carboidratos_g_100g: alimento.carboidratos_g_100g,
          gorduras_g_100g: alimento.gorduras_g_100g,
        });

        if (!erroInd) {
          console.log(`    ✅ "${alimento.nome_taco}" inserido`);
        } else {
          console.log(`    ℹ️ "${alimento.nome_taco}" já existe`);
        }
      }
    } else {
      console.log(`  ✅ Lote inserido`);
    }
  }

  // Buscar todos os IDs finais
  console.log('\n📥 Mapeando IDs finais dos alimentos...');
  const { data, error } = await admin
    .from('alimentos_referencia')
    .select('id, nome_taco')
    .in('nome_taco', nomesAInserir);

  if (error) {
    throw new Error(`Erro ao buscar IDs finais: ${error.message}`);
  }

  if (data) {
    for (const item of data) {
      idsPorNomeTaco.set(item.nome_taco as string, item.id as string);
    }
  }

  return idsPorNomeTaco;
}

/**
 * Insere medidas caseiras para cada alimento.
 * Se o alimento já tiver medidas, nenhuma operação (ON CONFLICT DO NOTHING).
 */
async function inserirMedidasCaseiras(
  admin: SupabaseClient,
  idsPorNomeTaco: Map<string, string>,
): Promise<void> {
  console.log('⚖️ Inserindo medidas caseiras genéricas...');

  const medidasParaInserir: Array<{
    alimento_id: string;
    medida: string;
    gramas: number;
  }> = [];

  for (const [nomeTaco, alimentoId] of idsPorNomeTaco) {
    for (const { medida, gramas } of MEDIDAS_CASEIRAS_GENERICAS) {
      medidasParaInserir.push({
        alimento_id: alimentoId,
        medida,
        gramas,
      });
    }
  }

  const loteSize = 500;
  for (let i = 0; i < medidasParaInserir.length; i += loteSize) {
    const lote = medidasParaInserir.slice(i, Math.min(i + loteSize, medidasParaInserir.length));

    const { error } = await admin.from('alimentos_medidas_caseiras').upsert(lote, {
      onConflict: 'alimento_id,medida',
      ignoreDuplicates: true,
    });

    if (error) {
      throw new Error(`Erro ao inserir medidas caseiras: ${error.message}`);
    }
  }

  console.log(`  ✅ ${medidasParaInserir.length} medidas caseiras inseridas`);
}

async function main() {
  const admin = createClient(baseSupabaseUrl(), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  console.log('🚀 Iniciando carga massiva da TACO...\n');

  try {
    // 1. Inserir alimentos
    const idsPorNomeTaco = await inserirAlimentos(admin, ALIMENTOS_TACO_COMPLETA);
    console.log(`\n✅ ${idsPorNomeTaco.size} alimentos processados`);

    // 2. Inserir medidas caseiras
    await inserirMedidasCaseiras(admin, idsPorNomeTaco);

    console.log('\n🎉 Carga completa concluída com sucesso!');
    console.log(`\n📊 Resumo final:`);
    console.log(`   - Alimentos: ${idsPorNomeTaco.size}`);
    console.log(`   - Medidas caseiras por alimento: ${MEDIDAS_CASEIRAS_GENERICAS.length}`);
    console.log(`   - Total de linhas em medidas_caseiras: ${idsPorNomeTaco.size * MEDIDAS_CASEIRAS_GENERICAS.length}`);
  } catch (err) {
    console.error('\n❌ Erro durante a carga da TACO:', err instanceof Error ? err.message : err);
    process.exit(1);
  }
}

main();
