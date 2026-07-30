-- F34 — coleta_diaria (Documento Mestre §3.5 G.2): EAV genérico para
-- leituras FREQUENTES de device/OCR/manual (pressão, SpO2, glicose de dedo,
-- peso, temperatura, autorrelatos, refeição) — distinto de `resultados_exames`
-- (G.1, EAV para exame LABORATORIAL pontual) e de `metricas_saude_diarias`
-- (G.3, colunas fixas, 1 linha/usuário/dia, agregado de wearable).
--
-- Entidade/Atributo/Valor: cada linha é UMA leitura de UM atributo. O valor
-- vive em uma de duas colunas tipadas (nunca as duas ao mesmo tempo):
--   - `valor_numerico` para atributos escalares (peso_kg, glicose_jejum,
--     pressao_sistolica, ...) — um número por leitura.
--   - `valor_jsonb` para atributos compostos (`refeicao`: lista de itens +
--     totais, já calculados pelo backend em `extract-metric-photo`) — EAV
--     puro exigiria uma linha por macro por item (calorias, proteínas,
--     carboidratos, gorduras × N itens), o que fragmenta uma leitura atômica
--     (uma refeição inteira, confirmada de uma vez) em dezenas de linhas sem
--     nenhum ganho — o JSONB mantém a leitura como uma unidade só, e ainda é
--     uma "coluna Valor" no sentido EAV (só que estruturada).
--
-- F10 Passo 3 (ConfirmacaoPratoPage) é o primeiro gravador: confirma um
-- prato → grava UMA linha aqui, atributo='refeicao', origem='ocr_refeicao'.
-- Demais tipos de aparelho (glicosímetro/pressão/balança via
-- HealthPayloadDialog) continuam sem persistência própria — fora do escopo
-- desta migration/tarefa (ver RELATÓRIO DE FIM DE TAREFA do F34).

create table coleta_diaria (
  id bigserial primary key,
  usuario_id uuid not null references auth.users (id) on delete cascade,

  -- Chave do atributo medido: 'refeicao', 'peso_kg', 'pressao_sistolica',
  -- 'glicose_jejum', etc. Texto livre (não enum) de propósito — cada novo
  -- tipo de leitura (F10 Passo 3 completo, F49...) só precisa de um novo
  -- valor aqui, nunca de uma migration para estender um enum.
  atributo text not null,

  valor_numerico numeric(10, 3),
  valor_jsonb jsonb,
  unidade text,

  -- De onde a leitura veio: 'ocr_refeicao', 'ocr_glicosimetro', 'manual',
  -- etc. Obrigatório por design (G.2) — nunca se sabe menos que "como isso
  -- chegou aqui".
  origem text not null,

  -- Score de confiança do OCR/IA, 0.00–1.00 — já produzido pelo servidor
  -- (extract-metric-photo) para toda leitura por câmera. NULL é válido só
  -- para origem='manual' (autorrelato não tem "confiança de leitura").
  confianca numeric(3, 2),

  -- Dia a que a leitura pertence (diário do usuário) — pode diferir de
  -- `criado_em`::date se o app gravar com atraso (fila offline).
  data_coleta date not null,

  criado_em timestamptz not null default now()
);

alter table coleta_diaria
  add constraint coleta_diaria_tem_valor
  check (valor_numerico is not null or valor_jsonb is not null);

alter table coleta_diaria
  add constraint coleta_diaria_confianca_em_faixa
  check (confianca is null or (confianca >= 0 and confianca <= 1));

create index idx_coleta_diaria_usuario_atributo_data
  on coleta_diaria (usuario_id, atributo, data_coleta desc);

-- ============================================================================
-- RLS + GRANT (Parte 0.10 / Parte 6) — toda migration nova precisa das duas;
-- RLS sozinho não basta, o cliente autenticado ainda precisa do privilégio de
-- tabela na ACL do Postgres (mesma lição já registrada em
-- 20260713140000_saneamento_grants_e_unificacao_rls.sql).
-- ============================================================================
alter table coleta_diaria enable row level security;

create policy "coleta_diaria_select_own"
  on coleta_diaria for select
  using (auth.uid() = usuario_id);

create policy "coleta_diaria_insert_own"
  on coleta_diaria for insert
  with check (auth.uid() = usuario_id);

create policy "coleta_diaria_update_own"
  on coleta_diaria for update
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- DELETE explicitamente pedido pela tarefa (F34): ao contrário de
-- `resultados_exames` (histórico de laudo, não editável pelo paciente),
-- `coleta_diaria` guarda autorrelatos e leituras que o próprio usuário pode
-- legitimamente querer apagar (ex.: refeição duplicada, leitura de aparelho
-- errada) — sempre escopado à própria linha.
create policy "coleta_diaria_delete_own"
  on coleta_diaria for delete
  using (auth.uid() = usuario_id);

grant select, insert, update, delete on coleta_diaria to authenticated;
