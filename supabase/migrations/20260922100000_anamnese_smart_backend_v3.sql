-- RELATÓRIO 20260922_0001 — "Upgrade massivo na inteligência da Anamnese":
-- motor de agregação de dados de smartwatch (médias reais, confiabilidade,
-- estatística por dia da semana), composição corporal automática, schema
-- pronto para dieta por IA, e validade parametrizada da anamnese. 100%
-- Backend/Supabase — nenhum arquivo Flutter/React tocado.
--
-- ============================================================================
-- Parte 1 — Colunas novas em `anamneses` (Itens 4 e 5 da tarefa)
-- ============================================================================
alter table anamneses
  -- Item 4 — "Estrutura para Dieta Baseada em IA e Restrições".
  add column if not exists restricoes_culturais_religiosas text[] not null default '{}',
  -- Array de refeições habituais — schema pronto pra IA consumir depois
  -- (RELATÓRIO 20260922_0001): cada elemento é
  -- `{numero_refeicao: int, horario: "HH:MM", fora_de_casa: bool,
  --   descricao_texto: text, kcal: numeric, proteina_g: numeric,
  --   carboidrato_g: numeric, gordura_g: numeric}`. Não há catálogo/tabela
  -- separada de propósito — é um rascunho estruturado que a IA vai LER,
  -- não uma fonte de verdade nutricional (essa continua sendo o Diário
  -- Alimentar existente).
  add column if not exists refeicoes_diarias_habituais jsonb,
  -- Item 5 — Validade da anamnese.
  add column if not exists data_validade timestamptz;

comment on column anamneses.restricoes_culturais_religiosas is
  'Item 4 (RELATÓRIO 20260922_0001) — array livre (ex.: "Halal", "Kosher", "Vegetariano religioso"), ao lado de restricoes_alimentares/intolerancias_alimentares/alergias. Sem catálogo curado de propósito (mesmo motivo de intolerancias_alimentares: universo grande demais pra um catálogo fechado agora).';
comment on column anamneses.refeicoes_diarias_habituais is
  'Item 4 (RELATÓRIO 20260922_0001) — array JSONB de refeições habituais, schema pronto para IA de sugestão de dieta consumir posteriormente. Cada elemento: {numero_refeicao, horario "HH:MM", fora_de_casa bool, descricao_texto, kcal, proteina_g, carboidrato_g, gordura_g}. Todos os campos de cada elemento são opcionais (a IA/usuário preenche o que souber) — só a forma de array é validada pelo CHECK abaixo, não o conteúdo de cada objeto.';
comment on column anamneses.data_validade is
  'Item 5 (RELATÓRIO 20260922_0001) — até quando esta anamnese é considerada válida. Preenchida automaticamente pelo trigger `anamneses_trg_computar_campos_automaticos` quando o INSERT não traz um valor explícito (caminho self-service: data_preenchimento + configuracoes_sistema.anamnese_dias_validade_padrao); o profissional pode escolher a própria data via `profissional_salvar_anamnese` (payload.data_validade), que nesse caso é respeitada e nunca sobrescrita.';

alter table anamneses drop constraint if exists anamneses_refeicoes_diarias_habituais_check;
alter table anamneses add constraint anamneses_refeicoes_diarias_habituais_check
  check (refeicoes_diarias_habituais is null or jsonb_typeof(refeicoes_diarias_habituais) = 'array');

-- ============================================================================
-- Parte 2 — Parâmetro de validade (Item 5)
-- ============================================================================
insert into configuracoes_sistema (chave, valor, descricao) values
  ('anamnese_dias_validade_padrao', '30', 'Quantos dias uma anamnese self-service (sem profissional escolhendo a data) fica válida — usado pelo trigger anamneses_trg_computar_campos_automaticos como data_criacao + este valor. RELATÓRIO 20260922_0001.')
on conflict (chave) do nothing;

-- ============================================================================
-- Parte 3 — Motor de Composição Corporal + Validade automática (Itens 3 e 5)
-- ============================================================================
-- BEFORE INSERT (anamneses é INSERT-only — nunca há UPDATE a interceptar).
-- Regra de não-clobber em AMBOS os cálculos: só preenche o que vier NULO no
-- payload. Isso cobre os dois caminhos de escrita (App self-service via
-- `.insert()` direto pela RLS `anamneses_insert_own`, e profissional via
-- `profissional_salvar_anamnese`) sem precisar tocar em nenhum dos dois —
-- o trigger roda pra qualquer INSERT na tabela, seja qual for a origem.
create or replace function public.anamneses_trg_computar_campos_automaticos()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_massa_gorda_calculada numeric;
  v_dias_validade_padrao int;
begin
  -- Item 3 — "se o payload vier com peso e percentual_gordura (ex: de
  -- balança inteligente), o backend DEVE interceptar e auto-calcular
  -- massa_gorda_kg e massa_magra_kg antes de gravar." Só preenche os
  -- campos que vierem NULOS — nunca sobrescreve um valor já informado
  -- explicitamente (ex.: profissional com bioimpedância própria, método
  -- diferente do "peso × %gordura").
  if new.peso_kg is not null and new.percentual_gordura is not null
     and (new.massa_gorda_kg is null or new.massa_magra_kg is null)
  then
    v_massa_gorda_calculada := coalesce(new.massa_gorda_kg, round(new.peso_kg * (new.percentual_gordura / 100.0), 2));
    if new.massa_gorda_kg is null then
      new.massa_gorda_kg := v_massa_gorda_calculada;
    end if;
    if new.massa_magra_kg is null then
      new.massa_magra_kg := round(new.peso_kg - v_massa_gorda_calculada, 2);
    end if;
  end if;

  -- Item 5 — "Se for usuário com profissional: gravar a data escolhida
  -- pelo profissional [payload já trouxe data_validade, não mexe aqui].
  -- Se for usuário self-service: gravar data_criacao + parâmetro padrão."
  if new.data_validade is null then
    select coalesce(valor::int, 30) into v_dias_validade_padrao
    from public.configuracoes_sistema
    where chave = 'anamnese_dias_validade_padrao';

    new.data_validade := coalesce(new.data_preenchimento, now()) + make_interval(days => coalesce(v_dias_validade_padrao, 30));
  end if;

  return new;
end;
$$;

drop trigger if exists anamneses_trg_computar_campos_automaticos on anamneses;
create trigger anamneses_trg_computar_campos_automaticos
  before insert on anamneses
  for each row
  execute function public.anamneses_trg_computar_campos_automaticos();

comment on trigger anamneses_trg_computar_campos_automaticos on anamneses is
  'RELATÓRIO 20260922_0001 — Itens 3 e 5: auto-calcula massa_gorda_kg/massa_magra_kg (peso×%gordura) e data_validade (data_criacao + anamnese_dias_validade_padrao) quando o INSERT não os traz explicitamente. Mesmo princípio de anamneses_trg_versionar (BEFORE INSERT, security definer) — ordem de execução entre os dois triggers não importa, cada um só mexe em colunas que o outro não toca.';

-- ============================================================================
-- Parte 4 — profissional_salvar_anamnese: aceita data_validade explícita +
-- os 2 campos novos do Item 4 (Restrição: sem tocar Flutter/React, só o
-- payload jsonb da RPC ganha campos NOVOS e OPCIONAIS — nenhum contrato
-- existente quebra; quem não enviar esses campos continua funcionando
-- exatamente igual).
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
    numero_refeicoes_dia, horarios_refeicoes_habituais, regularidade_alimentar,
    refeicoes_fora_de_casa, consumo_ultraprocessados, preferencias_alimentares,
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
    nullif(p_payload->>'horarios_refeicoes_habituais', ''),
    nullif(p_payload->>'regularidade_alimentar', ''),
    nullif(p_payload->>'refeicoes_fora_de_casa', ''),
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
  'RELATÓRIO 20260917_0001 (item 2) + 20260918_0001 (compliance total) + 20260922_0001 (Item 4: restricoes_culturais_religiosas/refeicoes_diarias_habituais; Item 5: data_validade explícita — se o payload não trouxer, o trigger anamneses_trg_computar_campos_automaticos calcula o padrão self-service mesmo assim). Profissional com vínculo ATIVO preenche uma anamnese nova pro paciente. SEM trava de carência.';

revoke execute on function public.profissional_salvar_anamnese(uuid, jsonb) from public;
grant execute on function public.profissional_salvar_anamnese(uuid, jsonb) to authenticated;

-- ============================================================================
-- Parte 5 — Item 1: Motor de Inicialização e Histórico
-- ============================================================================
-- Regra de Janela de Tempo: sem anamnese anterior -> últimos 30 dias; com
-- anterior -> desde a data dela até agora (usada pela RPC do Item 2 em
-- seguida). Preenchimento automático: copia sexo_biologico (lido "ao vivo"
-- de perfis_usuarios, nunca uma cópia potencialmente desatualizada dentro
-- da anamnese anterior), condições de saúde, alergias e as 3 restrições
-- (alimentares/intolerâncias/culturais-religiosas) da última anamnese —
-- exatamente os 4 grupos citados na tarefa, nada além disso. Função PURA
-- (só leitura, nenhum insert/update/delete).
create or replace function public.iniciar_rascunho_anamnese(p_usuario_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anamnese_anterior_id uuid;
  v_data_anterior timestamptz;
  v_janela_inicio timestamptz;
  v_janela_fim timestamptz := now();
  v_sexo_biologico public.sexo_biologico_enum;
  v_possui_condicao_saude boolean;
  v_restricoes_alimentares text[];
  v_intolerancias_alimentares text[];
  v_restricoes_culturais_religiosas text[];
  v_condicoes jsonb;
  v_alergias jsonb;
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
    raise exception 'Sem acesso ao rascunho de anamnese deste usuário.';
  end if;

  select a.id, a.data_preenchimento, a.possui_condicao_saude,
         a.restricoes_alimentares, a.intolerancias_alimentares, a.restricoes_culturais_religiosas
  into v_anamnese_anterior_id, v_data_anterior, v_possui_condicao_saude,
       v_restricoes_alimentares, v_intolerancias_alimentares, v_restricoes_culturais_religiosas
  from public.anamneses a
  where a.usuario_id = p_usuario_id
  order by a.data_preenchimento desc
  limit 1;

  if v_anamnese_anterior_id is null then
    v_janela_inicio := now() - interval '30 days';
  else
    v_janela_inicio := v_data_anterior;
  end if;

  select p.sexo_biologico into v_sexo_biologico
  from public.perfis_usuarios p
  where p.id = p_usuario_id;

  if v_anamnese_anterior_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'problema_saude_id', ps.id,
             'nome', ps.nome,
             'data_diagnostico', apz.data_diagnostico,
             'status', apz.status,
             'profissional_responsavel', apz.profissional_responsavel,
             'observacoes', apz.observacoes
           )), '[]'::jsonb)
    into v_condicoes
    from public.anamneses_problemas_saude apz
    join public.problemas_saude ps on ps.id = apz.problema_saude_id
    where apz.anamnese_id = v_anamnese_anterior_id;

    select coalesce(jsonb_agg(jsonb_build_object(
             'alergia_id', al.id,
             'nome_exibicao', al.nome_exibicao
           )), '[]'::jsonb)
    into v_alergias
    from public.anamneses_alergias aal
    join public.alergias al on al.id = aal.alergia_id
    where aal.anamnese_id = v_anamnese_anterior_id;
  else
    v_condicoes := '[]'::jsonb;
    v_alergias := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'janela', jsonb_build_object(
      'data_inicio', v_janela_inicio,
      'data_fim', v_janela_fim,
      'anamnese_anterior_id', v_anamnese_anterior_id,
      'anamnese_anterior_data', v_data_anterior,
      'dias_totais', ceil(extract(epoch from (v_janela_fim - v_janela_inicio)) / 86400.0)
    ),
    'rascunho', jsonb_build_object(
      'sexo_biologico', v_sexo_biologico,
      'possui_condicao_saude', v_possui_condicao_saude,
      'condicoes_saude', v_condicoes,
      'alergias', v_alergias,
      'restricoes_alimentares', to_jsonb(coalesce(v_restricoes_alimentares, '{}')),
      'intolerancias_alimentares', to_jsonb(coalesce(v_intolerancias_alimentares, '{}')),
      'restricoes_culturais_religiosas', to_jsonb(coalesce(v_restricoes_culturais_religiosas, '{}'))
    )
  );
end;
$$;

comment on function public.iniciar_rascunho_anamnese(uuid) is
  'RELATÓRIO 20260922_0001 (Item 1) — Motor de Inicialização e Histórico. Calcula a janela de tempo (30 dias sem anamnese anterior, ou desde a última anamnese) e devolve um rascunho copiando sexo_biologico (atualizado, lido de perfis_usuarios)/condições de saúde/alergias/restrições da última anamnese, pra pré-preencher o formulário e alimentar processar_medias_smartwatch. Função PURA (só leitura).';

revoke execute on function public.iniciar_rascunho_anamnese(uuid) from public;
grant execute on function public.iniciar_rascunho_anamnese(uuid) to authenticated;

-- ============================================================================
-- Parte 6 — Item 2: Motor de Agregação de Smartwatch e Matemática de
-- Confiabilidade
-- ============================================================================
-- Fontes: `metricas_saude_diarias` (1 linha/usuário/dia — passos, distância,
-- FC repouso, HRV, calorias, sono, peso, %gordura) e
-- `atividades_fisicas_treinos` (1 linha por treino real, com
-- início/fim/modalidade — a fonte de verdade de "Atividades por Dia da
-- Semana"/"Carga do Atleta", já que `anamneses_atividades_dias` é a rotina
-- AUTORRELATADA de uma anamnese específica, não um log histórico de
-- treinos reais). Função PURA (só leitura).
--
-- Lógica de agrupamento estatístico (documentada aqui e no relatório):
--
-- 1) Médias diárias — `avg()` do Postgres já ignora NULL por padrão, então
--    a média de cada métrica já sai dividida só pelos dias com dado (não
--    por 30 fixo). `percentual_confiabilidade` = dias com aquele dado não
--    nulo ÷ dias totais do período × 100.
--
-- 2) Atividades por dia da semana + modalidade — para cada dia da semana
--    (0=domingo..6=sábado) dentro de [p_data_inicio, p_data_fim], calcula
--    PRIMEIRO quantas vezes aquele dia da semana especificamente ocorre no
--    período (`contagem_dow`, via generate_series) — esse é o denominador
--    estatisticamente correto ("pelo número daquele dia específico contido
--    no período", não 4 ou 30 fixos). Duração total e nº de ocorrências de
--    cada modalidade naquele dia da semana são então divididos por esse
--    denominador, dando "quantos minutos/quantas vezes NAQUELE dia da
--    semana, em média, por semana do período".
--
-- 3) Carga do Atleta — soma todas as horas de treino (qualquer dia,
--    qualquer modalidade) no período inteiro, dividido pelo nº de semanas
--    do período (dias totais ÷ 7, fracionário — não arredondado).
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
    -- Base com as 7 chaves sempre presentes (mesmo sem nenhuma atividade
    -- naquele dia — `[]`, não uma chave ausente), sobreposta pelo que
    -- realmente foi agrupado.
    jsonb_build_object('0', '[]'::jsonb, '1', '[]'::jsonb, '2', '[]'::jsonb, '3', '[]'::jsonb, '4', '[]'::jsonb, '5', '[]'::jsonb, '6', '[]'::jsonb)
    || coalesce(jsonb_object_agg(dow::text, itens), '{}'::jsonb)
  into v_atividades_por_dia
  from agrupado_por_dia;

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
    'carga_atleta', v_carga,
    'calculado_em', now()
  );
end;
$$;

comment on function public.processar_medias_smartwatch(uuid, timestamptz, timestamptz) is
  'RELATÓRIO 20260922_0001 (Item 2) — Motor de Agregação de Smartwatch. Usa a janela devolvida por iniciar_rascunho_anamnese. Médias por métrica ignoram dias sem dado (avg() do Postgres já faz isso) e vêm com percentual_confiabilidade (dias com dado ÷ dias totais); atividades por dia da semana são divididas pelo nº real de vezes que aquele dia ocorreu no período (não uma constante); Carga do Atleta soma todas as horas de treino do período ÷ nº de semanas (fracionário). Função PURA (só leitura). fonte sempre "smartwatch".';

revoke execute on function public.processar_medias_smartwatch(uuid, timestamptz, timestamptz) from public;
grant execute on function public.processar_medias_smartwatch(uuid, timestamptz, timestamptz) to authenticated;
