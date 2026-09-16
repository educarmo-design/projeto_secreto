-- Motor Metabólico V1 + SSOT peso/altura (RELATÓRIO 20260916_0001) — pedido
-- explícito do fundador em docs/motor_metabolico.txt: "O peso não deve ser
-- mantido como atributo permanente do perfil" / "A altura deverá ser
-- confirmada em toda nova Anamnese" (Seção 1/2, "Eu considero estas decisões
-- fechadas" itens 1-3).

-- ============================================================================
-- Parte 1 — peso/altura viram snapshot da Anamnese, não mais do perfil
-- ============================================================================
-- Cada preenchimento de anamnese passa a carregar SEU PRÓPRIO peso/altura
-- (nunca sobrescrito por um preenchimento futuro, mesmo princípio de
-- `anamneses_trg_versionar`: a versão anterior nunca é editada). Nullable
-- porque anamneses já existentes no banco (antes desta migration) não têm
-- esse dado — "última anamnese válida" (usada pelo Motor e pelo Flutter) é
-- definida como a mais recente COM peso_kg/altura_cm preenchidos, não
-- necessariamente a `status_vigencia = 'ativo'`.
alter table anamneses
  add column if not exists peso_kg numeric(5, 2),
  add column if not exists altura_cm numeric(5, 1),
  add column if not exists peso_data_medicao date,
  add column if not exists peso_origem text;

comment on column anamneses.peso_kg is
  'RELATÓRIO 20260916_0001 — peso OFICIAL desta versão da anamnese (SSOT). Substitui perfis_usuarios.peso_kg (removida nesta mesma migration) como fonte do Motor Metabólico. Uma leitura de balança/wearable é só SUGESTÃO até o usuário confirmar no formulário de Anamnese — aí vira este valor.';
comment on column anamneses.altura_cm is
  'RELATÓRIO 20260916_0001 — altura OFICIAL desta versão da anamnese (SSOT), reconfirmada a cada preenchimento (nunca copiada silenciosamente da anamnese anterior — a UI mostra o valor anterior como sugestão editável). Substitui perfis_usuarios.altura_cm (removida nesta mesma migration).';
comment on column anamneses.peso_data_medicao is
  'Data em que o peso registrado nesta anamnese foi efetivamente medido (pode ser hoje, ou a data de uma leitura de balança/wearable confirmada pelo usuário) — distinta de anamneses.data_preenchimento.';
comment on column anamneses.peso_origem is
  'De onde veio o peso confirmado: ''usuario'' (digitado na hora), ''wearable''/''balanca'' (sugestão de metricas_saude_diarias aceita sem alteração), etc. Nullable para anamneses antigas sem esse rastro.';

-- ============================================================================
-- Parte 2 — remove peso/altura como atributo permanente de perfis_usuarios
-- ============================================================================
-- Ambas as colunas têm consumidores reais que dependiam de lê-las direto de
-- perfis_usuarios — corrigidos ABAIXO (Parte 3) antes deste DROP, na mesma
-- migration/transação, para nunca existir uma janela de "coluna já sumiu,
-- função ainda não corrigida".
alter table perfis_usuarios
  drop column if exists peso_kg,
  drop column if exists altura_cm;

-- ============================================================================
-- Parte 3 — corrige o consumidor legado (calcular_motor_metabolico) para não
-- quebrar com o DROP acima — contrato de saída (nomes de campo do jsonb)
-- 100% preservado, só a ORIGEM de altura_cm muda (de perfis_usuarios para a
-- última anamnese com dado). peso_kg deste RPC já vinha de
-- metricas_saude_diarias (não de perfis_usuarios) — não precisou mudar.
-- Mantido vivo de propósito (Restrição da tarefa "não quebrar legados"): tem
-- 3 consumidores reais em produção (validar_e_salvar_meta,
-- meta_bem_estar_repository.dart no Flutter, MotorMetabolicoCard.tsx/
-- InserirMedicaoModal.tsx no Painel Web) que não são tocados nesta tarefa.
create or replace function public.calcular_motor_metabolico(p_usuario_id uuid)
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
  v_massa_magra_kg numeric;
  v_anamnese_id uuid;
  v_tmb numeric;
  v_formula text;
  v_gasto_sedentario numeric;
  v_gasto_atividade numeric;
  v_tef numeric;
  v_tdee numeric;
  v_avisos text[] := '{}';
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

  -- RELATÓRIO 20260916_0001 — SSOT: altura não é mais lida de
  -- perfis_usuarios.altura_cm (coluna removida acima), e sim da última
  -- anamnese do usuário que tem o campo preenchido, de QUALQUER
  -- status_vigencia (mesmo espírito de "última anamnese válida" do resto
  -- desta tarefa).
  select a.altura_cm into v_altura_cm
  from public.anamneses a
  where a.usuario_id = p_usuario_id and a.altura_cm is not null
  order by a.data_preenchimento desc
  limit 1;

  -- Última leitura VÁLIDA (não-nula) de cada métrica — podem vir de dias
  -- diferentes (ex.: peso sincroniza todo dia pela balança, massa magra só
  -- quando a balança de bioimpedância mede). Inalterado por esta tarefa.
  select m.peso_kg into v_peso_kg
  from public.metricas_saude_diarias m
  where m.usuario_id_anonimo = p_usuario_id and m.peso_kg is not null
  order by m.data_referencia desc
  limit 1;

  select m.massa_magra_kg into v_massa_magra_kg
  from public.metricas_saude_diarias m
  where m.usuario_id_anonimo = p_usuario_id and m.massa_magra_kg is not null
  order by m.data_referencia desc
  limit 1;

  -- TMB
  if v_massa_magra_kg is not null then
    v_tmb := 370 + (21.6 * v_massa_magra_kg);
    v_formula := 'katch_mcardle';
  elsif v_peso_kg is not null and v_idade is not null and v_sexo is not null and v_altura_cm is not null then
    v_tmb := (10 * v_peso_kg) + (6.25 * v_altura_cm) - (5 * v_idade)
             + (case v_sexo when 'M' then 5 else -161 end);
    v_formula := 'mifflin_st_jeor';
  else
    v_tmb := null;
    v_formula := 'dados_insuficientes';
    if v_massa_magra_kg is null then v_avisos := array_append(v_avisos, 'sem_massa_magra'); end if;
    if v_peso_kg is null then v_avisos := array_append(v_avisos, 'sem_peso'); end if;
    if v_idade is null then v_avisos := array_append(v_avisos, 'sem_data_nascimento'); end if;
    if v_sexo is null then v_avisos := array_append(v_avisos, 'sem_sexo_biologico'); end if;
    if v_altura_cm is null then v_avisos := array_append(v_avisos, 'sem_altura'); end if;
  end if;

  v_gasto_sedentario := case when v_tmb is not null then v_tmb * 1.2 else null end;
  v_tef := case when v_tmb is not null then v_tmb * 0.10 else null end;

  select id into v_anamnese_id
  from public.anamneses
  where usuario_id = p_usuario_id and status_vigencia = 'ativo'
  limit 1;

  if v_peso_kg is null then
    v_gasto_atividade := null;
    v_avisos := array_append(v_avisos, 'sem_peso_para_gasto_atividade');
  elsif v_anamnese_id is null then
    v_gasto_atividade := 0;
    v_avisos := array_append(v_avisos, 'sem_anamnese_ativa');
  else
    select coalesce(sum(coalesce(t.met_estimado, 0) * v_peso_kg * (aa.minutos_diarios / 60.0)), 0)
    into v_gasto_atividade
    from public.anamneses_atividades aa
    join public.tipos_atividades_fisicas t on t.id = aa.atividade_id
    where aa.anamnese_id = v_anamnese_id;
  end if;

  v_tdee := case
    when v_gasto_sedentario is not null and v_gasto_atividade is not null
    then v_gasto_sedentario + v_gasto_atividade
    else null
  end;

  return jsonb_build_object(
    'tmb', v_tmb,
    'gasto_sedentario', v_gasto_sedentario,
    'gasto_atividade', v_gasto_atividade,
    'tef', v_tef,
    'tdee', v_tdee,
    'formula_usada', v_formula,
    'insumos', jsonb_build_object(
      'idade', v_idade,
      'sexo_biologico', v_sexo,
      'altura_cm', v_altura_cm,
      'peso_kg', v_peso_kg,
      'massa_magra_kg', v_massa_magra_kg
    ),
    'avisos', to_jsonb(v_avisos)
  );
end;
$$;

comment on function public.calcular_motor_metabolico(uuid) is
  'N07 (RELATÓRIO 20260812_0008). RELATÓRIO 20260916_0001: altura_cm passou a vir da última anamnese com o campo preenchido (SSOT), não mais de perfis_usuarios (coluna removida) — contrato de saída (nomes de campo) 100% preservado. Mantida viva por ter 3 consumidores reais em produção; ver calcular_motor_metabolico_v1 para o motor centralizado novo (TMB-001 + TDEE por dia da semana + rastreabilidade de fórmula/versão, docs/motor_metabolico.txt).';

-- ============================================================================
-- Parte 4 — Motor Metabólico Centralizado V1 (novo, aditivo)
-- ============================================================================
-- Implementa docs/motor_metabolico.txt: TMB-001 (Mifflin-St Jeor) como base;
-- TDEE por dia da semana via Decomposição (TMB + EAT + TEF) quando a
-- anamnese ativa tem rotina detalhada por dia (anamneses_atividades_dias)
-- para aquele dia específico, senão PAL (TMB × PAL padrão) — nunca as duas
-- estratégias somadas no mesmo dia (Seção "Regra fundamental de cálculo":
-- "não deverá combinar parcialmente os dois métodos... evitando dupla
-- contagem"). Registra fórmula/versão/parâmetros/estratégia no próprio JSON
-- de saída (Seção "Armazenamento do resultado").
--
-- GAP CONHECIDO, documentado de propósito (não escondido): a Seção "5. NEAT"
-- do documento pede que o NEAT (atividade não-exercício) seja estimado com
-- prioridade "smartwatch > passos > atividades manuais > rotina ocupacional
-- informada na anamnese" — este app ainda não coleta o campo "Rotina diária"
-- (sedentário/pouco ativo/.../trabalho intenso) descrito na Seção 5 do
-- Anamnese V1.0 do mesmo documento, então NEAT nunca é estimável
-- individualmente hoje. Seguindo a própria regra do documento ("quando não
-- houver dados suficientes para estimar o NEAT... não deverá inventar um
-- valor numérico... deverá utilizar o PAL"), a "Decomposição" desta V1 é
-- TMB + EAT + TEF (sem termo de NEAT separado, que ficaria zerado/inventado)
-- — mais fiel ao documento do que fingir ter um NEAT que não existe.
-- Registrado como backlog explícito no RELATÓRIO desta tarefa.
--
-- APENAS calcula e retorna (ME-005/ME-006/ACEITE da tarefa): nunca escreve
-- em objetivos_alimentares, sugestao_meta ou anamneses — não chama
-- validar_e_salvar_meta nem gerar_sugestao_meta. Não substitui nenhum
-- consumidor existente nesta tarefa (Motor Metabólico Centralizado é
-- trabalho de backend puro, ARQUIVOS desta tarefa não pede nenhuma tela
-- Flutter/Web nova consumindo-a ainda — "as metas serão inseridas... em uma
-- etapa futura").
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
  v_tmb numeric;
  v_tef numeric;
  v_avisos text[] := '{}';
  -- PAL padrão sedentário V1 — parâmetro único e versionado (Seção "8. PAL
  -- como fallback": "deverá ser um parâmetro versionado da biblioteca").
  -- Mesmo valor já estabelecido em calcular_motor_metabolico (gasto_
  -- sedentario = TMB × 1.2), reaproveitado aqui por continuidade — uma
  -- tabela de PAL por nível de atividade auto-relatado fica pro backlog
  -- (depende do campo "Rotina diária" ainda não coletado, ver comentário
  -- da função).
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
begin
  -- Mesmo guard de acesso de calcular_motor_metabolico/gerar_sugestao_meta.
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

  -- SSOT: peso/altura vêm da ÚLTIMA ANAMNESE VÁLIDA (mais recente com os
  -- dois campos preenchidos), nunca de perfis_usuarios (peso nunca esteve
  -- lá pro motor; altura foi removida de lá nesta mesma migration) nem de
  -- metricas_saude_diarias direto (aquilo é só "sugestão" até confirmado
  -- numa anamnese, docs/motor_metabolico.txt Seção 1).
  select a.peso_kg, a.altura_cm, a.id, a.peso_data_medicao
  into v_peso_kg, v_altura_cm, v_anamnese_id, v_peso_data_medicao
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

  -- TMB-001 — Mifflin-St Jeor (única fórmula da V1; TMB-002/003 exigem
  -- massa livre de gordura confiável — fora do escopo desta tarefa, que
  -- pede explicitamente "TMB-001 como base").
  if v_idade is not null and v_sexo is not null and v_peso_kg is not null and v_altura_cm is not null then
    v_tmb := (10 * v_peso_kg) + (6.25 * v_altura_cm) - (5 * v_idade)
             + (case v_sexo when 'M' then 5 else -161 end);
  else
    v_tmb := null;
    v_avisos := array_append(v_avisos, 'tmb_nao_calculada_dados_insuficientes');
  end if;

  -- TEF — 10% da TMB, parametrizado (Seção 7). Só entra na soma do TDEE na
  -- estratégia de Decomposição (nunca na estratégia PAL — o PAL já
  -- representa o multiplicador do dia inteiro, somar TEF por cima duplicaria
  -- Seção 7: "não deverá aplicar simultaneamente TEF global... e [outro]").
  -- Sem arredondar aqui de propósito: `v_tef` alimenta a soma de
  -- `v_tdee_dia` abaixo, e arredondar ANTES de somar introduzia um desvio
  -- de ~0,05 kcal/dia no TDEE final (achado testando ao vivo contra
  -- atleta1000@teste.com) — arredondamento só na saída (`tef_estimado`).
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
        -- Sem atividade estruturada registrada NESTE dia: Seção "9. Não
        -- tratar ausência de atividade como atividade zero" — não assume
        -- EAT=0 e monta uma decomposição capenga; usa PAL como estratégia
        -- INTEIRA do dia (TMB × PAL), que já é uma estimativa completa de
        -- gasto total, não só do "resto" depois de somar EAT=0.
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

  -- Média só com os 7 dias completos (Seção 13 — não enviesar com dias
  -- faltantes apresentados como "a média da semana").
  v_tdee_medio := case when v_dias_com_tdee = 7 then round(v_soma_tdee / 7, 1) else null end;
  v_estrategia_geral := case when v_usa_decomposicao_anamnese then 'decomposicao_parcial' else 'pal' end;

  -- APENAS retorna — nenhum insert/update/delete nesta função (ME-005).
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
    'insumos', jsonb_build_object(
      'idade', v_idade,
      'sexo_biologico', v_sexo,
      'altura_cm', v_altura_cm,
      'peso_kg', v_peso_kg,
      'peso_data_medicao', v_peso_data_medicao,
      'anamnese_id', v_anamnese_id
    ),
    'avisos', to_jsonb(v_avisos),
    'calculado_em', now()
  );
end;
$$;

comment on function public.calcular_motor_metabolico_v1(uuid) is
  'RELATÓRIO 20260916_0001 — Motor Metabólico Centralizado V1 (docs/motor_metabolico.txt): TMB-001 (Mifflin-St Jeor) usando peso/altura da última anamnese válida (SSOT, nunca de perfis_usuarios/metricas_saude_diarias direto); TDEE por dia da semana via Decomposição (TMB+EAT+TEF) quando há anamneses_atividades_dias para aquele dia, senão PAL (TMB×PAL padrão, parâmetro versionado PAL-001); TDEE médio só com os 7 dias completos. Gap conhecido documentado no corpo da função: NEAT não é estimado (sem fonte de dado objetiva ainda). APENAS calcula e retorna (ME-005/ME-006) — nunca escreve em objetivos_alimentares/sugestao_meta/anamneses, nunca chama validar_e_salvar_meta. Ainda não consumida por nenhuma tela Flutter/Web (entrega desta tarefa é só o backend).';

revoke execute on function public.calcular_motor_metabolico_v1(uuid) from public;
grant execute on function public.calcular_motor_metabolico_v1(uuid) to authenticated;
