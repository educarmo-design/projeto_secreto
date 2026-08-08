-- N20 (Fase 0, Parte 9.1) — Re-seed de embeddings reais + índice vetorial
-- (Parte 2 C3 / Parte 12 R16).
--
-- CONTEXTO REAL (investigado antes de escrever esta migration, não presumido):
-- `alimentos_referencia` tem hoje 625 linhas, TODAS com `embedding` não-nulo —
-- não ~8.000 como o Mestre v7.0 registra (Parte 2 F45/K), e não "23 mock, o
-- resto vazio". Pelo menos parte dessas 625 foi semeada num momento em que
-- `text-embedding-004` ainda existia na API; 23 delas foram completadas depois
-- com um vetor MOCK (hash MD5 determinístico) quando a chave usada não tinha
-- permissão de embeddings — ver RELATÓRIO DE FIM DE TAREFA (docs/log_dev/
-- 20260807_0002.md) para os comandos de auditoria que confirmaram isso direto
-- no banco. Nenhuma linha hoje tem como se provar "veio do modelo real atual"
-- só olhando pra ela — daí a coluna `embedding_model` abaixo.
--
-- ============================================================================
-- 1. Proveniência do embedding — resolve dois problemas de uma vez
-- ============================================================================
-- Sem isto, distinguir "mock" de "real desatualizado" de "real atual" exigiria
-- um heurística frágil (norma L2, distribuição de valores) que nenhuma delas
-- prova nada com certeza — testei isso manualmente e um mock pode sair
-- normalizado igual a um real. A resposta correta é registrar a origem no
-- momento da escrita, não tentar adivinhar depois.
--
-- Com a coluna, o script de seed (scripts/seed_food_embeddings.ts) faz o
-- WHERE ficar auto-descritivo e idempotente pra sempre, não só nesta rodada:
--   embedding IS NULL OR embedding_model IS NULL OR embedding_model <> :atual
-- Cobre os 3 casos (nunca semeado / semeado antes desta coluna existir, os
-- 625 de hoje / semeado com um modelo que não é mais o `EMBEDDING_MODEL_NAME`
-- vigente) com a MESMA query — e ganha de brinde a Regra 20 do Mestre
-- ("trocar o modelo obriga a re-semear"): troque a secret, rode o script de
-- novo, ele re-semeia sozinho só o que ficou pra trás.
alter table alimentos_referencia
  add column embedding_model text;

comment on column alimentos_referencia.embedding_model is
  'Nome do modelo (valor de EMBEDDING_MODEL_NAME no momento da escrita) que gerou o vetor em `embedding` — NULL para toda linha semeada antes desta coluna existir (inclui os 23 mock E os reais pré-existentes, ambos precisam ser re-semeados para o estado ficar auditável). Usado pelo WHERE de scripts/seed_food_embeddings.ts para reprocessar só o que está desatualizado ou nunca foi carimbado.';

-- ============================================================================
-- 2. Índice vetorial — HNSW, não IVFFlat
-- ============================================================================
-- `set local search_path`: mesmo bug já documentado em
-- 20260729120000_create_match_alimentos.sql — a conexão que `supabase db
-- push` usa não inclui `extensions` no search_path por padrão, e tanto o tipo
-- `vector` quanto a classe de operador `vector_cosine_ops` (registrada pelo
-- pgvector no schema `extensions`) precisam resolver no momento do CREATE.
set local search_path = public, extensions;

-- Decisão HNSW vs IVFFlat (ver RELATÓRIO para a justificativa completa):
-- IVFFlat precisa de um passo de treino (k-means) sobre os dados já
-- carregados para escolher `lists` direito — é por isso que a migration
-- 20260727120000 explicitamente NÃO criou índice nenhum na época (a tabela
-- só tinha 5 linhas, todas com embedding nulo: não havia o que treinar).
-- HNSW não tem essa dependência de "dado já lá antes de indexar" — o grafo é
-- construído incrementalmente, sem fase de treino, e dá recall melhor por
-- padrão sem precisar calibrar `lists`. Com ~625 linhas hoje (crescendo para
-- alguns milhares, não milhões), o custo de build/manutenção do HNSW é
-- irrelevante e a ausência de retreino quando o catálogo crescer é a
-- vantagem que importa aqui — sem isso, IVFFlat exigiria recriar o índice
-- periodicamente para não degradar conforme `alimentos_referencia` cresce.
--
-- `vector_cosine_ops`: mesma família de distância do operador `<=>` já usado
-- em match_alimentos (20260729120000) — um índice com operator class
-- diferente da consulta não seria usado pelo planner.
--
-- Sem `concurrently`: migrations do Supabase CLI rodam dentro de uma
-- transação, e `create index concurrently` não pode rodar dentro de uma
-- transação (erro do Postgres, não escolha nossa). Aceitável neste volume —
-- ~625 linhas hoje bloqueiam a tabela por uma fração de segundo; não há
-- tráfego de produção real ainda para esse lock incomodar.
create index idx_alimentos_referencia_embedding_hnsw
  on alimentos_referencia
  using hnsw (embedding extensions.vector_cosine_ops);

-- ============================================================================
-- 3. GRANT explícito (Parte 0.10 — obrigatório em toda migration)
-- ============================================================================
-- Nenhum GRANT novo necessário: `embedding_model` é coluna da mesma tabela
-- `alimentos_referencia`, que já concede select a `authenticated` (
-- 20260716120000) e select/insert/update a `service_role` (20260727120000) —
-- GRANT em Postgres é por tabela, não por coluna (mesma nota já registrada em
-- 20260727120000 ao acrescentar a coluna `embedding`). O índice não precisa
-- de GRANT — não é um objeto executável/consultável diretamente.
