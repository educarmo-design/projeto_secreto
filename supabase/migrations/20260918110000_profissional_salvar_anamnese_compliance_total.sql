-- RELATÓRIO 20260918_0001 (continuação) — Fix crítico + extensão de
-- `profissional_salvar_anamnese` pra acompanhar a migration anterior
-- (`20260918100000`).
--
-- FIX CRÍTICO: `anamneses_atividades_dias.intensidade` virou NOT NULL sem
-- default nesta mesma tarefa (Bloco 6, "obrigatório" — pedido explícito do
-- fundador) — mas esta RPC (criada numa tarefa anterior, 20260917120000)
-- não enviava essa coluna no INSERT. Sem este patch, TODA chamada de
-- `profissional_salvar_anamnese` com pelo menos 1 atividade quebraria com
-- "null value in column intensidade violates not-null constraint" a partir
-- de agora. Corrigido com `coalesce(..., 'moderada')` — aceita o valor
-- vindo do payload (a nova tela React vai mandar), mas não quebra
-- chamadores antigos que ainda não mandam.
--
-- EXTENSÃO: mesmo payload rico que `AnamneseRepository.salvarAnamnese`
-- (Flutter) já grava desde `20260918100000` — o profissional passa a poder
-- preencher os mesmos Blocos 1-12 pelo paciente.
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
    numero_refeicoes_dia, horarios_refeicoes_habituais, regularidade_alimentar,
    refeicoes_fora_de_casa, consumo_ultraprocessados, preferencias_alimentares,
    alimentos_evitados, restricoes_alimentares, intolerancias_alimentares, padrao_alimentar_habitual,
    rotina_diaria, atividade_ocupacional,
    horas_sono_medias, horario_dormir_habitual, horario_acordar_habitual,
    qualidade_sono_percebida, despertares_noturnos, sono_observacoes,
    possui_condicao_saude,
    bloco_idoso, bloco_atleta, bloco_recomposicao, bloco_diabetes, bloco_doenca_renal
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
    -- Profissional confirma implicitamente ao submeter o formulário — o
    -- Painel Web não tem uma 2ª tela de confirmação separada (diferente do
    -- app, Seção 11), o próprio ato de clicar "Salvar Anamnese" já é a
    -- confirmação profissional.
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
    nullif(p_payload->>'horarios_refeicoes_habituais', ''),
    nullif(p_payload->>'regularidade_alimentar', ''),
    nullif(p_payload->>'refeicoes_fora_de_casa', ''),
    nullif(p_payload->>'consumo_ultraprocessados', ''),
    nullif(p_payload->>'preferencias_alimentares', ''),
    nullif(p_payload->>'alimentos_evitados', ''),
    coalesce((select array_agg(value #>> '{}') from jsonb_array_elements(coalesce(p_payload->'restricoes_alimentares', '[]'::jsonb))), '{}'),
    coalesce((select array_agg(value #>> '{}') from jsonb_array_elements(coalesce(p_payload->'intolerancias_alimentares', '[]'::jsonb))), '{}'),
    nullif(p_payload->>'padrao_alimentar_habitual', ''),
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
    p_payload->'bloco_doenca_renal'
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
  'RELATÓRIO 20260917_0001 (item 2) + RELATÓRIO 20260918_0001 (compliance total, Blocos 1-16): profissional com vínculo ATIVO preenche uma anamnese nova pro paciente, cobrindo os mesmos campos que o self-service do App grava. SEM trava de carência. Mesmo princípio de anamneses_trg_versionar: sempre um INSERT novo.';

revoke execute on function public.profissional_salvar_anamnese(uuid, jsonb) from public;
grant execute on function public.profissional_salvar_anamnese(uuid, jsonb) to authenticated;
