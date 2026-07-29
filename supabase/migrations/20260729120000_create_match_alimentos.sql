-- "Cérebro da Busca" — Nutrição Semântica (Adendo v5.1 §A.3/§C.3).
--
-- RPC que a Edge Function `search-food` chama para casar o embedding do
-- termo de busca do usuário (gerado com taskType='RETRIEVAL_QUERY') contra
-- `alimentos_referencia.embedding` (gerado com taskType='RETRIEVAL_DOCUMENT'
-- por scripts/seed_food_embeddings.ts) via distância de cosseno (`<=>`,
-- operador do pgvector, habilitado em 20260727120000).
--
-- `security invoker` (não `definer`): `alimentos_referencia` já concede
-- `select` a `authenticated` com uma policy RLS `using (true)`
-- (20260716120000) — é um dicionário público do produto, ninguém que já
-- pode consultar a tabela diretamente ganha nada a mais podendo chamar esta
-- função. Elevar privilégio aqui seria escopo maior que o necessário (mesma
-- régua de mínimo privilégio já aplicada a
-- resolver_usuario_id_por_email, que É `security definer` porque
-- PRECISA ler auth.users — este caso é o oposto).
--
-- `set local search_path`: BUG CORRIGIDO (rodando pela primeira vez contra o
-- banco real) — `vector` sem qualificar deu `ERROR: type vector does not
-- exist (SQLSTATE 42704)`. `extra_search_path` do supabase/config.toml só
-- vale para a sessão do PostgREST; a conexão que `supabase db push` usa para
-- rodar esta migration não inclui `extensions` no search_path por padrão. E
-- diferente de PL/pgSQL, uma função `language sql` tem o corpo analisado já
-- no CREATE (não só na primeira chamada), então tanto o tipo do parâmetro
-- quanto o operador `<=>` (também definido no schema `extensions` pelo
-- pgvector) precisam resolver já nesse momento — daí o `set local`
-- explícito ANTES do `create function`, além de qualificar o tipo do
-- parâmetro por precaução.
set local search_path = public, extensions;

create or replace function match_alimentos(
  query_embedding extensions.vector(768),
  match_threshold float,
  match_count int
)
returns table (
  id uuid,
  nome_taco text,
  aliases text[],
  calorias_kcal_100g numeric,
  proteinas_g_100g numeric,
  carboidratos_g_100g numeric,
  gorduras_g_100g numeric,
  similarity float
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select
    a.id,
    a.nome_taco,
    a.aliases,
    a.calorias_kcal_100g,
    a.proteinas_g_100g,
    a.carboidratos_g_100g,
    a.gorduras_g_100g,
    1 - (a.embedding <=> query_embedding) as similarity
  from alimentos_referencia a
  where a.embedding is not null
    and 1 - (a.embedding <=> query_embedding) > match_threshold
  order by a.embedding <=> query_embedding asc
  limit match_count;
$$;

-- GRANT explícito (Parte 0.10 — obrigatório em toda migration). `revoke ...
-- from public` primeiro: por padrão toda função nova é executável por
-- `public` (que inclui `anon`) — como a tabela por trás só concede select a
-- `authenticated`, fechamos a mesma porta aqui, e listamos os dois papéis
-- que legitimamente precisam chamar isto: `authenticated` (uso direto
-- futuro, ex.: um cliente chamando a RPC sem passar pela Edge Function) e
-- `service_role` (o caminho real hoje — `search-food` chama com a service
-- role, mesmo padrão de toda Edge Function deste projeto que já segura
-- essa chave).
revoke execute on function match_alimentos(extensions.vector(768), float, int) from public;
grant execute on function match_alimentos(extensions.vector(768), float, int) to authenticated;
grant execute on function match_alimentos(extensions.vector(768), float, int) to service_role;
