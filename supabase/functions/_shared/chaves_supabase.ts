// _shared/chaves_supabase.ts — leitura das chaves do próprio projeto Supabase
// dentro das Edge Functions (N44 / S8.1 do Documento Mestre v9.2.1).
//
// A Supabase está descontinuando `anon`/`service_role` (JWTs) em favor de
// `sb_publishable_…`/`sb_secret_…`. Dentro das Edge Functions, a plataforma
// injeta as chaves novas como DICIONÁRIOS JSON (`SUPABASE_PUBLISHABLE_KEYS`,
// `SUPABASE_SECRET_KEYS`, ex.: {"default":"sb_secret_…"}) e mantém as
// variáveis antigas (`SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`) só por
// compatibilidade — elas carregam as chaves LEGADAS e param de funcionar
// quando o par legado for desativado no Dashboard (Passo 4).
//
// Por isso cada leitor tenta a chave nova primeiro e cai na legada se a nova
// não existir. Isso é o que permite o aceite do N44 "Parte 1": app e painel
// funcionando com as chaves novas ENQUANTO as legadas ainda estão ativas, e
// a volta, se algo quebrar, ser só uma variável. Depois do Passo 4 o
// fallback legado deixa de ser alcançado; removê-lo é limpeza opcional.
//
// Este módulo NUNCA loga nem devolve o valor da chave em mensagem de erro.

/** Nome do item usado quando o dicionário tem mais de uma chave. */
const NOME_CHAVE_PADRAO = 'default';

/**
 * Lê um dicionário JSON de chaves (`{"default":"sb_…"}`) e devolve a chave
 * `default`, ou a primeira se não houver `default`. Devolve `undefined` se a
 * variável não existe, não é JSON válido ou está vazia — nunca lança, para um
 * dicionário malformado cair no fallback legado em vez de derrubar a função.
 */
function lerDicionarioDeChaves(nomeVariavel: string): string | undefined {
  const bruto = Deno.env.get(nomeVariavel);
  if (!bruto) return undefined;
  try {
    const dicionario = JSON.parse(bruto);
    if (dicionario === null || typeof dicionario !== 'object') return undefined;
    const valores = dicionario as Record<string, unknown>;
    const escolhida = valores[NOME_CHAVE_PADRAO] ?? Object.values(valores)[0];
    return typeof escolhida === 'string' && escolhida !== '' ? escolhida : undefined;
  } catch {
    return undefined;
  }
}

/** Chave privilegiada (substitui `SUPABASE_SERVICE_ROLE_KEY`). Ignora RLS — só server-side. */
export function lerChaveSecreta(): string | undefined {
  return lerDicionarioDeChaves('SUPABASE_SECRET_KEYS') ||
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || undefined;
}

/** Chave pública (substitui `SUPABASE_ANON_KEY`). Respeita RLS. */
export function lerChavePublicavel(): string | undefined {
  return lerDicionarioDeChaves('SUPABASE_PUBLISHABLE_KEYS') ||
    Deno.env.get('SUPABASE_ANON_KEY') || undefined;
}
