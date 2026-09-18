-- RELATÓRIO 20260920_0001 — fecha os 3 gaps deixados explicitamente "fora
-- do escopo" no relatório anterior (20260919_0001) e documentados como
-- pendência em AdminComplianceAnamnese.tsx (Blocos 13/Meta Energética):
--
-- 1. MACRO-003/MACRO-004/MACRO-005 — os 3 protocolos de macronutrientes
--    que faltavam do catálogo de 5 da seção "Motor Metabólico — Protocolos
--    de Macronutrientes V1.0".
-- 2. Tabela de déficit multicritério real (DEFICIT-002-multicriterio-v1),
--    substituindo o parâmetro único fixo (DEFICIT-001-conservador-v1, 15%
--    fixo) pela tabela pedida pela Seção 5 daquele bloco, considerando os
--    6 fatores mínimos exigidos: objetivo; peso; TDEE; nível de atividade;
--    presença de condições relevantes; disponibilidade/qualidade dos
--    dados. O documento não define os números da tabela (só exige que
--    ela exista, considere os 6 fatores e seja "versionada e passível de
--    atualização") — os parâmetros abaixo são a primeira versão dessa
--    tabela, documentados e isolados em constantes nomeadas.
--
-- `calcular_motor_metabolico_v1` continua PURA (ME-005/ME-006: nenhum
-- insert/update/delete) — tudo aqui é ainda "recomendação do sistema",
-- nunca a meta salva (isso só acontece via validar_e_salvar_meta, mediante
-- ação explícita do usuário/profissional).
--
-- ============================================================================
-- Tabela de déficit multicritério (DEFICIT-002-multicriterio-v1)
-- ============================================================================
-- Substitui o DEFICIT-001-conservador-v1 (15% fixo). Fatores considerados,
-- cada um isolado e documentado:
--
-- 1. Nível de atividade (Seção 5/Bloco 6, campo `anamneses.rotina_diaria`,
--    autorrelato, 5 níveis) — define o percentual BASE. Quanto mais
--    sedentária a rotina, maior o percentual base (mais "gordura" de TDEE
--    pra cortar com segurança); quanto mais intensa, menor o percentual
--    base (protege desempenho/energia disponível, coerente com a Seção 8
--    do mesmo bloco sobre não aplicar déficit agressivo em quem treina
--    pesado).
-- 2. TDEE (`tdee_medio`) — ajuste em pontos percentuais por faixa
--    absoluta: TDEE baixo fica mais conservador (percentual menor, pra não
--    aproximar demais da TMB); TDEE alto pode sustentar um percentual
--    levemente maior.
-- 3. Presença de condições relevantes (`anamneses.possui_condicao_saude`)
--    — reduz o percentual (mais conservador) quando o usuário reporta
--    alguma condição de saúde, na ausência de avaliação profissional.
-- 4. Disponibilidade/qualidade dos dados (`qualidade.score`, calculado
--    acima) — reduz o percentual quando a qualidade é "média" (fallback
--    de PAL ou sem composição corporal confirmada); "baixa" nunca chega
--    aqui (TMB nulo já bloqueia toda a recomendação energética).
-- 5. Peso (`peso_kg`) — não entra como ajuste percentual, e sim como TETO
--    ABSOLUTO do déficit em kcal/dia (10 kcal por kg de peso corporal),
--    um limite de segurança independente do TDEE.
-- 6. Objetivo (`objetivo_codigo`) — já é o que decide SE este ramo roda
--    (perder_peso/reduzir_gordura_corporal), inalterado desta migration.
--
-- O percentual final (após os ajustes 1-4) é limitado a [5%, 20%]; o
-- déficit em kcal (TDEE × percentual) é limitado pelo teto de peso (5); e
-- a recomendação final nunca fica abaixo da TMB calculada (mesmo piso já
-- aplicado pela trava clínica de N08_TRAVA_CLINICA em
-- validar_e_salvar_meta — este informativo nunca sugere algo que a trava
-- de gravação rejeitaria).
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
  v_rotina_diaria text;
  v_possui_condicao_saude boolean;
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
  -- SISTEMA (nunca a meta salva — ME-003/ME-005/ME-006).
  v_deficit_versao constant text := 'DEFICIT-002-multicriterio-v1';
  v_estrategia_energetica text;
  v_deficit_aplicado numeric;
  v_energia_recomendacao_media numeric;

  -- Fatores da tabela multicritério (RELATÓRIO 20260920_0001).
  v_deficit_base numeric;
  v_deficit_ajuste_tdee numeric;
  v_deficit_ajuste_condicao numeric;
  v_deficit_ajuste_qualidade numeric;
  v_deficit_percentual_bruto numeric;
  v_deficit_percentual_limitado numeric;
  v_deficit_kcal_bruto numeric;
  v_deficit_teto_peso_kcal numeric;
  v_deficit_kcal_aplicado numeric;
  v_deficit_piso_tmb_acionado boolean;
  v_deficit_percentual_efetivo numeric;
  v_deficit_percentual_min constant numeric := 0.05;
  v_deficit_percentual_max constant numeric := 0.20;
  v_deficit_teto_kcal_por_kg constant numeric := 10;

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

  -- MACRO-003 — Seção 6: proteína por MLG (massa livre de gordura, aqui
  -- `anamneses.massa_magra_kg`) + gordura g/kg de peso + carboidrato
  -- residual. "Exige validação se a MLG está disponível" — só calculado
  -- quando `massa_magra_kg` não é nulo; senão o bloco fica `null` e um
  -- aviso explícito é adicionado.
  v_macro003_proteina_g_por_kg_mlg constant numeric := 2.0;
  v_macro003_gordura_g_por_kg constant numeric := 0.8;
  v_macro003_versao constant text := 'MACRO-003-default-v1';
  v_macro003_proteina_g numeric;
  v_macro003_proteina_kcal numeric;
  v_macro003_gordura_g numeric;
  v_macro003_gordura_kcal numeric;
  v_macro003_carboidrato_kcal numeric;
  v_macro003_carboidrato_g numeric;
  v_macro003_valido boolean;
  v_macro003_disponivel boolean;

  -- MACRO-004 — Seção 7: proteína prioritária (g/kg, parâmetro próprio,
  -- mais alto que MACRO-002 pra diferenciar "prioridade") + limite/
  -- parâmetro de gordura (percentual MÍNIMO da energia-alvo, fixo) +
  -- carboidrato variável (absorve toda a energia restante).
  v_macro004_proteina_g_por_kg constant numeric := 1.8;
  v_macro004_gordura_pct_minimo constant numeric := 0.25;
  v_macro004_versao constant text := 'MACRO-004-default-v1';
  v_macro004_proteina_g numeric;
  v_macro004_proteina_kcal numeric;
  v_macro004_gordura_g numeric;
  v_macro004_gordura_kcal numeric;
  v_macro004_carboidrato_kcal numeric;
  v_macro004_carboidrato_g numeric;
  v_macro004_valido boolean;

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

  -- SSOT: peso/altura/objetivo/composição corporal/rotina/condições vêm
  -- da ÚLTIMA ANAMNESE VÁLIDA (mais recente com peso+altura preenchidos).
  -- `rotina_diaria` e `possui_condicao_saude` passam a alimentar a nova
  -- tabela de déficit multicritério (RELATÓRIO 20260920_0001) — antes só
  -- eram registrados, não usados pelo Motor.
  select a.peso_kg, a.altura_cm, a.id, a.peso_data_medicao, a.objetivo_codigo, a.massa_magra_kg, a.percentual_gordura, a.rotina_diaria, a.possui_condicao_saude
  into v_peso_kg, v_altura_cm, v_anamnese_id, v_peso_data_medicao, v_objetivo_codigo, v_massa_magra_kg, v_percentual_gordura, v_rotina_diaria, v_possui_condicao_saude
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
  -- bloco), inalterado desta migration.
  -- ==========================================================================
  if v_tdee_medio is not null and v_objetivo_codigo is not null then
    if v_objetivo_codigo = 'manter_peso' then
      v_estrategia_energetica := 'manutencao';
      v_energia_recomendacao_media := v_tdee_medio;
    elsif v_objetivo_codigo in ('perder_peso', 'reduzir_gordura_corporal') then
      v_estrategia_energetica := 'deficit_conservador';

      -- Fator 1: nível de atividade (`rotina_diaria`) → percentual base.
      if v_rotina_diaria is null then
        v_deficit_base := 0.15;
        v_avisos := array_append(v_avisos, 'deficit_sem_rotina_diaria_usando_padrao_moderado');
      else
        v_deficit_base := case v_rotina_diaria
          when 'predominantemente_sentado' then 0.20
          when 'pouco_ativo' then 0.18
          when 'moderadamente_ativo' then 0.15
          when 'muito_ativo' then 0.12
          when 'trabalho_fisicamente_intenso' then 0.10
          else 0.15
        end;
      end if;

      -- Fator 2: TDEE médio (faixa absoluta) → ajuste em pontos percentuais.
      v_deficit_ajuste_tdee := case
        when v_tdee_medio < 1800 then -0.03
        when v_tdee_medio >= 2600 then 0.02
        else 0
      end;

      -- Fator 3: presença de condições relevantes → mais conservador.
      v_deficit_ajuste_condicao := case when v_possui_condicao_saude then -0.05 else 0 end;

      -- Fator 4: qualidade dos dados → mais conservador quando "média"
      -- ("baixa" nunca chega aqui, pois bloqueia o TMB acima).
      v_deficit_ajuste_qualidade := case when v_score_qualidade = 'media' then -0.03 else 0 end;

      v_deficit_percentual_bruto := v_deficit_base + v_deficit_ajuste_tdee + v_deficit_ajuste_condicao + v_deficit_ajuste_qualidade;
      v_deficit_percentual_limitado := least(greatest(v_deficit_percentual_bruto, v_deficit_percentual_min), v_deficit_percentual_max);

      -- Fator 5: peso → teto absoluto do déficit em kcal/dia (independe
      -- do percentual calculado acima).
      v_deficit_kcal_bruto := v_tdee_medio * v_deficit_percentual_limitado;
      v_deficit_teto_peso_kcal := v_peso_kg * v_deficit_teto_kcal_por_kg;
      v_deficit_kcal_aplicado := least(v_deficit_kcal_bruto, v_deficit_teto_peso_kcal);

      -- Piso de segurança: a recomendação nunca fica abaixo da TMB (mesmo
      -- piso já aplicado pela trava clínica em validar_e_salvar_meta).
      v_energia_recomendacao_media := round(greatest(v_tdee_medio - v_deficit_kcal_aplicado, v_tmb), 1);
      v_deficit_piso_tmb_acionado := (v_tdee_medio - v_deficit_kcal_aplicado) < v_tmb;
      v_deficit_percentual_efetivo := round((v_tdee_medio - v_energia_recomendacao_media) / v_tdee_medio, 4);
      v_deficit_aplicado := v_deficit_percentual_efetivo;

      if v_deficit_piso_tmb_acionado then
        v_avisos := array_append(v_avisos, 'deficit_limitado_pelo_piso_da_tmb');
      end if;
    else
      v_avisos := array_append(v_avisos, 'objetivo_sem_estrategia_energetica_automatica_v1');
    end if;
  elsif v_objetivo_codigo is null then
    v_avisos := array_append(v_avisos, 'sem_objetivo_para_recomendacao_energetica');
  end if;

  -- ==========================================================================
  -- "Protocolos de Macronutrientes V1.0" — só calculados quando há
  -- energia-alvo (recomendação acima) E peso (pré-requisito de todos os
  -- protocolos 001-004).
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
    v_macro002_valido := v_macro002_carboidrato_kcal >= 0;
    if not v_macro002_valido then
      v_avisos := array_append(v_avisos, 'macro_002_carboidrato_negativo_energia_alvo_insuficiente');
    end if;

    -- MACRO-003 — Seção 6: proteína por MLG (`massa_magra_kg`) + gordura
    -- g/kg de peso + carboidrato residual. "A fonte e a data da MLG
    -- deverão ser preservadas" — devolvidas junto (mesma
    -- `peso_data_medicao` da anamnese, única data de composição corporal
    -- disponível no schema atual).
    v_macro003_disponivel := v_massa_magra_kg is not null;
    if v_macro003_disponivel then
      v_macro003_proteina_g := round(v_massa_magra_kg * v_macro003_proteina_g_por_kg_mlg, 1);
      v_macro003_gordura_g := round(v_peso_kg * v_macro003_gordura_g_por_kg, 1);
      v_macro003_proteina_kcal := v_macro003_proteina_g * 4;
      v_macro003_gordura_kcal := v_macro003_gordura_g * 9;
      v_macro003_carboidrato_kcal := v_energia_recomendacao_media - v_macro003_proteina_kcal - v_macro003_gordura_kcal;
      v_macro003_carboidrato_g := round(v_macro003_carboidrato_kcal / 4, 1);
      v_macro003_valido := v_macro003_carboidrato_kcal >= 0;
      if not v_macro003_valido then
        v_avisos := array_append(v_avisos, 'macro_003_carboidrato_negativo_energia_alvo_insuficiente');
      end if;
    else
      v_avisos := array_append(v_avisos, 'macro_003_sem_massa_magra_kg_disponivel');
    end if;

    -- MACRO-004 — Seção 7: proteína prioritária (g/kg, parâmetro próprio) +
    -- limite/parâmetro de gordura (percentual mínimo fixo da energia-alvo)
    -- + carboidrato variável (absorve a energia restante).
    v_macro004_proteina_g := round(v_peso_kg * v_macro004_proteina_g_por_kg, 1);
    v_macro004_proteina_kcal := v_macro004_proteina_g * 4;
    v_macro004_gordura_kcal := v_energia_recomendacao_media * v_macro004_gordura_pct_minimo;
    v_macro004_gordura_g := round(v_macro004_gordura_kcal / 9, 1);
    v_macro004_carboidrato_kcal := v_energia_recomendacao_media - v_macro004_proteina_kcal - v_macro004_gordura_g * 9;
    v_macro004_carboidrato_g := round(v_macro004_carboidrato_kcal / 4, 1);
    v_macro004_valido := v_macro004_carboidrato_kcal >= 0;
    if not v_macro004_valido then
      v_avisos := array_append(v_avisos, 'macro_004_carboidrato_negativo_energia_alvo_insuficiente');
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
      'recomendacao_media_diaria', v_energia_recomendacao_media,
      'fatores_considerados', case when v_estrategia_energetica = 'deficit_conservador' then jsonb_build_object(
        'nivel_atividade', coalesce(v_rotina_diaria, 'nao_informado'),
        'deficit_base_percentual', v_deficit_base,
        'ajuste_tdee_percentual', v_deficit_ajuste_tdee,
        'ajuste_condicao_relevante_percentual', v_deficit_ajuste_condicao,
        'ajuste_qualidade_dados_percentual', v_deficit_ajuste_qualidade,
        'percentual_antes_dos_limites', round(v_deficit_percentual_bruto, 4),
        'percentual_apos_limites_5_a_20', v_deficit_percentual_limitado,
        'teto_deficit_kcal_por_peso', v_deficit_teto_peso_kcal,
        'deficit_kcal_aplicado', round(v_tdee_medio - v_energia_recomendacao_media, 1),
        'piso_tmb_acionado', v_deficit_piso_tmb_acionado
      ) else null end
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
      ),
      'macro_003', jsonb_build_object(
        'versao', v_macro003_versao,
        'disponivel', v_macro003_disponivel,
        'parametros', jsonb_build_object(
          'proteina_g_por_kg_mlg', v_macro003_proteina_g_por_kg_mlg,
          'gordura_g_por_kg_peso', v_macro003_gordura_g_por_kg
        ),
        'massa_magra_kg', v_massa_magra_kg,
        'massa_magra_data_medicao', v_peso_data_medicao,
        'proteina_g', v_macro003_proteina_g,
        'carboidrato_g', v_macro003_carboidrato_g,
        'gordura_g', v_macro003_gordura_g,
        'validacao_soma_ok', v_macro003_valido
      ),
      'macro_004', jsonb_build_object(
        'versao', v_macro004_versao,
        'parametros', jsonb_build_object(
          'proteina_g_por_kg', v_macro004_proteina_g_por_kg,
          'gordura_percentual_minimo', v_macro004_gordura_pct_minimo
        ),
        'proteina_g', v_macro004_proteina_g,
        'carboidrato_g', v_macro004_carboidrato_g,
        'gordura_g', v_macro004_gordura_g,
        'validacao_soma_ok', v_macro004_valido
      ),
      'macro_005', jsonb_build_object(
        'versao', 'MACRO-005-personalizado-v1',
        'disponivel', true,
        'calculo_automatico', false,
        'motivo', 'personalizado_pelo_profissional_use_validar_macro_personalizado'
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
      'percentual_gordura', v_percentual_gordura,
      'rotina_diaria', v_rotina_diaria,
      'possui_condicao_saude', v_possui_condicao_saude
    ),
    'avisos', to_jsonb(v_avisos),
    'calculado_em', now()
  );
end;
$$;

comment on function public.calcular_motor_metabolico_v1(uuid) is
  'RELATÓRIO 20260916_0001 (V1 original) + 20260919_0001 (macros 001/002, qualidade, recomendação energética) + 20260920_0001 (MACRO-003/004/005, tabela de déficit multicritério DEFICIT-002-multicriterio-v1). Função PURA (ME-005/006, nenhum insert/update/delete) — "recomendação" e "macros" são informativos, nunca a meta salva.';

revoke execute on function public.calcular_motor_metabolico_v1(uuid) from public;
grant execute on function public.calcular_motor_metabolico_v1(uuid) to authenticated;

-- ============================================================================
-- MACRO-005 — Seção 8: "personalizado pelo profissional". Por definição
-- não é calculado automaticamente (o profissional define os valores
-- diretamente); a exigência do documento pra este protocolo é "o sistema
-- deverá validar a consistência matemática dos valores" — é isso que esta
-- função pura faz, isolada e reutilizável por quem for chamá-la (painel
-- do profissional, futuramente) antes de repassar os valores pra
-- validar_e_salvar_meta. Não grava nada.
-- ============================================================================
create or replace function public.validar_macro_personalizado(
  p_energia_alvo_kcal numeric,
  p_proteina_g numeric,
  p_carboidrato_g numeric,
  p_gordura_g numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tolerancia_kcal constant numeric := 2;
  v_soma_kcal numeric;
  v_diferenca numeric;
  v_valido boolean;
begin
  if p_energia_alvo_kcal is null or p_proteina_g is null or p_carboidrato_g is null or p_gordura_g is null then
    raise exception 'MACRO-005 exige energia-alvo, proteína, carboidrato e gordura preenchidos.';
  end if;
  if p_proteina_g < 0 or p_carboidrato_g < 0 or p_gordura_g < 0 or p_energia_alvo_kcal <= 0 then
    raise exception 'MACRO-005: valores devem ser não negativos e a energia-alvo maior que zero.';
  end if;

  v_soma_kcal := (p_proteina_g * 4) + (p_carboidrato_g * 4) + (p_gordura_g * 9);
  v_diferenca := v_soma_kcal - p_energia_alvo_kcal;
  v_valido := abs(v_diferenca) <= v_tolerancia_kcal;

  return jsonb_build_object(
    'versao', 'MACRO-005-personalizado-v1',
    'energia_alvo_kcal', p_energia_alvo_kcal,
    'soma_kcal_calculada', v_soma_kcal,
    'diferenca_kcal', v_diferenca,
    'tolerancia_kcal', v_tolerancia_kcal,
    'valido', v_valido
  );
end;
$$;

comment on function public.validar_macro_personalizado(numeric, numeric, numeric, numeric) is
  'RELATÓRIO 20260920_0001 — MACRO-005 ("personalizado pelo profissional", Seção 8 de "Protocolos de Macronutrientes V1.0"). Função PURA de validação matemática (kcal proteína + kcal carboidrato + kcal gordura = energia-alvo, Seção 16); não grava nada e não substitui validar_e_salvar_meta.';

revoke execute on function public.validar_macro_personalizado(numeric, numeric, numeric, numeric) from public;
grant execute on function public.validar_macro_personalizado(numeric, numeric, numeric, numeric) to authenticated;
