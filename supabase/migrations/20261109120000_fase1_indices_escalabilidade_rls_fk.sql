-- Fase 1 do Roadmap de Escalabilidade (RELATÓRIO 20261109_0001,
-- docs/log_dev/) — índices B-Tree de otimização física, sem nenhuma
-- mudança de lógica de negócio/RPC/RLS (Restrição explícita da tarefa).
--
-- Auditoria completa do schema (todas as 54 migrations até aqui, ver
-- relatório) levantou TODA coluna usada (a) em cláusula USING/WITH CHECK
-- de uma policy de RLS (direto ou via `exists (...)` voltando pra tabela
-- externa) e (b) toda Foreign Key do schema. Na prática, todo caso (a)
-- já é um caso (b) — nenhuma policy compara uma coluna que não seja
-- também uma FK — então as duas listas colapsam numa só.
--
-- A GRANDE MAIORIA dessas colunas JÁ tem índice (quase sempre como
-- coluna líder de um índice composto já existente, ex.
-- `idx_anamneses_usuario_status (usuario_id, status_vigencia)`, ou como
-- coluna líder de uma PK composta, ex. `anamneses_alergias (anamnese_id,
-- alergia_id)`) — essas NÃO entram aqui de novo (um índice duplicado só
-- custaria espaço/escrita, sem ganho nenhum). Esta migration cobre
-- EXCLUSIVAMENTE as colunas que sobraram descobertas: FKs/colunas de RLS
-- que são a coluna TRAILING (não líder) de uma PK composta, ou que nunca
-- tiveram nenhum índice próprio.
--
-- `create index if not exists` em todas — idempotente, roda de novo sem
-- erro nem efeito colateral se algum dia for reaplicada.

-- ============================================================================
-- planejamento_clinico — RLS compara as 2 colunas direto (`auth.uid() =
-- profissional_id or auth.uid() = paciente_id_anonimo`), nenhuma delas é
-- a PK da tabela (migration `20260706191827`).
-- ============================================================================
create index if not exists idx_planejamento_clinico_profissional_id
  on planejamento_clinico (profissional_id);

create index if not exists idx_planejamento_clinico_paciente_id_anonimo
  on planejamento_clinico (paciente_id_anonimo);

-- ============================================================================
-- resultados_exames.marcador_codigo — FK pra marcadores_referencia,
-- coluna TRAILING (2ª) do índice composto `idx_resultados_exames_
-- usuario_marcador_data (usuario_id, marcador_codigo, data_coleta)` —
-- não serve pra lookup direto por marcador_codigo sozinho.
-- ============================================================================
create index if not exists idx_resultados_exames_marcador_codigo
  on resultados_exames (marcador_codigo);

-- ============================================================================
-- atividades_fisicas_treinos.tipo_atividade_codigo — FK pra
-- tipos_atividades_fisicas(nome_codigo), sem índice próprio (o único
-- índice da tabela é por usuario_id/data).
-- ============================================================================
create index if not exists idx_atividades_fisicas_treinos_tipo_atividade_codigo
  on atividades_fisicas_treinos (tipo_atividade_codigo);

-- ============================================================================
-- RBAC (D3, migration `20260811200000`) — as duas tabelas de junção M:N
-- já têm índice na coluna LÍDER da própria PK composta
-- (`idx_usuario_papeis_usuario`/`idx_papeis_permissoes_papel`); a coluna
-- TRAILING de cada PK composta nunca teve índice próprio.
-- ============================================================================
create index if not exists idx_usuario_papeis_papel_id
  on usuario_papeis (papel_id);

create index if not exists idx_papeis_permissoes_permissao_id
  on papeis_permissoes (permissao_id);

-- ============================================================================
-- usuario_alergias.alergia_id — coluna TRAILING da PK composta
-- (usuario_id, alergia_id), migration `20260811210000`.
-- ============================================================================
create index if not exists idx_usuario_alergias_alergia_id
  on usuario_alergias (alergia_id);

-- ============================================================================
-- anamneses.profissional_id — quem prescreveu (RELATÓRIO 20260917_0001,
-- Anamnese Profissional), nullable, nunca teve índice próprio (o único
-- índice da tabela é por usuario_id/status_vigencia).
-- ============================================================================
create index if not exists idx_anamneses_profissional_id
  on anamneses (profissional_id);

-- ============================================================================
-- Tabelas N:N de anamneses (migration `20260811240000`) — cada uma já
-- tem índice na coluna LÍDER da PK composta (`anamnese_id`); a coluna
-- TRAILING (catálogo referenciado) nunca teve índice próprio.
-- ============================================================================
create index if not exists idx_anamneses_alergias_alergia_id
  on anamneses_alergias (alergia_id);

create index if not exists idx_anamneses_problemas_saude_problema_saude_id
  on anamneses_problemas_saude (problema_saude_id);

create index if not exists idx_anamneses_atividades_atividade_id
  on anamneses_atividades (atividade_id);

-- anamneses_atividades_dias (migration `20260915120000`) — PK composta de
-- 3 colunas (anamnese_id, atividade_id, dia_semana); atividade_id é a 2ª,
-- não a líder, sem índice próprio.
create index if not exists idx_anamneses_atividades_dias_atividade_id
  on anamneses_atividades_dias (atividade_id);

-- ============================================================================
-- objetivos_alimentares.profissional_id — quem prescreveu a meta (N10,
-- migration `20260812110000`), nullable, nunca teve índice próprio (o
-- único índice da tabela é por usuario_id/tipo_dia/status_vigencia; a FK
-- `anamnese_id` já ganhou o seu em `20261102140000`).
-- ============================================================================
create index if not exists idx_objetivos_alimentares_profissional_id
  on objetivos_alimentares (profissional_id);

-- ============================================================================
-- sugestao_meta.anamnese_id — FK nullable pra anamneses (migration
-- `20260915120000`), nunca teve índice próprio (o único índice da tabela
-- é por usuario_id/status_vigencia).
-- ============================================================================
create index if not exists idx_sugestao_meta_anamnese_id
  on sugestao_meta (anamnese_id);

-- ============================================================================
-- Blocos complementares da Anamnese (migration `20260918100000`) —
-- `anamnese_id` é FK direta (não há PK composta aqui, cada linha tem seu
-- próprio `id`), nunca teve índice próprio.
-- ============================================================================
create index if not exists idx_anamneses_medicamentos_anamnese_id
  on anamneses_medicamentos (anamnese_id);

create index if not exists idx_anamneses_suplementos_anamnese_id
  on anamneses_suplementos (anamnese_id);

create index if not exists idx_anamneses_exames_laboratoriais_anamnese_id
  on anamneses_exames_laboratoriais (anamnese_id);
