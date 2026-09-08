/**
 * RELATÓRIO 20260908_0001 (Mestre v8.0, Regra 23 — Falhar Visível, Regra 26
 * — Curadoria Humana): script de CURADORIA — grava no banco, diferente de
 * `scripts/auditoria_catalogo.ts` (só leitura). Executa exatamente o plano
 * aprovado pelo fundador em cima do RELATÓRIO 20260902_0003, e SÓ isso —
 * nenhuma decisão nova tomada aqui.
 *
 * Só faz UPDATE (nunca DELETE nenhuma linha, nunca INSERT). Idempotente: lê
 * o estado atual e só grava o que ainda não está aplicado — rodar de novo
 * não duplica nem reverte nada.
 *
 * 3 mudanças:
 *
 * 1. DIFERENCIAR DUPLICATAS (`nome_taco` idêntico em 2 linhas, achado
 *    20260902_0003): "Pão de queijo" (2 ids) e "Café, coado" (2 ids).
 *    Renomeados com um complemento GROUNDED no próprio dado já cadastrado
 *    (não inventado): a linha de "Pão de queijo" com `medida_padrao_qtd`
 *    50g já tinha o alias "pão de queijo grande" — vira "..., grande"; a
 *    de 30g vira "..., tradicional". A linha de "Café, coado" com o alias
 *    "cafe coado fraco" já dizia "fraco" — vira "..., fraco"; a outra
 *    (2kcal/100g, a única com 2 medidas cadastradas) vira "..., tradicional".
 *    Só `nome_taco` muda — os `aliases` de cada linha ficam intactos (uma
 *    busca genérica por "pão de queijo"/"café" continua batendo nas duas,
 *    e agora o fix de algoritmo em `index.ts` devolve ambiguidade — `null`
 *    — em vez de arbitrar, exatamente o comportamento correto).
 *
 * 2. APAGAR TOTALMENTE os aliases genéricos demais: `fruta`, `suco`,
 *    `verdura`, `hortalica` — de TODAS as linhas onde aparecem (8 + 4 + 3 +
 *    2 = 17 linhas). Estes eram os que cruzavam categorias INTEIRAS
 *    diferentes (ex.: "fruta" sempre resolvia pra "Atemóia, crua",
 *    aparecesse a fruta que fosse).
 *
 * 3. ELEGER 1 DONO só pros aliases `leite`/`iogurte`/`achocolatado` —
 *    mantém no alimento certo, remove dos outros 3/2/1:
 *      - leite       -> só em "Leite, de vaca, integral"
 *      - iogurte     -> só em "Iogurte natural"
 *      - achocolatado -> só em "Leite, de vaca, achocolatado" (líquido,
 *                        não o pó — decisão do fundador)
 *
 * DELIBERADAMENTE NÃO TOCADO (decisão do fundador): `peixe`, `carne`,
 * `salgado`, `acompanhamento` continuam ambíguos nos dados — é o fix de
 * algoritmo em `extract-metric-photo/index.ts` (Regra Anti-Sequestro +
 * falha visível em empate) que passa a tratar isso corretamente, sem
 * precisar apagar nem eleger nada nesses 4.
 *
 * Uso:
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
 *     deno run --allow-net --allow-env scripts/curadoria_aliases.ts --dry-run
 *   (sem --dry-run: aplica de verdade)
 *
 * Mesma service role key dos outros scripts em scripts/ (guardada em
 * web_painel/.env.local, nunca commitada).
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const DRY_RUN = Deno.args.includes('--dry-run');

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('❌ Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no ambiente.');
  Deno.exit(1);
}

const admin = createClient(SUPABASE_URL, SERVICE_KEY);

// Mesma normalização de `index.ts` (duplicada de propósito — script
// standalone, não vale importar por uma função não exportada do módulo).
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
}

console.log(`${DRY_RUN ? '🔍 DRY-RUN (nenhuma escrita)' : '✍️  APLICANDO DE VERDADE'} — curadoria de aliases.\n`);

const { data, error } = await admin.from('alimentos_referencia').select('id, nome_taco, aliases').order('nome_taco');
if (error) throw error;
const linhas = (data ?? []) as LinhaAlimento[];
console.log(`Catálogo: ${linhas.length} alimentos.\n`);

interface Atualizacao {
  id: string;
  nomeTacoAtual: string;
  novoNomeTaco?: string;
  aliasesAtuais?: string[];
  novosAliases?: string[];
  motivo: string;
}

const atualizacoes: Atualizacao[] = [];

// ─────────────────────────────────────────────────────────────────────────
// 1. Diferenciar duplicatas exatas (só nome_taco muda, IDs fixos —
// confirmados por consulta direta ao banco antes de escrever este script)
// ─────────────────────────────────────────────────────────────────────────
const RENOMEACOES_DUPLICATA: { id: string; novoNomeTaco: string; motivo: string }[] = [
  {
    id: '38e42869-58e7-40b7-95be-f5a464eebf4a',
    novoNomeTaco: 'Pão de queijo, tradicional',
    motivo: 'duplicata de "Pão de queijo" — 30g/unidade, sem modificador de tamanho nos aliases',
  },
  {
    id: 'ab40c4ee-f019-4d04-92bf-07abcbe2fb9a',
    novoNomeTaco: 'Pão de queijo, grande',
    motivo: 'duplicata de "Pão de queijo" — 50g/unidade, já tinha alias "pão de queijo grande"',
  },
  {
    id: '52706959-9941-4722-b86c-8884f4fc502c',
    novoNomeTaco: 'Café, coado, tradicional',
    motivo: 'duplicata de "Café, coado" — 2kcal/100g, única com 2 medidas cadastradas (xícara + xícara pequena)',
  },
  {
    id: '3341d3b8-6b77-4883-832f-3b8a6788dc21',
    novoNomeTaco: 'Café, coado, fraco',
    motivo: 'duplicata de "Café, coado" — 0kcal/100g, já tinha alias "cafe coado fraco"',
  },
];

for (const r of RENOMEACOES_DUPLICATA) {
  const linha = linhas.find((l) => l.id === r.id);
  if (!linha) {
    throw new Error(`Renomeação de duplicata: id ${r.id} não encontrado no catálogo — script desatualizado?`);
  }
  if (linha.nome_taco === r.novoNomeTaco) continue; // já aplicado, idempotente
  atualizacoes.push({
    id: r.id,
    nomeTacoAtual: linha.nome_taco,
    novoNomeTaco: r.novoNomeTaco,
    motivo: r.motivo,
  });
}

// ─────────────────────────────────────────────────────────────────────────
// 2. Apagar totalmente os 4 aliases genéricos demais, de qualquer linha
// onde aparecerem
// ─────────────────────────────────────────────────────────────────────────
const ALIASES_REMOVER_TOTALMENTE = new Set(['fruta', 'suco', 'verdura', 'hortalica']);

for (const linha of linhas) {
  const aliases = linha.aliases ?? [];
  const novosAliases = aliases.filter((a) => !ALIASES_REMOVER_TOTALMENTE.has(normalizarTexto(a)));
  if (novosAliases.length === aliases.length) continue; // nada a remover aqui

  const removidos = aliases.filter((a) => ALIASES_REMOVER_TOTALMENTE.has(normalizarTexto(a)));
  const jaTemAtualizacao = atualizacoes.find((u) => u.id === linha.id);
  if (jaTemAtualizacao) {
    jaTemAtualizacao.aliasesAtuais = aliases;
    jaTemAtualizacao.novosAliases = novosAliases;
    jaTemAtualizacao.motivo += ` + remove alias genérico(s): ${removidos.join(', ')}`;
  } else {
    atualizacoes.push({
      id: linha.id,
      nomeTacoAtual: linha.nome_taco,
      aliasesAtuais: aliases,
      novosAliases,
      motivo: `remove alias genérico(s): ${removidos.join(', ')}`,
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 3. Eleger 1 dono só pra "leite"/"iogurte"/"achocolatado" — remove dos
// demais, mantém intacto no dono (confirmado explicitamente, nunca
// assumido).
// ─────────────────────────────────────────────────────────────────────────
const ELEICOES_DE_ALIAS: { alias: string; donoNomeTaco: string }[] = [
  { alias: 'leite', donoNomeTaco: 'Leite, de vaca, integral' },
  { alias: 'iogurte', donoNomeTaco: 'Iogurte natural' },
  { alias: 'achocolatado', donoNomeTaco: 'Leite, de vaca, achocolatado' },
];

for (const eleicao of ELEICOES_DE_ALIAS) {
  const dono = linhas.find((l) => normalizarTexto(l.nome_taco) === normalizarTexto(eleicao.donoNomeTaco));
  if (!dono) {
    throw new Error(`Eleição de alias "${eleicao.alias}": dono "${eleicao.donoNomeTaco}" não encontrado — script desatualizado?`);
  }
  const donoTemAlias = (dono.aliases ?? []).some((a) => normalizarTexto(a) === eleicao.alias);
  if (!donoTemAlias) {
    throw new Error(
      `Eleição de alias "${eleicao.alias}": o dono escolhido ("${eleicao.donoNomeTaco}") NÃO tem esse alias hoje — abortando pra não perder o alias em lugar nenhum.`,
    );
  }

  for (const linha of linhas) {
    if (linha.id === dono.id) continue; // nunca mexe no dono
    const aliases = linha.aliases ?? [];
    const temAlias = aliases.some((a) => normalizarTexto(a) === eleicao.alias);
    if (!temAlias) continue;

    const novosAliases = aliases.filter((a) => normalizarTexto(a) !== eleicao.alias);
    const jaTemAtualizacao = atualizacoes.find((u) => u.id === linha.id);
    if (jaTemAtualizacao) {
      // Encadeia sobre o resultado já computado no passo 2 (se houver),
      // nunca sobre o array original — senão perderia a remoção anterior.
      const base = jaTemAtualizacao.novosAliases ?? aliases;
      jaTemAtualizacao.aliasesAtuais = jaTemAtualizacao.aliasesAtuais ?? aliases;
      jaTemAtualizacao.novosAliases = base.filter((a) => normalizarTexto(a) !== eleicao.alias);
      jaTemAtualizacao.motivo += ` + remove alias "${eleicao.alias}" (dono eleito: "${eleicao.donoNomeTaco}")`;
    } else {
      atualizacoes.push({
        id: linha.id,
        nomeTacoAtual: linha.nome_taco,
        aliasesAtuais: aliases,
        novosAliases,
        motivo: `remove alias "${eleicao.alias}" (dono eleito: "${eleicao.donoNomeTaco}")`,
      });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Aplicar (ou só reportar, em --dry-run)
// ─────────────────────────────────────────────────────────────────────────
console.log(`${atualizacoes.length} linha(s) a atualizar:\n`);
for (const u of atualizacoes) {
  console.log(`— [${u.id}] "${u.nomeTacoAtual}"`);
  if (u.novoNomeTaco) console.log(`    nome_taco: "${u.nomeTacoAtual}" -> "${u.novoNomeTaco}"`);
  if (u.novosAliases) {
    console.log(`    aliases: [${(u.aliasesAtuais ?? []).join(', ')}] -> [${u.novosAliases.join(', ')}]`);
  }
  console.log(`    motivo: ${u.motivo}\n`);
}

if (DRY_RUN) {
  console.log('🔍 DRY-RUN — nenhuma linha foi gravada. Rode sem --dry-run para aplicar de verdade.');
  Deno.exit(0);
}

let sucesso = 0;
for (const u of atualizacoes) {
  const payload: { nome_taco?: string; aliases?: string[] } = {};
  if (u.novoNomeTaco) payload.nome_taco = u.novoNomeTaco;
  if (u.novosAliases) payload.aliases = u.novosAliases;

  const { error: erroUpdate } = await admin.from('alimentos_referencia').update(payload).eq('id', u.id);
  if (erroUpdate) {
    console.error(`❌ Falha ao atualizar [${u.id}]: ${erroUpdate.message}`);
    continue;
  }
  sucesso++;
}

console.log(`\n✅ ${sucesso}/${atualizacoes.length} linha(s) atualizada(s) com sucesso. Nenhuma linha apagada.`);
