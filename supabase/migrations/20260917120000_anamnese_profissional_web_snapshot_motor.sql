-- Anamnese Profissional (Web B2B) + Fechamento do Gap Crítico de
-- Persistência do Snapshot do Motor (RELATÓRIO 20260917_0001,
-- docs/motor_metabolico.txt BLOCO 13: "Cada Anamnese deve armazenar uma
-- fotografia completa dos resultados calculados").

-- ============================================================================
-- Parte 1 — Anamnese: campos que faltavam pro fluxo profissional
-- ============================================================================
-- `objetivo_outro`: "Outros objetivos personalizados" (item 2 da tarefa) —
-- texto livre, preenchido quando `objetivo_codigo = 'outro'`.
-- `data_proxima_avaliacao`: só o profissional define isto (item 2 — "Sem
-- Trava de Tempo: o profissional... define a data da próxima avaliação
-- livremente"); NULL pra anamneses self-service, que continuam usando a
-- regra fixa de 30 dias calculada no cliente (Flutter), não uma coluna.
-- `resultado_motor_v1`/`resultado_motor_gravado_em`: o Gap Crítico em si —
-- ver Parte 3.
alter table anamneses
  add column if not exists objetivo_outro text,
  add column if not exists data_proxima_avaliacao timestamptz,
  add column if not exists resultado_motor_v1 jsonb,
  add column if not exists resultado_motor_gravado_em timestamptz;

comment on column anamneses.objetivo_outro is
  'RELATÓRIO 20260917_0001 — texto livre de "outros objetivos personalizados" (item 2 da tarefa), preenchido quando objetivo_codigo = ''outro''. NULL nos demais casos.';
comment on column anamneses.data_proxima_avaliacao is
  'RELATÓRIO 20260917_0001 — só preenchida por profissional (Anamnese Profissional, Painel Web): ele define livremente, sem a trava fixa de 30 dias do fluxo self-service (que calcula no cliente, não grava aqui).';
comment on column anamneses.resultado_motor_v1 is
  'RELATÓRIO 20260917_0001 (Gap Crítico, docs/motor_metabolico.txt BLOCO 13) — JSON EXATO devolvido por calcular_motor_metabolico_v1 no momento em que uma Meta foi salva para esta anamnese (self-service pelo App OU prescrição pelo profissional no Web) — ver validar_e_salvar_meta, Parte 3. NULL até a primeira meta ser salva para esta anamnese (a RPC do motor em si nunca escreve nada — é pura).';
comment on column anamneses.resultado_motor_gravado_em is
  'Quando o snapshot acima foi gravado — pode diferir de resultado_motor_v1->>''calculado_em'' (o timestamp do próprio cálculo) se o snapshot for atualizado por uma meta salva depois, sem que os insumos tenham mudado.';

-- `objetivo_codigo` ganha o 4º valor — precisa existir ANTES do objetivo
-- "outro" poder ser gravado pela RPC profissional (Parte 2).
alter table anamneses drop constraint if exists anamneses_objetivo_codigo_check;
alter table anamneses add constraint anamneses_objetivo_codigo_check
  check (objetivo_codigo in ('emagrecimento', 'manutencao', 'hipertrofia', 'outro'));

-- ============================================================================
-- Parte 2 — RPC profissional_salvar_anamnese (Anamnese Profissional, Web)
-- ============================================================================
-- `anamneses_insert_own` (RLS, `20260811240000`) só permite `usuario_id =
-- auth.uid()` — um profissional não pode inserir DIRETO uma anamnese em
-- nome do paciente. Mesmo padrão de `profissional_atualizar_sexo_biologico`
-- (`20260812100000`): RPC `security definer` com o vínculo checado à mão.
--
-- Sem trava de carência de 30 dias aqui de propósito (item 2 — "Sem Trava
-- de Tempo"): o profissional pode preencher quantas anamneses quiser,
-- quando quiser; `data_proxima_avaliacao` é só um campo informativo que ELE
-- escolhe, nunca uma regra que bloqueia o próximo preenchimento.
--
-- `sexo_biologico` continua fora do payload — já tem sua própria RPC
-- (`profissional_atualizar_sexo_biologico`), o client do Painel Web chama
-- as duas em sequência (mesmo dado, mora em tabelas diferentes: sexo em
-- `perfis_usuarios`, o resto aqui em `anamneses`).
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
  v_atividade jsonb;
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
    peso_kg, altura_cm, peso_data_medicao, peso_origem, data_proxima_avaliacao
  ) values (
    p_paciente_id,
    v_profissional_id,
    v_objetivo_codigo,
    nullif(p_payload->>'objetivo_outro', ''),
    nullif(p_payload->>'peso_kg', '')::numeric,
    nullif(p_payload->>'altura_cm', '')::numeric,
    current_date,
    'profissional',
    nullif(p_payload->>'data_proxima_avaliacao', '')::timestamptz
  )
  returning id into v_anamnese_id;

  for v_atividade in select * from jsonb_array_elements(v_atividades)
  loop
    insert into public.anamneses_atividades_dias (anamnese_id, atividade_id, dia_semana, minutos)
    values (
      v_anamnese_id,
      (v_atividade->>'atividade_id')::smallint,
      (v_atividade->>'dia_semana')::smallint,
      (v_atividade->>'minutos')::int
    );
  end loop;

  return jsonb_build_object('sucesso', true, 'anamnese_id', v_anamnese_id);
end;
$$;

comment on function public.profissional_salvar_anamnese(uuid, jsonb) is
  'RELATÓRIO 20260917_0001 (item 2) — Anamnese Profissional (Painel Web): profissional com vínculo ATIVO preenche uma anamnese nova pro paciente. SEM trava de carência (diferente do fluxo self-service do App) — data_proxima_avaliacao é livre, definida por ele. Mesmo princípio de anamneses_trg_versionar: sempre um INSERT novo, nunca edita uma anamnese anterior.';

revoke execute on function public.profissional_salvar_anamnese(uuid, jsonb) from public;
grant execute on function public.profissional_salvar_anamnese(uuid, jsonb) to authenticated;

-- ============================================================================
-- Parte 3 — Gap Crítico: validar_e_salvar_meta passa a gravar o snapshot
-- ============================================================================
-- Ponto ÚNICO de gravação de meta pra App (self-service) E Web
-- (profissional) — ver `20260812110000`. Adiciona, ao final (depois do
-- INSERT em objetivos_alimentares já ter sucedido), uma chamada a
-- calcular_motor_metabolico_v1 (RPC pura, `20260916120000`) e grava o JSON
-- exato na anamnese que originou o cálculo. Corpo da função idêntico ao
-- anterior — só a parte final (snapshot) é nova, ver comentário inline.
create or replace function public.validar_e_salvar_meta(p_payload jsonb, p_is_profissional boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_usuario_id uuid;
  v_profissional_id uuid;
  v_tipo_dia text := coalesce(p_payload->>'tipo_dia', 'PADRAO');
  v_calorias_alvo int := (p_payload->>'calorias_alvo')::int;
  v_proteina_g int := nullif(p_payload->>'proteina_g', '')::int;
  v_carbo_g int := nullif(p_payload->>'carbo_g', '')::int;
  v_gordura_g int := nullif(p_payload->>'gordura_g', '')::int;
  v_vencimento_em timestamptz := nullif(p_payload->>'vencimento_em', '')::timestamptz;
  v_motor jsonb;
  v_tmb numeric;
  v_peso_kg numeric;
  v_warnings text[] := '{}';
  v_violacao_clinica boolean := false;
  v_novo_id uuid;
  v_resultado_v1 jsonb;
  v_anamnese_snapshot_id uuid;
begin
  if p_is_profissional then
    v_usuario_id := (p_payload->>'usuario_id')::uuid;
    if v_usuario_id is null then
      raise exception 'N08_PAYLOAD_INVALIDO: usuario_id é obrigatório para prescrição profissional.';
    end if;

    if auth.uid() is distinct from v_usuario_id
       and not exists (
         select 1 from public.vinculos_profissional_paciente v
         where v.profissional_id = auth.uid()
           and v.paciente_id = v_usuario_id
           and v.status = 'ativo'
       )
       and not public.eh_admin()
    then
      raise exception 'N08_SEM_VINCULO: Sem vínculo ativo com este paciente.';
    end if;

    v_profissional_id := auth.uid();
  else
    -- Self-service: `usuario_id` é SEMPRE o chamador — nunca lido do
    -- payload (um atleta não pode criar meta para outra pessoa passando o
    -- id de outra pessoa no JSON).
    v_usuario_id := auth.uid();
    v_profissional_id := null;

    if v_usuario_id is null then
      raise exception 'N08_SEM_SESSAO: Nenhum usuário autenticado.';
    end if;

    if exists (
      select 1 from public.objetivos_alimentares o
      where o.usuario_id = v_usuario_id
        and o.tipo_dia = v_tipo_dia
        and o.status_vigencia = 'ativo'
        and o.profissional_id is not null
    ) then
      raise exception 'N08_PRIORIDADE_PROFISSIONAL: Você está sob acompanhamento de um profissional para este tipo de dia — sua meta atual só pode ser alterada por ele.';
    end if;

    if exists (
      select 1 from public.objetivos_alimentares o
      where o.usuario_id = v_usuario_id
        and o.profissional_id is null
        and o.data_criacao >= now() - interval '30 days'
    ) then
      raise exception 'N08_CARENCIA_MENSAL: Você só pode alterar sua meta de bem-estar 1x por mês.';
    end if;
  end if;

  if v_calorias_alvo is null then
    raise exception 'N08_PAYLOAD_INVALIDO: calorias_alvo é obrigatório.';
  end if;

  -- Motor N07 interno — mesma RPC que o Painel Web chama pra simular
  -- (`20260812100000`), aqui reaproveitada pro cálculo clínico. `insumos.
  -- peso_kg` já vem resolvido de lá (última leitura válida) — não repete a
  -- consulta a `metricas_saude_diarias`.
  v_motor := public.calcular_motor_metabolico(v_usuario_id);
  v_tmb := (v_motor->>'tmb')::numeric;
  v_peso_kg := (v_motor->'insumos'->>'peso_kg')::numeric;

  if v_tmb is not null and v_peso_kg is not null and v_peso_kg > 0 then
    if v_gordura_g is not null and (v_gordura_g::numeric / v_peso_kg) < 0.6 then
      v_warnings := array_append(v_warnings, 'gordura_abaixo_do_minimo_0_6g_por_kg');
      v_violacao_clinica := true;
    end if;
    if v_calorias_alvo < v_tmb then
      v_warnings := array_append(v_warnings, 'calorias_abaixo_da_tmb');
      v_violacao_clinica := true;
    end if;
    if v_calorias_alvo > (v_tmb * 2.5) then
      v_warnings := array_append(v_warnings, 'calorias_acima_de_2_5x_tmb');
      v_violacao_clinica := true;
    end if;
  else
    -- Sem TMB/peso não dá pra avaliar as 3 regras numéricas — isso NÃO é
    -- uma violação clínica (nada foi violado, é desconhecido), então nunca
    -- bloqueia; só avisa que a validação foi parcial.
    v_warnings := array_append(v_warnings, 'validacao_parcial_dados_insuficientes_para_tmb_ou_peso');
  end if;

  -- A TRAVA em si: só existe pro caminho self-service, e só quando alguma
  -- das 3 regras numéricas realmente violou (não pela nota de dado
  -- insuficiente).
  if v_violacao_clinica and not p_is_profissional then
    raise exception 'N08_TRAVA_CLINICA: Esta meta está fora da faixa de segurança para o seu perfil (calorias ou gordura incompatíveis com sua Taxa Metabólica Basal) — ajuste os valores ou procure acompanhamento profissional.';
  end if;

  insert into public.objetivos_alimentares (
    usuario_id, profissional_id, tipo_dia, calorias_alvo, proteina_g, carbo_g, gordura_g, vencimento_em
  ) values (
    v_usuario_id, v_profissional_id, v_tipo_dia, v_calorias_alvo, v_proteina_g, v_carbo_g, v_gordura_g, v_vencimento_em
  )
  returning id into v_novo_id;

  -- ── Gap Crítico (RELATÓRIO 20260917_0001, item 1) ─────────────────────
  -- A meta acabou de ser salva com sucesso (self-service OU profissional,
  -- os dois caminhos chegam até aqui) — este é o momento em que o
  -- documento pede pra "fotografar" o Resultado Calculado dentro da
  -- anamnese que originou esse número. calcular_motor_metabolico_v1 é
  -- pura (nunca escreve nada sozinha, ME-005/006) — quem grava é sempre
  -- quem CONFIRMA uma meta em cima dela, exatamente esta função.
  -- `insumos.anamnese_id` (dentro do jsonb devolvido) é null quando não há
  -- anamnese com peso/altura pra anexar o snapshot — nesse caso não há
  -- onde gravar, e isso não deve derrubar o salvamento da meta (já
  -- concluído acima).
  v_resultado_v1 := public.calcular_motor_metabolico_v1(v_usuario_id);
  v_anamnese_snapshot_id := (v_resultado_v1->'insumos'->>'anamnese_id')::uuid;

  if v_anamnese_snapshot_id is not null then
    update public.anamneses
    set resultado_motor_v1 = v_resultado_v1,
        resultado_motor_gravado_em = now()
    where id = v_anamnese_snapshot_id;
  end if;

  return jsonb_build_object(
    'sucesso', true,
    'id', v_novo_id,
    'violacao_clinica', v_violacao_clinica,
    'avisos', to_jsonb(v_warnings)
  );
end;
$$;

comment on function public.validar_e_salvar_meta(jsonb, boolean) is
  'N08 (RELATÓRIO 20260812_0010). RELATÓRIO 20260917_0001 (Gap Crítico): ao salvar a meta com sucesso, também grava o JSON exato de calcular_motor_metabolico_v1 em anamneses.resultado_motor_v1 — pra usuário self-service (App) E profissional (Web), os dois caminhos passam por esta mesma função. p_is_profissional=true (N10) nunca bloqueia, só devolve avisos; p_is_profissional=false (N11) levanta N08_TRAVA_CLINICA (Hard Block ANVISA), N08_PRIORIDADE_PROFISSIONAL ou N08_CARENCIA_MENSAL antes de sequer tentar validar/inserir.';

revoke execute on function public.validar_e_salvar_meta(jsonb, boolean) from public;
grant execute on function public.validar_e_salvar_meta(jsonb, boolean) to authenticated;
