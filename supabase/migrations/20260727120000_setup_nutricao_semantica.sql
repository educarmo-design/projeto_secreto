-- F45 continuação (Adendo v5.1, seção A.3) — Busca Semântica + Cache de
-- Sinônimos para o casamento "texto livre do Gemini -> alimento" no Passo 2
-- do F10, além do que o casamento exato/substring por
-- `alimentos_referencia.aliases` (20260716120000) já cobre. Objetivo:
-- resolver gírias/sinônimos que o Gemini pode gerar e que não estão
-- cadastrados como alias literal (ex.: "arroz soltinho", "bifinho") via
-- embedding + similaridade de cosseno, e memoizar cada termo já resolvido
-- num cache — depois da primeira resolução, o mesmo termo nunca paga o custo
-- de uma nova busca vetorial.
--
-- DESVIO REGISTRADO EM RELAÇÃO AO PEDIDO ORIGINAL (ver RELATÓRIO DE FIM DE
-- TAREFA): a tarefa pedia uma tabela NOVA `alimentos_taco`. Investigando o
-- schema atual antes de escrever esta migration, `alimentos_referencia`
-- (20260716120000) já É essa tabela — id, nome canônico, macros por 100g —
-- e já é lida em produção por `extract-metric-photo`
-- (supabase/functions/extract-metric-photo/index.ts). Criar uma segunda
-- tabela `alimentos_taco` do zero duplicaria o catálogo nutricional (dois
-- lugares para curar os mesmos dados, duas fontes de verdade que podem
-- divergir) e nasceria desconectada de tudo que já existe — nada no app leria
-- dela. Em vez disso: ALTER em `alimentos_referencia` acrescentando a coluna
-- de embedding, e a nova tabela de cache referencia essa mesma tabela já
-- existente. `alimentos_taco` não é criada nesta migration.

-- ============================================================================
-- 1. Extensão pgvector
-- ============================================================================
-- `with schema extensions`: mesma convenção do Supabase hospedado — o
-- catálogo de extensões da instância fica separado do schema `public`, e
-- `extra_search_path` (supabase/config.toml) já inclui `extensions`, então
-- `vector(768)` resolve sem precisar qualificar o schema nas colunas abaixo.
create extension if not exists vector with schema extensions;

-- ============================================================================
-- 2. alimentos_referencia — acrescenta o vetor semântico
-- ============================================================================
-- 768 dimensões: padrão do `text-embedding-004` do Gemini (mesma família de
-- modelo já usada pelo resto do pipeline de IA do app, ver
-- extract-metric-photo). Nullable de propósito — a ingestão real dos
-- embeddings (rodar o texto de `nome_taco`/`aliases` de cada linha existente
-- através do `text-embedding-004` e popular esta coluna) é trabalho de uma
-- tarefa separada, listada como pendência no RELATÓRIO. As 5 linhas de seed
-- de 20260716120000 nascem com `embedding` nulo.
alter table alimentos_referencia
  add column embedding extensions.vector(768);

comment on column alimentos_referencia.embedding is
  'Embedding semântico (Gemini text-embedding-004, 768 dimensões) de nome_taco + aliases — usado pela busca por similaridade de cosseno para casar sinônimos/gírias que o casamento exato/substring de aliases não cobre. NULL até a tarefa de ingestão popular esta coluna.';

-- Nenhum índice ivfflat/hnsw criado nesta migration: esses índices são
-- treinados por k-means sobre os dados existentes, e com a tabela tendo
-- apenas as 5 linhas de seed (todas com embedding NULO agora), treinar um
-- índice hoje não teria nenhum dado real para indexar. Busca por
-- similaridade continua funcionando via sequential scan (`order by embedding
-- <=> :query limit N`) nesse volume; o índice fica registrado como
-- pendência para quando a ingestão real popular a coluna (ver RELATÓRIO).

-- ============================================================================
-- 3. cache_sinonimos_alimentos — memoization de termo -> alimento resolvido
-- ============================================================================
create table cache_sinonimos_alimentos (
  id bigserial primary key,
  -- Termo já normalizado (minúsculas, sem acento — mesma normalização que o
  -- Edge Function já aplica antes de casar contra `aliases`) usado como
  -- chave de memoization. Único: o mesmo termo sempre resolve para o mesmo
  -- alimento, nunca é ambíguo.
  termo_buscado text not null,
  alimento_id uuid not null references alimentos_referencia (id) on delete cascade,
  contagem_hits integer not null default 1 check (contagem_hits > 0),
  criado_em timestamptz not null default now(),
  ultimo_hit_em timestamptz not null default now(),
  unique (termo_buscado)
);

create index idx_cache_sinonimos_alimento_id
  on cache_sinonimos_alimentos (alimento_id);

alter table cache_sinonimos_alimentos enable row level security;

create policy "cache_sinonimos_select_authenticated"
  on cache_sinonimos_alimentos for select
  to authenticated
  using (true);

-- Sem policy de INSERT/UPDATE/DELETE para `authenticated`: só a Edge
-- Function (service_role) grava o cache — mesma regra de
-- `alimentos_referencia`/`alimentos_medidas_caseiras`, curadoria/escrita
-- nunca é do cliente.

-- ============================================================================
-- 4. GRANT explícito (Parte 0.10 — obrigatório em toda migration)
-- ============================================================================
-- alimentos_referencia: já tinha `grant select ... to authenticated` desde
-- 20260716120000 (cobre a coluna nova `embedding` também — GRANT em Postgres
-- é por tabela, não por coluna). O que faltava, e esta migration inaugura, é
-- o grant explícito para `service_role`: até aqui nenhuma migration deste
-- projeto concedeu privilégio de tabela a `service_role` explicitamente —
-- mas a partir de agora a ingestão de embeddings (Edge Function/script,
-- rodando como service_role) precisa escrever nesta tabela, então o
-- privilégio deixa de ser implícito e passa a existir na ACL de verdade.
grant select, insert, update on alimentos_referencia to service_role;

-- cache_sinonimos_alimentos: authenticated só lê; toda escrita (insert do
-- primeiro hit, update do contador nos hits seguintes) é do service_role.
grant select on cache_sinonimos_alimentos to authenticated;
grant select, insert, update on cache_sinonimos_alimentos to service_role;
