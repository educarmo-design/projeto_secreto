-- RELATÓRIO 20260927_0001 — QA final da Anamnese: limpeza de campos
-- obsoletos, confirmação de achado (intolerâncias já existia) e nova
-- métrica de duração média por sessão NO DIA (agregada entre modalidades)
-- em `processar_medias_smartwatch`.
--
-- ============================================================================
-- Item 1a — Limpeza: horarios_refeicoes_habituais/refeicoes_fora_de_casa
-- ============================================================================
-- Ambos os campos viraram parte da estrutura interna de cada refeição em
-- `refeicoes_diarias_habituais` (RELATÓRIO 20260922_0001: `horario`/
-- `fora_de_casa` por refeição) — as 2 colunas soltas antigas (texto livre,
-- sem estrutura por refeição) ficaram redundantes e confusas ("2 lugares
-- pra dizer a mesma coisa"). Removidas de propósito, não só descontinuadas.
alter table anamneses
  drop column if exists horarios_refeicoes_habituais,
  drop column if exists refeicoes_fora_de_casa;

-- ============================================================================
-- Item 1b — Intolerâncias: ACHADO, não implementado (Regra 26 — reportar
-- honestamente em vez de duplicar)
-- ============================================================================
-- A tarefa pediu "adicione o campo intolerancias (array) ao lado de
-- alergias e restrições culturais" — `anamneses.intolerancias_alimentares
-- text[]` JÁ EXISTE desde a migration `20260918100000` (Bloco 5, Seção 8).
-- Nenhuma coluna nova foi criada aqui pra não duplicar o dado; o que
-- realmente faltava era a MECÂNICA DE SELEÇÃO (chips, igual Alergias/
-- Restrições Culturais, em vez de texto livre separado por vírgula) — isso
-- é 100% UI (Flutter/React), sem mudança de schema. Ver RELATÓRIO
-- 20260927_0001 para o detalhe da UI.

-- ============================================================================
-- Item 1c — processar_medias_smartwatch: nova métrica agregada por dia
-- ============================================================================
-- `duracao_media_por_sessao_minutos` (por modalidade+dia, RELATÓRIO
-- 20260922_0001) já existia e satisfaz a fórmula literal pedida
-- ("tempo total ÷ número de ocorrências daquele dia") quando o "dia" é
-- entendido como aquele dia da semana PARA aquela modalidade específica —
-- mas nunca tinha sido exibida em nenhuma tela (gap real, corrigido nos
-- modais de revisão desta tarefa). Adicionado aqui, complementar: um novo
-- campo `duracao_media_por_sessao_dia` (por dia da semana, SOMANDO todas as
-- modalidades daquele dia) — a leitura "tempo total do dia ÷ ocorrências do
-- dia" tratando o dia como um todo, não só uma modalidade — cobre as 2
-- interpretações possíveis do texto da tarefa.
create or replace function public.processar_medias_smartwatch(
  p_usuario_id uuid,
  p_data_inicio timestamptz,
  p_data_fim timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dias_totais int;
  v_semanas_periodo numeric;
  v_metricas jsonb;
  v_atividades_por_dia jsonb;
  v_duracao_media_por_sessao_dia jsonb;
  v_horas_totais numeric;
  v_carga jsonb;
begin
  if auth.uid() is distinct from p_usuario_id
     and not exists (
       select 1 from public.vinculos_profissional_paciente v
       where v.profissional_id = auth.uid()
         and v.paciente_id = p_usuario_id
         and v.status = 'ativo'
     )
     and not public.eh_admin()
  then
    raise exception 'Sem acesso às médias de smartwatch deste usuário.';
  end if;

  if p_data_inicio is null or p_data_fim is null or p_data_fim < p_data_inicio then
    raise exception 'Janela de datas inválida (p_data_fim deve ser >= p_data_inicio).';
  end if;

  v_dias_totais := (p_data_fim::date - p_data_inicio::date) + 1;
  v_semanas_periodo := v_dias_totais / 7.0;

  -- ---- 1) Médias diárias + confiabilidade ----------------------------------
  select jsonb_build_object(
    'passos', jsonb_build_object('media', round(avg(passos), 1), 'dias_com_dado', count(passos), 'percentual_confiabilidade', round(count(passos)::numeric / v_dias_totais * 100, 1)),
    'distancia_metros', jsonb_build_object('media', round(avg(distancia_metros), 1), 'dias_com_dado', count(distancia_metros), 'percentual_confiabilidade', round(count(distancia_metros)::numeric / v_dias_totais * 100, 1)),
    'fc_repouso', jsonb_build_object('media', round(avg(fc_repouso), 1), 'dias_com_dado', count(fc_repouso), 'percentual_confiabilidade', round(count(fc_repouso)::numeric / v_dias_totais * 100, 1)),
    'hrv_medio', jsonb_build_object('media', round(avg(hrv_medio), 1), 'dias_com_dado', count(hrv_medio), 'percentual_confiabilidade', round(count(hrv_medio)::numeric / v_dias_totais * 100, 1)),
    'calorias_ativas', jsonb_build_object('media', round(avg(calorias_ativas), 1), 'dias_com_dado', count(calorias_ativas), 'percentual_confiabilidade', round(count(calorias_ativas)::numeric / v_dias_totais * 100, 1)),
    'calorias_basais', jsonb_build_object('media', round(avg(calorias_basais), 1), 'dias_com_dado', count(calorias_basais), 'percentual_confiabilidade', round(count(calorias_basais)::numeric / v_dias_totais * 100, 1)),
    'calorias_totais', jsonb_build_object('media', round(avg(calorias_totais), 1), 'dias_com_dado', count(calorias_totais), 'percentual_confiabilidade', round(count(calorias_totais)::numeric / v_dias_totais * 100, 1)),
    'minutos_sono', jsonb_build_object('media', round(avg(minutos_sono), 1), 'dias_com_dado', count(minutos_sono), 'percentual_confiabilidade', round(count(minutos_sono)::numeric / v_dias_totais * 100, 1)),
    'peso_kg', jsonb_build_object('media', round(avg(peso_kg), 2), 'dias_com_dado', count(peso_kg), 'percentual_confiabilidade', round(count(peso_kg)::numeric / v_dias_totais * 100, 1)),
    'percentual_gordura', jsonb_build_object('media', round(avg(percentual_gordura), 2), 'dias_com_dado', count(percentual_gordura), 'percentual_confiabilidade', round(count(percentual_gordura)::numeric / v_dias_totais * 100, 1))
  )
  into v_metricas
  from public.metricas_saude_diarias
  where usuario_id_anonimo = p_usuario_id
    and data_referencia >= p_data_inicio::date
    and data_referencia <= p_data_fim::date;

  -- ---- 2) Atividades por dia da semana + modalidade -------------------------
  with dias_periodo as (
    select generate_series(p_data_inicio::date, p_data_fim::date, interval '1 day')::date as dia
  ),
  contagem_dow as (
    select extract(dow from dia)::int as dow, count(*) as qtd
    from dias_periodo
    group by 1
  ),
  atividades_agrupadas as (
    select
      extract(dow from t.inicio_atividade)::int as dow,
      t.tipo_atividade_codigo as modalidade,
      count(*) as ocorrencias,
      sum(extract(epoch from (t.fim_atividade - t.inicio_atividade)) / 60.0) as duracao_total_minutos
    from public.atividades_fisicas_treinos t
    where t.usuario_id = p_usuario_id
      and t.inicio_atividade >= p_data_inicio
      and t.inicio_atividade <= p_data_fim
    group by 1, 2
  ),
  atividades_com_denominador as (
    select
      a.dow,
      jsonb_build_object(
        'modalidade', a.modalidade,
        'ocorrencias_totais', a.ocorrencias,
        'duracao_total_minutos', round(a.duracao_total_minutos, 1),
        -- "número de semanas (ou seja, pelo número daquele dia específico
        -- contido no período)" — o denominador real, não uma constante.
        'semanas_do_periodo', c.qtd,
        'media_ocorrencias_por_semana', round(a.ocorrencias::numeric / c.qtd, 2),
        'media_duracao_minutos_por_semana', round(a.duracao_total_minutos / c.qtd, 1),
        'duracao_media_por_sessao_minutos', round(a.duracao_total_minutos / a.ocorrencias, 1)
      ) as item
    from atividades_agrupadas a
    join contagem_dow c on c.dow = a.dow
  ),
  agrupado_por_dia as (
    select dow, jsonb_agg(item order by (item->>'duracao_total_minutos')::numeric desc) as itens
    from atividades_com_denominador
    group by dow
  )
  select
    jsonb_build_object('0', '[]'::jsonb, '1', '[]'::jsonb, '2', '[]'::jsonb, '3', '[]'::jsonb, '4', '[]'::jsonb, '5', '[]'::jsonb, '6', '[]'::jsonb)
    || coalesce(jsonb_object_agg(dow::text, itens), '{}'::jsonb)
  into v_atividades_por_dia
  from agrupado_por_dia;

  -- RELATÓRIO 20260927_0001 (Item 1c) — total do DIA (somando todas as
  -- modalidades daquele dia da semana) ÷ nº de ocorrências do DIA, a
  -- leitura "tempo total do dia ÷ ocorrências daquele dia" tratando o dia
  -- como um todo (complementar à métrica por modalidade acima). Um
  -- `with ... select into` só enxerga suas próprias CTEs — não dá pra
  -- reaproveitar `atividades_agrupadas` do bloco anterior (já encerrado),
  -- então esta consulta recalcula a agregação por (dow, modalidade) sua
  -- própria vez (dado pequeno, custo desprezível).
  with atividades_agrupadas as (
    select
      extract(dow from t.inicio_atividade)::int as dow,
      count(*) as ocorrencias,
      sum(extract(epoch from (t.fim_atividade - t.inicio_atividade)) / 60.0) as duracao_total_minutos
    from public.atividades_fisicas_treinos t
    where t.usuario_id = p_usuario_id
      and t.inicio_atividade >= p_data_inicio
      and t.inicio_atividade <= p_data_fim
    group by 1
  )
  select
    jsonb_build_object('0', null, '1', null, '2', null, '3', null, '4', null, '5', null, '6', null)
    || coalesce(jsonb_object_agg(dow::text, round(duracao_total_minutos / ocorrencias, 1)), '{}'::jsonb)
  into v_duracao_media_por_sessao_dia
  from atividades_agrupadas
  where ocorrencias > 0;

  -- ---- 3) Carga do Atleta — horas totais e média semanal --------------------
  select coalesce(sum(extract(epoch from (fim_atividade - inicio_atividade)) / 3600.0), 0)
  into v_horas_totais
  from public.atividades_fisicas_treinos
  where usuario_id = p_usuario_id
    and inicio_atividade >= p_data_inicio
    and inicio_atividade <= p_data_fim;

  v_carga := jsonb_build_object(
    'horas_totais_periodo', round(v_horas_totais, 2),
    'semanas_no_periodo', round(v_semanas_periodo, 2),
    'media_semanal_horas', round(v_horas_totais / v_semanas_periodo, 2)
  );

  return jsonb_build_object(
    'fonte', 'smartwatch',
    'janela', jsonb_build_object('data_inicio', p_data_inicio, 'data_fim', p_data_fim, 'dias_totais', v_dias_totais),
    'metricas_diarias', v_metricas,
    'atividades_por_dia_semana', v_atividades_por_dia,
    'duracao_media_por_sessao_dia', v_duracao_media_por_sessao_dia,
    'carga_atleta', v_carga,
    'calculado_em', now()
  );
end;
$$;

comment on function public.processar_medias_smartwatch(uuid, timestamptz, timestamptz) is
  'RELATÓRIO 20260922_0001 (original) + 20260927_0001 (Item 1c: novo campo duracao_media_por_sessao_dia, agregado por dia da semana somando todas as modalidades — complementar ao duracao_media_por_sessao_minutos por modalidade, que já existia). Função PURA (só leitura). fonte sempre "smartwatch".';

revoke execute on function public.processar_medias_smartwatch(uuid, timestamptz, timestamptz) from public;
grant execute on function public.processar_medias_smartwatch(uuid, timestamptz, timestamptz) to authenticated;

-- ============================================================================
-- Item 1a (continuação) — profissional_salvar_anamnese: remove as 2
-- colunas descontinuadas do INSERT (contrato: quem não enviar mais esses
-- campos no payload continua funcionando; quem ainda enviar, o valor é
-- simplesmente ignorado — nunca dá erro).
-- ============================================================================
create or replace function public.profissional_salvar_anamnese(p_paciente_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profissional_id uuid := auth.uid();
  v_anamnese_id uuid;
  v_objetivo_codigo text := p_payload->>'objetivo_codigo';
  v_atividades jsonb := coalesce(p_payload->'atividades', '[]'::jsonb);
  v_medicamentos jsonb := coalesce(p_payload->'medicamentos', '[]'::jsonb);
  v_suplementos jsonb := coalesce(p_payload->'suplementos', '[]'::jsonb);
  v_exames jsonb := coalesce(p_payload->'exames', '[]'::jsonb);
  v_alergias jsonb := coalesce(p_payload->'alergias', '[]'::jsonb);
  v_item jsonb;
begin
  if v_profissional_id is null then
    raise exception 'N09_SEM_SESSAO: Nenhum profissional autenticado.';
  end if;

  if not exists (
    select 1 from public.vinculos_profissional_paciente v
    where v.profissional_id = v_profissional_id
      and v.paciente_id = p_paciente_id
      and v.status = 'ativo'
  ) and not public.eh_admin() then
    raise exception 'N09_SEM_VINCULO: Sem vínculo ativo com este paciente.';
  end if;

  if v_objetivo_codigo is null then
    raise exception 'N09_PAYLOAD_INVALIDO: objetivo_codigo é obrigatório.';
  end if;

  insert into public.anamneses (
    usuario_id, profissional_id, objetivo_codigo, objetivo_outro,
    peso_kg, altura_cm, peso_data_medicao, peso_origem, data_proxima_avaliacao,
    dados_confirmados, confirmado_em,
    motivo_avaliacao, motivo_avaliacao_outro,
    objetivos_secundarios, meta_peso_desejado_kg, meta_percentual_gordura_desejado,
    meta_massa_desejada_kg, meta_prazo, meta_outro_indicador,
    percentual_gordura, massa_gorda_kg, massa_magra_kg, massa_muscular_kg,
    circunferencia_cintura_cm, circunferencia_abdominal_cm,
    metodo_avaliacao_composicao, fonte_composicao_corporal,
    houve_alteracao_peso_nao_planejada,
    numero_refeicoes_dia, regularidade_alimentar,
    consumo_ultraprocessados, preferencias_alimentares,
    alimentos_evitados, restricoes_alimentares, intolerancias_alimentares, padrao_alimentar_habitual,
    restricoes_culturais_religiosas, refeicoes_diarias_habituais,
    rotina_diaria, atividade_ocupacional,
    horas_sono_medias, horario_dormir_habitual, horario_acordar_habitual,
    qualidade_sono_percebida, despertares_noturnos, sono_observacoes,
    possui_condicao_saude,
    bloco_idoso, bloco_atleta, bloco_recomposicao, bloco_diabetes, bloco_doenca_renal,
    data_validade
  ) values (
    p_paciente_id,
    v_profissional_id,
    v_objetivo_codigo,
    nullif(p_payload->>'objetivo_outro', ''),
    nullif(p_payload->>'peso_kg', '')::numeric,
    nullif(p_payload->>'altura_cm', '')::numeric,
    current_date,
    'profissional',
    nullif(p_payload->>'data_proxima_avaliacao', '')::timestamptz,
    true, now(),
    nullif(p_payload->>'motivo_avaliacao', ''),
    nullif(p_payload->>'motivo_avaliacao_outro', ''),
    coalesce((select array_agg(value #>> '{}') from jsonb_array_elements(coalesce(p_payload->'objetivos_secundarios', '[]'::jsonb))), '{}'),
    nullif(p_payload->>'meta_peso_desejado_kg', '')::numeric,
    nullif(p_payload->>'meta_percentual_gordura_desejado', '')::numeric,
    nullif(p_payload->>'meta_massa_desejada_kg', '')::numeric,
    nullif(p_payload->>'meta_prazo', '')::date,
    nullif(p_payload->>'meta_outro_indicador', ''),
    nullif(p_payload->>'percentual_gordura', '')::numeric,
    nullif(p_payload->>'massa_gorda_kg', '')::numeric,
    nullif(p_payload->>'massa_magra_kg', '')::numeric,
    nullif(p_payload->>'massa_muscular_kg', '')::numeric,
    nullif(p_payload->>'circunferencia_cintura_cm', '')::numeric,
    nullif(p_payload->>'circunferencia_abdominal_cm', '')::numeric,
    nullif(p_payload->>'metodo_avaliacao_composicao', ''),
    nullif(p_payload->>'fonte_composicao_corporal', ''),
    nullif(p_payload->>'houve_alteracao_peso_nao_planejada', ''),
    nullif(p_payload->>'numero_refeicoes_dia', '')::smallint,
    nullif(p_payload->>'regularidade_alimentar', ''),
    nullif(p_payload->>'consumo_ultraprocessados', ''),
    nullif(p_payload->>'preferencias_alimentares', ''),
    nullif(p_payload->>'alimentos_evitados', ''),
    coalesce((select array_agg(value #>> '{}') from jsonb_array_elements(coalesce(p_payload->'restricoes_alimentares', '[]'::jsonb))), '{}'),
    coalesce((select array_agg(value #>> '{}') from jsonb_array_elements(coalesce(p_payload->'intolerancias_alimentares', '[]'::jsonb))), '{}'),
    nullif(p_payload->>'padrao_alimentar_habitual', ''),
    coalesce((select array_agg(value #>> '{}') from jsonb_array_elements(coalesce(p_payload->'restricoes_culturais_religiosas', '[]'::jsonb))), '{}'),
    p_payload->'refeicoes_diarias_habituais',
    nullif(p_payload->>'rotina_diaria', ''),
    nullif(p_payload->>'atividade_ocupacional', ''),
    nullif(p_payload->>'horas_sono_medias', '')::numeric,
    nullif(p_payload->>'horario_dormir_habitual', '')::time,
    nullif(p_payload->>'horario_acordar_habitual', '')::time,
    nullif(p_payload->>'qualidade_sono_percebida', ''),
    nullif(p_payload->>'despertares_noturnos', '')::smallint,
    nullif(p_payload->>'sono_observacoes', ''),
    (p_payload->>'possui_condicao_saude')::boolean,
    p_payload->'bloco_idoso',
    p_payload->'bloco_atleta',
    p_payload->'bloco_recomposicao',
    p_payload->'bloco_diabetes',
    p_payload->'bloco_doenca_renal',
    nullif(p_payload->>'data_validade', '')::timestamptz
  )
  returning id into v_anamnese_id;

  for v_item in select * from jsonb_array_elements(v_atividades)
  loop
    insert into public.anamneses_atividades_dias (anamnese_id, atividade_id, dia_semana, minutos, intensidade)
    values (
      v_anamnese_id,
      (v_item->>'atividade_id')::smallint,
      (v_item->>'dia_semana')::smallint,
      (v_item->>'minutos')::int,
      coalesce(nullif(v_item->>'intensidade', ''), 'moderada')
    );
  end loop;

  for v_item in select * from jsonb_array_elements(coalesce(p_payload->'condicoes_saude', '[]'::jsonb))
  loop
    insert into public.anamneses_problemas_saude (anamnese_id, problema_saude_id, data_diagnostico, status, profissional_responsavel, observacoes)
    values (
      v_anamnese_id,
      (v_item->>'problema_saude_id')::uuid,
      nullif(v_item->>'data_diagnostico', '')::date,
      nullif(v_item->>'status', ''),
      nullif(v_item->>'profissional_responsavel', ''),
      nullif(v_item->>'observacoes', '')
    );
  end loop;

  for v_item in select * from jsonb_array_elements(v_alergias)
  loop
    insert into public.anamneses_alergias (anamnese_id, alergia_id)
    values (v_anamnese_id, (v_item->>0)::uuid);
  end loop;

  for v_item in select * from jsonb_array_elements(v_medicamentos)
  loop
    insert into public.anamneses_medicamentos (anamnese_id, nome, dose, unidade, frequencia)
    values (v_anamnese_id, v_item->>'nome', nullif(v_item->>'dose', '')::numeric, nullif(v_item->>'unidade', ''), nullif(v_item->>'frequencia', ''));
  end loop;

  for v_item in select * from jsonb_array_elements(v_suplementos)
  loop
    insert into public.anamneses_suplementos (anamnese_id, nome, dose, unidade, objetivo)
    values (v_anamnese_id, v_item->>'nome', nullif(v_item->>'dose', '')::numeric, nullif(v_item->>'unidade', ''), nullif(v_item->>'objetivo', ''));
  end loop;

  for v_item in select * from jsonb_array_elements(v_exames)
  loop
    insert into public.anamneses_exames_laboratoriais (anamnese_id, nome_exame, resultado, unidade)
    values (v_anamnese_id, v_item->>'nome_exame', nullif(v_item->>'resultado', ''), nullif(v_item->>'unidade', ''));
  end loop;

  return jsonb_build_object('sucesso', true, 'anamnese_id', v_anamnese_id);
end;
$$;

comment on function public.profissional_salvar_anamnese(uuid, jsonb) is
  'RELATÓRIO 20260917_0001 + 20260918_0001 + 20260922_0001 + 20260927_0001 (Item 1a: horarios_refeicoes_habituais/refeicoes_fora_de_casa removidos do INSERT, colunas descontinuadas). Profissional com vínculo ATIVO preenche uma anamnese nova pro paciente. SEM trava de carência.';

revoke execute on function public.profissional_salvar_anamnese(uuid, jsonb) from public;
grant execute on function public.profissional_salvar_anamnese(uuid, jsonb) to authenticated;
