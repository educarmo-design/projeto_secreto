-- RELATÓRIO 20260918_0001 — Compliance total com docs/motor_metabolico.txt
-- (Blocos 1 a 16 / Seções 1 a 28 da especificação completa da Anamnese —
-- não a variante "V1.0 mínima" do mesmo documento, que explicitamente
-- exclui vários destes blocos; ver o relatório desta tarefa para a
-- resolução dessa ambiguidade textual do próprio documento).
--
-- `anamneses` está com 0 linhas em produção neste momento (confirmado ao
-- vivo antes de escrever esta migration) — todas as mudanças abaixo são
-- portanto puramente aditivas, sem necessidade de backfill/migração de
-- dado existente.

-- ============================================================================
-- Parte 1 — Bloco 2 (Objetivos): lista exata da Seção 4.1/4.2
-- ============================================================================
-- Lista anterior ('emagrecimento','manutencao','hipertrofia','outro') não
-- batia com a lista exata pedida — trocada pela lista literal da Seção 4.1.
-- Sem UPDATE de dado existente necessário (tabela vazia), mas o UPDATE
-- abaixo fica como salvaguarda idempotente caso isto rode num ambiente que
-- não esteja vazio no futuro (dev/staging).
update anamneses set objetivo_codigo = 'perder_peso' where objetivo_codigo = 'emagrecimento';
update anamneses set objetivo_codigo = 'manter_peso' where objetivo_codigo = 'manutencao';
update anamneses set objetivo_codigo = 'ganhar_massa_muscular' where objetivo_codigo = 'hipertrofia';

alter table anamneses drop constraint if exists anamneses_objetivo_codigo_check;
alter table anamneses add constraint anamneses_objetivo_codigo_check
  check (objetivo_codigo in (
    'perder_peso', 'manter_peso', 'ganhar_peso', 'reduzir_gordura_corporal',
    'ganhar_massa_muscular', 'recomposicao_corporal', 'melhorar_desempenho_esportivo', 'outro'
  ));

comment on column anamneses.objetivo_codigo is
  'Lista EXATA da Seção 4.1 do documento (RELATÓRIO 20260918_0001) — 8 opções. Antes desta tarefa usava uma lista menor/divergente (emagrecimento/manutencao/hipertrofia/outro).';

-- Objetivos secundários (Seção 5.2 — "permitir múltiplos") + Meta
-- quantitativa (Seção 5.3 / 4.2) — condicional conforme o objetivo.
alter table anamneses
  add column if not exists objetivos_secundarios text[] not null default '{}',
  add column if not exists meta_peso_desejado_kg numeric,
  add column if not exists meta_percentual_gordura_desejado numeric,
  add column if not exists meta_massa_desejada_kg numeric,
  add column if not exists meta_prazo date,
  add column if not exists meta_outro_indicador text;

comment on column anamneses.objetivos_secundarios is
  'Bloco 2 (Seção 5.2) — múltiplos objetivos secundários, mesmos códigos de objetivo_codigo. Array vazio = nenhum informado.';
comment on column anamneses.meta_peso_desejado_kg is
  'Bloco 2 (Seção 5.3/4.2) — meta quantitativa condicional. "A existência de uma meta não significa que o sistema deva automaticamente considerá-la clinicamente adequada" (Seção 5.3) — nenhuma validação clínica é aplicada sobre estes 3 campos de meta.';

-- ============================================================================
-- Parte 2 — Bloco 1 (Contexto da avaliação): motivo da avaliação
-- ============================================================================
alter table anamneses
  add column if not exists motivo_avaliacao text,
  add column if not exists motivo_avaliacao_outro text;

alter table anamneses drop constraint if exists anamneses_motivo_avaliacao_check;
alter table anamneses add constraint anamneses_motivo_avaliacao_check
  check (motivo_avaliacao is null or motivo_avaliacao in (
    'avaliacao_inicial', 'reavaliacao_periodica', 'alteracao_objetivo', 'alteracao_condicao_saude',
    'alteracao_peso', 'alteracao_rotina', 'nova_avaliacao_profissional', 'retorno_apos_interrupcao', 'outro'
  ));

comment on column anamneses.motivo_avaliacao is
  'Bloco 1 (Seção 4, "Motivos possíveis") — nullable só pelas anamneses já existentes antes desta migration (nenhuma em produção hoje); telas novas devem sempre preencher.';

-- ============================================================================
-- Parte 3 — Bloco 3 (Antropometria): composição corporal completa
-- ============================================================================
-- peso_kg/altura_cm/peso_data_medicao/peso_origem já existem (SSOT,
-- 20260916120000). Faltava o resto da composição corporal snapshot na
-- própria versão da anamnese (hoje só em metricas_saude_diarias, que é
-- "dado de origem", não o dado oficial da anamnese — mesma regra já
-- aplicada a peso/altura, estendida aqui pro resto do Bloco 3).
alter table anamneses
  add column if not exists percentual_gordura numeric,
  add column if not exists massa_gorda_kg numeric,
  add column if not exists massa_magra_kg numeric,
  add column if not exists massa_muscular_kg numeric,
  add column if not exists circunferencia_cintura_cm numeric,
  add column if not exists circunferencia_abdominal_cm numeric,
  add column if not exists metodo_avaliacao_composicao text,
  add column if not exists fonte_composicao_corporal text,
  add column if not exists data_avaliacao_composicao date;

comment on column anamneses.massa_magra_kg is
  'Bloco 3 — também é o insumo de MLG para TMB-002/TMB-003 (Katch-McArdle/Cunningham, docs/motor_metabolico.txt "Fórmulas de TMB V1.0") quando o Motor as suportar; hoje o Motor V1 só usa TMB-001 (Mifflin-St Jeor) — ver checklist do relatório.';

-- ============================================================================
-- Parte 4 — Bloco 4 (Histórico de peso)
-- ============================================================================
-- "Esses dados são históricos e não devem ser confundidos com o peso
-- oficial da nova Anamnese" — por isso NÃO são colunas novas persistidas,
-- e sim uma RPC de leitura (Parte 12 abaixo) que reconstrói o histórico a
-- partir das anamneses já existentes. Só a pergunta explícita da Seção 10
-- vira coluna (é um dado INFORMADO, não derivado).
alter table anamneses
  add column if not exists houve_alteracao_peso_nao_planejada text;

alter table anamneses drop constraint if exists anamneses_alteracao_peso_check;
alter table anamneses add constraint anamneses_alteracao_peso_check
  check (houve_alteracao_peso_nao_planejada is null or houve_alteracao_peso_nao_planejada in ('sim', 'nao', 'nao_sabe'));

-- ============================================================================
-- Parte 5 — Bloco 5 (Alimentação): padrão alimentar
-- ============================================================================
-- Consumo (energia/proteína/carboidrato/gordura/fibra/água/álcool) NÃO
-- entra aqui de propósito — já existe o diário alimentar
-- (ColetaDiariaRepository) com esse mesmo dado; duplicar violaria a Seção
-- 18 ("não deve conter informações redundantes que já existam em outros
-- módulos"). Alergias/intolerâncias reaproveitam `alergias`/
-- `anamneses_alergias` já existentes (Bloco 8 da tarefa 20260811_0007);
-- `intolerancias_alimentares` é texto livre porque não há catálogo de
-- intolerâncias hoje (diferente de alergia, que já tinha).
alter table anamneses
  add column if not exists numero_refeicoes_dia smallint,
  add column if not exists horarios_refeicoes_habituais text,
  add column if not exists regularidade_alimentar text,
  add column if not exists refeicoes_fora_de_casa text,
  add column if not exists consumo_ultraprocessados text,
  add column if not exists preferencias_alimentares text,
  add column if not exists alimentos_evitados text,
  add column if not exists restricoes_alimentares text[] not null default '{}',
  add column if not exists intolerancias_alimentares text[] not null default '{}',
  add column if not exists padrao_alimentar_habitual text;

-- ============================================================================
-- Parte 6 — Bloco 6 (Atividades e rotina semanal) + Seção 5 (rotina diária)
-- ============================================================================
-- Rotina diária (Seção 5) — pergunta única, complementar ao NEAT. Registrada
-- mas NÃO alimenta o cálculo do PAL do Motor V1 nesta tarefa (o Motor usa
-- PAL fixo 1.2 versionado, "PAL-001-sedentario-v1" — mudar a fórmula do
-- Motor para consumir este campo é uma alteração de MOTOR, fora do escopo
-- desta tarefa, que é sobre a Anamnese; ver checklist do relatório).
alter table anamneses
  add column if not exists rotina_diaria text,
  add column if not exists atividade_ocupacional text;

alter table anamneses drop constraint if exists anamneses_rotina_diaria_check;
alter table anamneses add constraint anamneses_rotina_diaria_check
  check (rotina_diaria is null or rotina_diaria in (
    'predominantemente_sentado', 'pouco_ativo', 'moderadamente_ativo', 'muito_ativo', 'trabalho_fisicamente_intenso'
  ));

-- Atividade não estruturada — "passos"/"tempo em movimento" JÁ são
-- coletados automaticamente por wearable (metricas_saude_diarias.passos) —
-- reperguntar violaria a Seção 18 ("não pedir informações que possam ser
-- calculadas ou obtidas automaticamente"). Só o que não tem outra fonte
-- vira campo aqui.

-- Intensidade (Bloco 6, "obrigatório" — RESTRIÇÃO explícita da tarefa: "incluir
-- obrigatoriamente a Intensidade"). Tabela `anamneses_atividades_dias`
-- também está com 0 linhas em produção hoje (FK cascade de `anamneses`,
-- que está vazia) — `not null` sem default é seguro.
alter table anamneses_atividades_dias
  add column if not exists intensidade text not null default 'moderada',
  add column if not exists horario time,
  add column if not exists distancia_km numeric,
  add column if not exists calorias_dispositivo numeric,
  add column if not exists fonte text not null default 'usuario';

alter table anamneses_atividades_dias alter column intensidade drop default;

alter table anamneses_atividades_dias drop constraint if exists anamneses_atividades_dias_intensidade_check;
alter table anamneses_atividades_dias add constraint anamneses_atividades_dias_intensidade_check
  check (intensidade in ('leve', 'moderada', 'alta'));

comment on column anamneses_atividades_dias.intensidade is
  'Bloco 6 — obrigatório por pedido explícito do fundador (RELATÓRIO 20260918_0001). NOT NULL sem default (o default "moderada" usado só durante o ADD COLUMN foi removido em seguida — tabela estava vazia, então não sobrou nenhuma linha com o default).';

-- ============================================================================
-- Parte 7 — Bloco 7 (Sono e recuperação)
-- ============================================================================
alter table anamneses
  add column if not exists horas_sono_medias numeric,
  add column if not exists horario_dormir_habitual time,
  add column if not exists horario_acordar_habitual time,
  add column if not exists qualidade_sono_percebida text,
  add column if not exists despertares_noturnos smallint,
  add column if not exists sono_dados_wearable boolean not null default false,
  add column if not exists sono_observacoes text;

alter table anamneses drop constraint if exists anamneses_qualidade_sono_check;
alter table anamneses add constraint anamneses_qualidade_sono_check
  check (qualidade_sono_percebida is null or qualidade_sono_percebida in ('muito_ruim', 'ruim', 'regular', 'boa', 'muito_boa'));

comment on table anamneses is
  'N09 (RELATÓRIO 20260811_0007) — Anamnese Nutricional Versionada. Ampliada em várias tarefas subsequentes (SSOT peso/altura em 20260916120000; snapshot do Motor V1/campos profissionais em 20260917120000; compliance total com Blocos 1-16 de docs/motor_metabolico.txt em 20260918_0001 — RELATÓRIO desta migration). INSERT-only: um novo preenchimento é sempre uma linha nova, nunca um UPDATE.';

-- ============================================================================
-- Parte 8 — Bloco 8 (Condições de saúde)
-- ============================================================================
-- "Não tenho" explícito (RESTRIÇÃO da tarefa) — `null` = não respondeu
-- ainda, `false` = respondeu "Não tenho" (distinção auditável).
alter table anamneses
  add column if not exists possui_condicao_saude boolean;

-- Detalhe por condição (Seção 11 do bloco completo: "diagnóstico; data;
-- status; profissional responsável; observações; evidências/exames
-- associados"). `anamneses_problemas_saude` já existe (N:N simples,
-- 20260811240000) — estendida em vez de recriada.
alter table anamneses_problemas_saude
  add column if not exists data_diagnostico date,
  add column if not exists status text,
  add column if not exists profissional_responsavel text,
  add column if not exists observacoes text,
  add column if not exists evidencias_relacionadas text;

alter table anamneses_problemas_saude drop constraint if exists anamneses_problemas_saude_status_check;
alter table anamneses_problemas_saude add constraint anamneses_problemas_saude_status_check
  check (status is null or status in ('ativo', 'controlado', 'resolvido', 'em_investigacao'));

-- Curadoria do catálogo: ADITIVA, não substitui os 20 itens já curados
-- (mais granulares — ex.: "Diabetes Mellitus Tipo 1/2" em vez de só
-- "Diabetes"). A lista EXATA da Seção 8 (14 categorias) passa a existir
-- como opções de nível mais alto, lado a lado com as já existentes mais
-- específicas — nenhum dado/curadoria anterior é removido.
insert into problemas_saude (nome) values
  ('Diabetes'), ('Pré-diabetes'), ('Hipertensão'), ('Dislipidemia'),
  ('Doença cardiovascular'), ('Doença renal'), ('Doença hepática'),
  ('Doenças gastrointestinais'), ('Doença da tireoide'), ('Obesidade'),
  ('Sarcopenia'), ('Fragilidade'), ('Transtornos alimentares'), ('Outra condição relevante')
on conflict (nome) do nothing;

-- ============================================================================
-- Parte 9 — Bloco 9 (Medicamentos)
-- ============================================================================
create table if not exists anamneses_medicamentos (
  id uuid primary key default gen_random_uuid(),
  anamnese_id uuid not null references anamneses (id) on delete cascade,
  nome text not null,
  dose numeric,
  unidade text,
  frequencia text,
  horario text,
  indicacao text,
  data_inicio date,
  data_termino date,
  uso_atual boolean not null default true,
  prescritor text,
  criado_em timestamptz not null default now()
);

comment on table anamneses_medicamentos is
  'Bloco 9 (RELATÓRIO 20260918_0001) — "contexto para os motores, sem alterar tratamento automaticamente" (docs/motor_metabolico.txt). Nenhuma RPC lê esta tabela para decisão clínica automática nesta tarefa.';

alter table anamneses_medicamentos enable row level security;

create policy "anamneses_medicamentos_select_own_or_profissional"
  on anamneses_medicamentos for select
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_medicamentos.anamnese_id
        and (
          a.usuario_id = auth.uid()
          or exists (
            select 1 from vinculos_profissional_paciente v
            where v.profissional_id = auth.uid() and v.paciente_id = a.usuario_id and v.status = 'ativo'
          )
        )
    )
  );

create policy "anamneses_medicamentos_insert_own"
  on anamneses_medicamentos for insert
  with check (exists (select 1 from anamneses a where a.id = anamneses_medicamentos.anamnese_id and a.usuario_id = auth.uid()));

create policy "anamneses_medicamentos_delete_own"
  on anamneses_medicamentos for delete
  using (exists (select 1 from anamneses a where a.id = anamneses_medicamentos.anamnese_id and a.usuario_id = auth.uid()));

grant select, insert, delete on anamneses_medicamentos to authenticated;

-- ============================================================================
-- Parte 10 — Bloco 10 (Suplementos)
-- ============================================================================
create table if not exists anamneses_suplementos (
  id uuid primary key default gen_random_uuid(),
  anamnese_id uuid not null references anamneses (id) on delete cascade,
  nome text not null,
  dose numeric,
  unidade text,
  frequencia text,
  horario text,
  objetivo text,
  uso_atual boolean not null default true,
  orientacao_profissional text,
  criado_em timestamptz not null default now()
);

alter table anamneses_suplementos enable row level security;

create policy "anamneses_suplementos_select_own_or_profissional"
  on anamneses_suplementos for select
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_suplementos.anamnese_id
        and (
          a.usuario_id = auth.uid()
          or exists (
            select 1 from vinculos_profissional_paciente v
            where v.profissional_id = auth.uid() and v.paciente_id = a.usuario_id and v.status = 'ativo'
          )
        )
    )
  );

create policy "anamneses_suplementos_insert_own"
  on anamneses_suplementos for insert
  with check (exists (select 1 from anamneses a where a.id = anamneses_suplementos.anamnese_id and a.usuario_id = auth.uid()));

create policy "anamneses_suplementos_delete_own"
  on anamneses_suplementos for delete
  using (exists (select 1 from anamneses a where a.id = anamneses_suplementos.anamnese_id and a.usuario_id = auth.uid()));

grant select, insert, delete on anamneses_suplementos to authenticated;

-- ============================================================================
-- Parte 11 — Bloco 11 (Exames laboratoriais)
-- ============================================================================
create table if not exists anamneses_exames_laboratoriais (
  id uuid primary key default gen_random_uuid(),
  anamnese_id uuid not null references anamneses (id) on delete cascade,
  data_exame date,
  nome_exame text not null,
  resultado text,
  unidade text,
  referencia_laboratorio text,
  origem text,
  documento_origem text,
  criado_em timestamptz not null default now()
);

comment on table anamneses_exames_laboratoriais is
  'Bloco 11 (RELATÓRIO 20260918_0001) — "o sistema deve preservar o resultado original" (docs/motor_metabolico.txt). `resultado`/`unidade` são texto livre de propósito: painel laboratorial não é estruturado nesta tarefa (fora do escopo "Seções 1-18" da Anamnese em si).';

alter table anamneses_exames_laboratoriais enable row level security;

create policy "anamneses_exames_laboratoriais_select_own_or_profissional"
  on anamneses_exames_laboratoriais for select
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_exames_laboratoriais.anamnese_id
        and (
          a.usuario_id = auth.uid()
          or exists (
            select 1 from vinculos_profissional_paciente v
            where v.profissional_id = auth.uid() and v.paciente_id = a.usuario_id and v.status = 'ativo'
          )
        )
    )
  );

create policy "anamneses_exames_laboratoriais_insert_own"
  on anamneses_exames_laboratoriais for insert
  with check (exists (select 1 from anamneses a where a.id = anamneses_exames_laboratoriais.anamnese_id and a.usuario_id = auth.uid()));

create policy "anamneses_exames_laboratoriais_delete_own"
  on anamneses_exames_laboratoriais for delete
  using (exists (select 1 from anamneses a where a.id = anamneses_exames_laboratoriais.anamnese_id and a.usuario_id = auth.uid()));

grant select, insert, delete on anamneses_exames_laboratoriais to authenticated;

-- ============================================================================
-- Parte 12 — Bloco 12 (Blocos condicionais): Idoso, Atleta, Recomposição,
-- Diabetes, Doença Renal
-- ============================================================================
-- JSONB (não colunas discretas) de propósito: são ~10-15 campos POR bloco,
-- só preenchidos quando aplicável (adaptativo — "não apresentar todas as
-- perguntas para todos os usuários"), sem consulta relacional necessária
-- hoje. Mesmo padrão já usado em `resultado_motor_v1`. Chaves documentadas
-- abaixo batem exatamente com a lista de cada bloco no documento.
alter table anamneses
  add column if not exists bloco_idoso jsonb,
  add column if not exists bloco_atleta jsonb,
  add column if not exists bloco_recomposicao jsonb,
  add column if not exists bloco_diabetes jsonb,
  add column if not exists bloco_doenca_renal jsonb;

comment on column anamneses.bloco_idoso is
  'Bloco 12.1 — chaves: perda_involuntaria_peso, apetite, dificuldade_alimentacao, mastigacao, degluticao, mobilidade, quedas, forca, atividade_fisica, funcionalidade, composicao_corporal, risco_nutricional, suporte_social.';
comment on column anamneses.bloco_atleta is
  'Bloco Atleta (Seção 16/9.3) — chaves: modalidade, nivel, horas_semana, sessoes_semana, duracao, intensidade, treinamento_resistido, treinamento_aerobico, periodizacao, dias_descanso, competicoes, proxima_competicao, categoria_peso, estrategia_recuperacao, suplementacao, alimentacao_durante_exercicio.';
comment on column anamneses.bloco_recomposicao is
  'Bloco Recomposição Corporal (Seção 17) — chaves: percentual_gordura_atual, percentual_desejado, massa_magra, massa_muscular, treinamento_resistido, frequencia, historico_treinamento, evolucao_forca, historico_peso, estrategia_nutricional_atual.';
comment on column anamneses.bloco_diabetes is
  'Bloco Diabetes (Seção 18/9.1) — chaves: tipo, data_diagnostico, hba1c, glicemia, hipoglicemias, hiperglicemias, insulina, medicamentos, cgm, glicosimetro, tempo_no_alvo, relacao_exercicio, complicacoes, comorbidades.';
comment on column anamneses.bloco_doenca_renal is
  'Bloco Doença Renal (Seção 19/9.2) — chaves: diagnostico, estagio, tfg_egfr, creatinina, albuminuria_proteinuria, ureia, potassio, sodio, fosforo, calcio, bicarbonato, dialise, tipo_dialise, transplante, restricao_hidrica, orientacao_proteina, outras_restricoes.';

-- ============================================================================
-- Parte 13 — Bloco 15 (Qualidade e exceções) — estrutura pronta, sem
-- algoritmo de scoring (não especificado no documento — nenhuma fórmula de
-- "score de qualidade" é dada; inventar uma violaria o mesmo princípio já
-- estabelecido no projeto de nunca arbitrar número clínico sem fórmula
-- explícita do fundador).
-- ============================================================================
alter table anamneses
  add column if not exists qualidade_dados jsonb;

comment on column anamneses.qualidade_dados is
  'Bloco 15 (RELATÓRIO 20260918_0001) — estrutura para {score, dados_faltantes[], dados_inconsistentes[], dados_desatualizados[], excecoes_bloqueantes[], alertas[]}. NULL até uma tarefa futura implementar o algoritmo de scoring (não especificado em docs/motor_metabolico.txt) — gap documentado, não escondido.';

-- ============================================================================
-- Parte 14 — Bloco 16 (Auditoria e versionamento): número de versão +
-- confirmação explícita (Seção 11 — "Confirme seus dados")
-- ============================================================================
alter table anamneses
  add column if not exists numero_versao int,
  add column if not exists dados_confirmados boolean not null default false,
  add column if not exists confirmado_em timestamptz;

comment on column anamneses.numero_versao is
  'Bloco 16 — sequencial POR USUÁRIO (1, 2, 3...), preenchido pelo trigger anamneses_trg_versionar (abaixo). Complementar a status_vigencia/data_preenchimento, que já dão ordenação — este campo só torna "qual versão é esta" explícito sem precisar contar linhas.';
comment on column anamneses.dados_confirmados is
  'Bloco 1/Seção 11 (RESTRIÇÃO da tarefa: "Garantir a tela final de Confirme seus dados antes de enviar para o motor") — true só depois que o usuário/profissional passou pela tela de confirmação final. Nenhuma RPC do Motor valida este campo hoje (o Flutter/React controla a ordem chamando a tela de confirmação antes de salvar) — ver checklist do relatório para o gap de enforcement server-side.';

-- Extensão do trigger de versionamento (20260811240000) — mesmo corpo,
-- só adiciona o cálculo de numero_versao.
create or replace function public.anamneses_versionar_status_vigencia()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status_vigencia = 'ativo' then
    update public.anamneses
    set status_vigencia = 'historico'
    where usuario_id = new.usuario_id
      and status_vigencia = 'ativo';
  end if;

  if new.numero_versao is null then
    select coalesce(max(numero_versao), 0) + 1
    into new.numero_versao
    from public.anamneses
    where usuario_id = new.usuario_id;
  end if;

  return new;
end;
$$;

comment on trigger anamneses_trg_versionar on anamneses is
  'N09 (RELATÓRIO 20260811_0007) + RELATÓRIO 20260918_0001 (numero_versao): garante no máximo 1 anamnese "ativo" por usuário E preenche numero_versao sequencial automaticamente quando o cliente não o envia (o app nunca deveria enviar isso manualmente).';

-- ============================================================================
-- Parte 15 — RPC: Histórico de peso (Bloco 4) — leitura, nunca persiste
-- ============================================================================
-- Mesmo guard de acesso de calcular_motor_metabolico_v1 (dono, profissional
-- vinculado ATIVO, ou admin). Busca o peso mais próximo de cada marco
-- temporal dentre as anamneses com peso preenchido — "mais próximo", não
-- "exato", porque anamneses não são preenchidas em datas fixas.
create or replace function public.anamnese_historico_peso(p_usuario_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_peso_atual numeric;
  v_peso_anterior numeric;
  v_peso_30_dias numeric;
  v_peso_3_meses numeric;
  v_peso_6_meses numeric;
  v_peso_12_meses numeric;
  v_maior_peso numeric;
  v_menor_peso numeric;
  v_variacao_percentual numeric;
begin
  if auth.uid() is distinct from p_usuario_id
     and not exists (
       select 1 from public.vinculos_profissional_paciente v
       where v.profissional_id = auth.uid() and v.paciente_id = p_usuario_id and v.status = 'ativo'
     )
     and not public.eh_admin()
  then
    raise exception 'Sem acesso ao histórico de peso deste usuário.';
  end if;

  select a.peso_kg into v_peso_atual
  from public.anamneses a
  where a.usuario_id = p_usuario_id and a.peso_kg is not null
  order by a.data_preenchimento desc limit 1;

  select a.peso_kg into v_peso_anterior
  from public.anamneses a
  where a.usuario_id = p_usuario_id and a.peso_kg is not null
  order by a.data_preenchimento desc offset 1 limit 1;

  select a.peso_kg into v_peso_30_dias
  from public.anamneses a
  where a.usuario_id = p_usuario_id and a.peso_kg is not null and a.data_preenchimento <= now() - interval '30 days'
  order by a.data_preenchimento desc limit 1;

  select a.peso_kg into v_peso_3_meses
  from public.anamneses a
  where a.usuario_id = p_usuario_id and a.peso_kg is not null and a.data_preenchimento <= now() - interval '3 months'
  order by a.data_preenchimento desc limit 1;

  select a.peso_kg into v_peso_6_meses
  from public.anamneses a
  where a.usuario_id = p_usuario_id and a.peso_kg is not null and a.data_preenchimento <= now() - interval '6 months'
  order by a.data_preenchimento desc limit 1;

  select a.peso_kg into v_peso_12_meses
  from public.anamneses a
  where a.usuario_id = p_usuario_id and a.peso_kg is not null and a.data_preenchimento <= now() - interval '12 months'
  order by a.data_preenchimento desc limit 1;

  select max(a.peso_kg), min(a.peso_kg) into v_maior_peso, v_menor_peso
  from public.anamneses a
  where a.usuario_id = p_usuario_id and a.peso_kg is not null;

  if v_peso_anterior is not null and v_peso_anterior > 0 and v_peso_atual is not null then
    v_variacao_percentual := round(((v_peso_atual - v_peso_anterior) / v_peso_anterior) * 100, 1);
  end if;

  return jsonb_build_object(
    'peso_atual', v_peso_atual,
    'peso_anterior', v_peso_anterior,
    'peso_30_dias', v_peso_30_dias,
    'peso_3_meses', v_peso_3_meses,
    'peso_6_meses', v_peso_6_meses,
    'peso_12_meses', v_peso_12_meses,
    'maior_peso', v_maior_peso,
    'menor_peso', v_menor_peso,
    'variacao_percentual', v_variacao_percentual
  );
end;
$$;

comment on function public.anamnese_historico_peso(uuid) is
  'Bloco 4 (RELATÓRIO 20260918_0001) — "o sistema deve recuperar automaticamente informações históricas disponíveis". Função PURA (nunca persiste, ME-005/006) — reconstrói o histórico a partir das anamneses já existentes, nunca duplica o peso como coluna nova.';

revoke execute on function public.anamnese_historico_peso(uuid) from public;
grant execute on function public.anamnese_historico_peso(uuid) to authenticated;

-- ============================================================================
-- Parte 16 — Curadoria do catálogo de alergias (RESTRIÇÃO explícita da
-- tarefa: "padrão clínico"). Aditivo — a linha de teste pré-existente
-- ("TESTE"/"TESTE") não é removida (fora do escopo desta tarefa apagar
-- dado de teste de uma curadoria anterior não relacionada).
-- ============================================================================
insert into alergias (nome_codigo, nome_exibicao) values
  ('AMENDOIM', 'Amendoim'),
  ('CASTANHAS_NOZES', 'Castanhas/Nozes'),
  ('CRUSTACEOS_FRUTOS_MAR', 'Crustáceos/Frutos do mar'),
  ('LEITE', 'Leite'),
  ('OVOS', 'Ovos'),
  ('PEIXES', 'Peixes'),
  ('SOJA', 'Soja'),
  ('TRIGO_GLUTEN', 'Trigo/Glúten'),
  ('GERGELIM', 'Gergelim'),
  ('OUTROS', 'Outros')
on conflict (nome_codigo) do nothing;
