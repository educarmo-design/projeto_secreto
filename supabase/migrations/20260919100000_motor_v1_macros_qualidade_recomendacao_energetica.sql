-- RELATÓRIO 20260919_0001 — fecha o gap real da tarefa anterior: o
-- documento docs/motor_metabolico.txt tem ~1.300 linhas a mais do que
-- foram lidas naquela tarefa (a contagem de linhas usada pra guiar a
-- leitura estava incorreta) — nelas estão as seções "Motor Metabólico —
-- Protocolos de Macronutrientes V1.0", "Motor Metabólico — Definição da
-- Meta Energética V1.0" e "Definição de Cálculos, Metas e Prescrição —
-- V1.0" (ME-001 a ME-009), com fórmulas explícitas que não foram
-- implementadas. Corrigido aqui, lendo o documento completo (3512 linhas).
--
-- `calcular_motor_metabolico_v1` (`20260916120000`) ganha 3 blocos novos
-- de saída — TODOS informativos (ME-001/ME-005/ME-006: "resultado
-- calculado" e "recomendação do sistema" NUNCA são a mesma coisa que
-- "meta" registrada; esta função continua pura, nenhum insert/update/
-- delete, e o app/painel continuam exigindo confirmação explícita do
-- usuário/profissional antes de qualquer meta ser salva — nada disso
-- muda aqui):
--
-- 1. `qualidade` — Bloco 15/Regra 25: score Alta/Média/Baixa (heurística
--    pedida explicitamente pelo fundador, já que o documento não define
--    uma fórmula de score).
-- 2. `energia_recomendacao` — "Motor Metabólico — Definição da Meta
--    Energética V1.0": manutenção → TDEE médio; perda de peso/redução de
--    gordura → TDEE médio − déficit parametrizado conservador (Seção 5,
--    "tabela parametrizada" simplificada aqui pra 1 parâmetro versionado
--    — não os 6 fatores completos que o documento lista, ver relatório).
-- 3. `macros_recomendados` — "Motor Metabólico — Protocolos de
--    Macronutrientes V1.0": MACRO-001 (percentual energético) e MACRO-002
--    (proteína/gordura g/kg + carboidrato residual), matemática copiada
--    literalmente das Seções 4 e 5 daquele bloco, com a validação da
--    Seção 16 (`kcal proteína + kcal carboidrato + kcal gordura =
--    energia-alvo`).
create or replace function public.calcular_motor_metabolico_v1(p_usuario_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_idade int;
  v_sexo public.sexo_biologico_enum;
  v_altura_cm numeric;
  v_peso_kg numeric;
  v_peso_data_medicao date;
  v_anamnese_id uuid;
  v_objetivo_codigo text;
  v_massa_magra_kg numeric;
  v_percentual_gordura numeric;
  v_tmb numeric;
  v_tef numeric;
  v_avisos text[] := '{}';
  v_pal_padrao constant numeric := 1.2;
  v_pal_versao constant text := 'PAL-001-sedentario-v1';
  v_usa_decomposicao_anamnese boolean;
  v_dia int;
  v_tem_atividade_no_dia boolean;
  v_eat_dia numeric;
  v_tdee_dia numeric;
  v_estrategia_dia text;
  v_detalhe jsonb := '{}'::jsonb;
  v_soma_tdee numeric := 0;
  v_dias_com_tdee int := 0;
  v_tdee_medio numeric;
  v_estrategia_geral text;

  -- Bloco 15/Regra 25 — Score de Qualidade (heurística do fundador, RELATÓRIO 20260919_0001).
  v_score_qualidade text;
  v_motivos_qualidade text[] := '{}';

  -- "Definição da Meta Energética V1.0", Seções 4/5 — recomendação do
  -- SISTEMA (nunca a meta salva — ME-003/ME-005/ME-006). Déficit único
  -- parametrizado e versionado (simplificação documentada da "tabela"
  -- completa de 6 fatores que o texto pede — ver relatório da tarefa).
  v_deficit_percentual_padrao constant numeric := 0.15;
  v_deficit_versao constant text := 'DEFICIT-001-conservador-v1';
  v_estrategia_energetica text;
  v_deficit_aplicado numeric;
  v_energia_recomendacao_media numeric;

  -- "Protocolos de Macronutrientes V1.0", Seções 4/5 — MACRO-001/MACRO-002.
  v_macro001_pct_proteina constant numeric := 0.25;
  v_macro001_pct_carboidrato constant numeric := 0.45;
  v_macro001_pct_gordura constant numeric := 0.30;
  v_macro001_versao constant text := 'MACRO-001-default-v1';
  v_macro001_proteina_kcal numeric;
  v_macro001_carboidrato_kcal numeric;
  v_macro001_gordura_kcal numeric;
  v_macro001_proteina_g numeric;
  v_macro001_carboidrato_g numeric;
  v_macro001_gordura_g numeric;
  v_macro001_valido boolean;

  v_macro002_proteina_g_por_kg constant numeric := 1.6;
  v_macro002_gordura_g_por_kg constant numeric := 0.8;
  v_macro002_versao constant text := 'MACRO-002-default-v1';
  v_macro002_proteina_g numeric;
  v_macro002_proteina_kcal numeric;
  v_macro002_gordura_g numeric;
  v_macro002_gordura_kcal numeric;
  v_macro002_carboidrato_kcal numeric;
  v_macro002_carboidrato_g numeric;
  v_macro002_valido boolean;

  -- Tolerância de arredondamento pra validação da Seção 16 ("kcal
  -- proteína + kcal carboidrato + kcal gordura = energia-alvo").
  v_tolerancia_kcal constant numeric := 2;
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
    raise exception 'Sem acesso ao Motor Metabólico deste usuário.';
  end if;

  select public.calcular_idade(p.data_nascimento), p.sexo_biologico
  into v_idade, v_sexo
  from public.perfis_usuarios p
  where p.id = p_usuario_id;

  -- SSOT: peso/altura/objetivo/composição corporal vêm da ÚLTIMA ANAMNESE
  -- VÁLIDA (mais recente com peso+altura preenchidos) — mesma fonte já
  -- usada, agora também lendo objetivo_codigo/massa_magra_kg/
  -- percentual_gordura (Blocos 2/3, RELATÓRIO 20260918_0001) pra alimentar
  -- a recomendação energética/macros/qualidade desta migration.
  select a.peso_kg, a.altura_cm, a.id, a.peso_data_medicao, a.objetivo_codigo, a.massa_magra_kg, a.percentual_gordura
  into v_peso_kg, v_altura_cm, v_anamnese_id, v_peso_data_medicao, v_objetivo_codigo, v_massa_magra_kg, v_percentual_gordura
  from public.anamneses a
  where a.usuario_id = p_usuario_id
    and a.peso_kg is not null
    and a.altura_cm is not null
  order by a.data_preenchimento desc
  limit 1;

  if v_anamnese_id is null then
    v_avisos := array_append(v_avisos, 'sem_anamnese_com_dados_antropometricos');
  end if;
  if v_idade is null then v_avisos := array_append(v_avisos, 'sem_data_nascimento'); end if;
  if v_sexo is null then v_avisos := array_append(v_avisos, 'sem_sexo_biologico'); end if;
  if v_peso_kg is null then v_avisos := array_append(v_avisos, 'sem_peso'); end if;
  if v_altura_cm is null then v_avisos := array_append(v_avisos, 'sem_altura'); end if;

  if v_idade is not null and v_sexo is not null and v_peso_kg is not null and v_altura_cm is not null then
    v_tmb := (10 * v_peso_kg) + (6.25 * v_altura_cm) - (5 * v_idade)
             + (case v_sexo when 'M' then 5 else -161 end);
  else
    v_tmb := null;
    v_avisos := array_append(v_avisos, 'tmb_nao_calculada_dados_insuficientes');
  end if;

  v_tef := case when v_tmb is not null then v_tmb * 0.10 else null end;

  v_usa_decomposicao_anamnese := v_anamnese_id is not null and exists (
    select 1 from public.anamneses_atividades_dias where anamnese_id = v_anamnese_id
  );

  for v_dia in 0..6 loop
    if v_tmb is null then
      v_tdee_dia := null;
      v_estrategia_dia := 'dados_insuficientes';
    else
      v_tem_atividade_no_dia := v_usa_decomposicao_anamnese and exists (
        select 1 from public.anamneses_atividades_dias
        where anamnese_id = v_anamnese_id and dia_semana = v_dia
      );

      if v_tem_atividade_no_dia then
        select coalesce(sum(coalesce(t.met_estimado, 0) * v_peso_kg * (aad.minutos / 60.0)), 0)
        into v_eat_dia
        from public.anamneses_atividades_dias aad
        join public.tipos_atividades_fisicas t on t.id = aad.atividade_id
        where aad.anamnese_id = v_anamnese_id and aad.dia_semana = v_dia;

        v_tdee_dia := v_tmb + v_eat_dia + v_tef;
        v_estrategia_dia := 'decomposicao';
      else
        v_tdee_dia := v_tmb * v_pal_padrao;
        v_estrategia_dia := 'pal';
      end if;
    end if;

    v_detalhe := v_detalhe || jsonb_build_object(
      v_dia::text,
      jsonb_build_object(
        'tdee', case when v_tdee_dia is not null then round(v_tdee_dia, 1) else null end,
        'estrategia', v_estrategia_dia
      )
    );

    if v_tdee_dia is not null then
      v_soma_tdee := v_soma_tdee + v_tdee_dia;
      v_dias_com_tdee := v_dias_com_tdee + 1;
    end if;
  end loop;

  v_tdee_medio := case when v_dias_com_tdee = 7 then round(v_soma_tdee / 7, 1) else null end;
  v_estrategia_geral := case when v_usa_decomposicao_anamnese then 'decomposicao_parcial' else 'pal' end;

  -- ==========================================================================
  -- Bloco 15/Regra 25 — Score de Qualidade (heurística explícita do
  -- fundador, RELATÓRIO 20260919_0001 — o documento não define uma
  -- fórmula, só exige o registro de "um" score).
  -- ==========================================================================
  if v_tmb is null then
    v_score_qualidade := 'baixa';
    v_motivos_qualidade := array_append(v_motivos_qualidade, 'dados_insuficientes_para_tmb');
  elsif v_estrategia_geral = 'decomposicao_parcial' and v_massa_magra_kg is not null and v_percentual_gordura is not null then
    v_score_qualidade := 'alta';
    v_motivos_qualidade := array_append(v_motivos_qualidade, 'decomposicao_com_composicao_corporal_confirmada');
  else
    v_score_qualidade := 'media';
    if v_estrategia_geral = 'pal' then
      v_motivos_qualidade := array_append(v_motivos_qualidade, 'estrategia_fallback_pal');
    end if;
    if v_massa_magra_kg is null or v_percentual_gordura is null then
      v_motivos_qualidade := array_append(v_motivos_qualidade, 'sem_composicao_corporal_confirmada');
    end if;
  end if;

  -- ==========================================================================
  -- "Definição da Meta Energética V1.0", Seções 4/5 — recomendação do
  -- SISTEMA (nunca a meta — ME-003/ME-005/ME-006, continua exigindo
  -- confirmação explícita em validar_e_salvar_meta). Só objetivos
  -- manter_peso/perder_peso/reduzir_gordura_corporal têm estratégia
  -- automática na V1 — ganho de peso/massa muscular/recomposição/
  -- performance exigem avaliação profissional (Seções 6-8 do mesmo
  -- bloco: "não deverá aplicar automaticamente superávit"/"não deverá
  -- ser tratada simplesmente como TDEE±X"/"a definição deverá ser do
  -- profissional") — fora do escopo desta tarefa, que pede
  -- explicitamente só manutenção e perda de peso.
  -- ==========================================================================
  if v_tdee_medio is not null and v_objetivo_codigo is not null then
    if v_objetivo_codigo = 'manter_peso' then
      v_estrategia_energetica := 'manutencao';
      v_energia_recomendacao_media := v_tdee_medio;
    elsif v_objetivo_codigo in ('perder_peso', 'reduzir_gordura_corporal') then
      v_estrategia_energetica := 'deficit_conservador';
      v_deficit_aplicado := v_deficit_percentual_padrao;
      v_energia_recomendacao_media := round(v_tdee_medio * (1 - v_deficit_percentual_padrao), 1);
    else
      v_avisos := array_append(v_avisos, 'objetivo_sem_estrategia_energetica_automatica_v1');
    end if;
  elsif v_objetivo_codigo is null then
    v_avisos := array_append(v_avisos, 'sem_objetivo_para_recomendacao_energetica');
  end if;

  -- ==========================================================================
  -- "Protocolos de Macronutrientes V1.0", Seções 4/5 — só calculados
  -- quando há energia-alvo (recomendação acima) E peso (pra MACRO-002).
  -- ==========================================================================
  if v_energia_recomendacao_media is not null and v_peso_kg is not null then
    -- MACRO-001 — Percentual energético (Seção 4): "gramas = kcal ×
    -- percentual ÷ 4" (proteína/carboidrato), "÷ 9" (gordura).
    v_macro001_proteina_kcal := v_energia_recomendacao_media * v_macro001_pct_proteina;
    v_macro001_carboidrato_kcal := v_energia_recomendacao_media * v_macro001_pct_carboidrato;
    v_macro001_gordura_kcal := v_energia_recomendacao_media * v_macro001_pct_gordura;
    v_macro001_proteina_g := round(v_macro001_proteina_kcal / 4, 1);
    v_macro001_carboidrato_g := round(v_macro001_carboidrato_kcal / 4, 1);
    v_macro001_gordura_g := round(v_macro001_gordura_kcal / 9, 1);
    -- Validação Seção 16: soma das kcal (recalculadas a partir dos
    -- gramas já arredondados, não dos valores fracionários internos —
    -- é isso que "resultado apresentado" realmente soma) deve bater com
    -- a energia-alvo dentro da tolerância de arredondamento.
    v_macro001_valido := abs((v_macro001_proteina_g * 4 + v_macro001_carboidrato_g * 4 + v_macro001_gordura_g * 9) - v_energia_recomendacao_media) <= v_tolerancia_kcal;

    -- MACRO-002 — Proteína/gordura g/kg + carboidrato residual (Seção 5):
    -- "P(g) = peso × meta_proteína_g/kg", "G(g) = peso × meta_gordura_g/kg",
    -- "C(kcal) = energia-alvo − proteína(kcal) − gordura(kcal)".
    v_macro002_proteina_g := round(v_peso_kg * v_macro002_proteina_g_por_kg, 1);
    v_macro002_gordura_g := round(v_peso_kg * v_macro002_gordura_g_por_kg, 1);
    v_macro002_proteina_kcal := v_macro002_proteina_g * 4;
    v_macro002_gordura_kcal := v_macro002_gordura_g * 9;
    v_macro002_carboidrato_kcal := v_energia_recomendacao_media - v_macro002_proteina_kcal - v_macro002_gordura_kcal;
    v_macro002_carboidrato_g := round(v_macro002_carboidrato_kcal / 4, 1);
    -- "O sistema deverá validar se o resultado é matematicamente
    -- possível" (Seção 5) — carboidrato residual não pode ser negativo;
    -- por construção (carboidrato = residual), a soma já bate exato, a
    -- validação aqui é sobre o resultado ser fisiologicamente possível,
    -- não sobre a soma (que é garantida pela própria fórmula).
    v_macro002_valido := v_macro002_carboidrato_kcal >= 0;
    if not v_macro002_valido then
      v_avisos := array_append(v_avisos, 'macro_002_carboidrato_negativo_energia_alvo_insuficiente');
    end if;
  end if;

  return jsonb_build_object(
    'motor_versao', 'v1',
    'formula_tmb', jsonb_build_object(
      'codigo', 'TMB-001',
      'nome', 'Mifflin-St Jeor',
      'versao', '1.0'
    ),
    'estrategia_tdee', v_estrategia_geral,
    'parametros', jsonb_build_object('pal_padrao', v_pal_padrao, 'pal_versao', v_pal_versao, 'tef_percentual', 0.10),
    'tmb', v_tmb,
    'tef_estimado', round(v_tef, 1),
    'tdee_por_dia', v_detalhe,
    'tdee_medio', v_tdee_medio,
    'qualidade', jsonb_build_object('score', v_score_qualidade, 'motivos', to_jsonb(v_motivos_qualidade)),
    'energia_recomendacao', case when v_estrategia_energetica is null then null else jsonb_build_object(
      'estrategia', v_estrategia_energetica,
      'deficit_percentual', v_deficit_aplicado,
      'deficit_versao', case when v_estrategia_energetica = 'deficit_conservador' then v_deficit_versao else null end,
      'recomendacao_media_diaria', v_energia_recomendacao_media
    ) end,
    'macros_recomendados', case when v_energia_recomendacao_media is null or v_peso_kg is null then null else jsonb_build_object(
      'energia_alvo', v_energia_recomendacao_media,
      'protocolo_principal', 'MACRO-002',
      'macro_001', jsonb_build_object(
        'versao', v_macro001_versao,
        'parametros', jsonb_build_object(
          'percentual_proteina', v_macro001_pct_proteina,
          'percentual_carboidrato', v_macro001_pct_carboidrato,
          'percentual_gordura', v_macro001_pct_gordura
        ),
        'proteina_g', v_macro001_proteina_g,
        'carboidrato_g', v_macro001_carboidrato_g,
        'gordura_g', v_macro001_gordura_g,
        'validacao_soma_ok', v_macro001_valido
      ),
      'macro_002', jsonb_build_object(
        'versao', v_macro002_versao,
        'parametros', jsonb_build_object(
          'proteina_g_por_kg', v_macro002_proteina_g_por_kg,
          'gordura_g_por_kg', v_macro002_gordura_g_por_kg
        ),
        'proteina_g', v_macro002_proteina_g,
        'carboidrato_g', v_macro002_carboidrato_g,
        'gordura_g', v_macro002_gordura_g,
        'validacao_soma_ok', v_macro002_valido
      )
    ) end,
    'insumos', jsonb_build_object(
      'idade', v_idade,
      'sexo_biologico', v_sexo,
      'altura_cm', v_altura_cm,
      'peso_kg', v_peso_kg,
      'peso_data_medicao', v_peso_data_medicao,
      'anamnese_id', v_anamnese_id,
      'objetivo_codigo', v_objetivo_codigo,
      'massa_magra_kg', v_massa_magra_kg,
      'percentual_gordura', v_percentual_gordura
    ),
    'avisos', to_jsonb(v_avisos),
    'calculado_em', now()
  );
end;
$$;

comment on function public.calcular_motor_metabolico_v1(uuid) is
  'RELATÓRIO 20260916_0001 (V1 original) + RELATÓRIO 20260919_0001 (macros MACRO-001/002, score de qualidade, recomendação energética — gap real da tarefa anterior, corrigido após leitura completa do documento). Função PURA (ME-005/006, nenhum insert/update/delete) — "recomendação" e "macros" são informativos, nunca a meta salva.';

revoke execute on function public.calcular_motor_metabolico_v1(uuid) from public;
grant execute on function public.calcular_motor_metabolico_v1(uuid) to authenticated;
