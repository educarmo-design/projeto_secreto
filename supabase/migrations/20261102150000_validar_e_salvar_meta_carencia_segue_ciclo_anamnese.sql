-- Trava de carência mensal (N08_CARENCIA_MENSAL) passa a acompanhar o
-- CICLO DA ANAMNESE, não mais só a data da última meta (RELATÓRIO
-- 20261102_0003). Achado no teste em device físico: ao concluir uma nova
-- anamnese e tentar salvar a meta calculada pelo Motor Metabólico, o
-- usuário era bloqueado alegando carência de 30 dias — mesmo tendo
-- acabado de submeter uma avaliação nova. "A meta precisa obedecer ao
-- mesmo ciclo da anamnese" (fundador).
--
-- Mesmo corpo de `20261102140000` — a ÚNICA mudança é a condição do
-- N08_CARENCIA_MENSAL: antes bloqueava sempre que existisse QUALQUER meta
-- self-service gravada nos últimos 30 dias; agora só bloqueia quando essa
-- meta mais recente já está atrelada (via `anamnese_id`, FK — RELATÓRIO
-- 20261102_0002) à MESMA anamnese que está vigente agora (resolvida por
-- `calcular_motor_metabolico_v1`, a mesma função que já resolve a FK do
-- INSERT) — ou seja, o usuário já salvou uma meta para este MESMO ciclo e
-- está tentando editá-la de novo rapidamente (isso continua bloqueado).
-- Uma anamnese NOVA, com uma FK diferente da última meta salva, libera a
-- gravação imediatamente, mesmo dentro dos 30 dias.
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
  v_ultima_meta_propria_anamnese_id uuid;
  v_ultima_meta_propria_data timestamptz;
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
  end if;

  if v_calorias_alvo is null then
    raise exception 'N08_PAYLOAD_INVALIDO: calorias_alvo é obrigatório.';
  end if;

  -- FK direta (RELATÓRIO 20261102_0002) — resolvida ANTES do INSERT, e
  -- agora também ANTES da checagem de carência mensal (ver abaixo), que
  -- passa a depender deste valor.
  v_resultado_v1 := public.calcular_motor_metabolico_v1(v_usuario_id);
  v_anamnese_snapshot_id := (v_resultado_v1->'insumos'->>'anamnese_id')::uuid;

  -- ── Carência mensal segue o ciclo da anamnese (RELATÓRIO 20261102_0003) ──
  -- Só pro caminho self-service. Olha a meta PRÓPRIA mais recente
  -- (qualquer `status_vigencia`) e só bloqueia se ela já está atrelada à
  -- MESMA anamnese vigente agora (`is not distinct from`, null-safe: duas
  -- metas sem nenhuma anamnese atrelada também contam como "mesmo ciclo",
  -- preservando o comportamento antigo quando não há dado de anamnese pra
  -- decidir). Uma anamnese nova (FK diferente) sempre libera, mesmo
  -- dentro dos 30 dias — "a meta precisa obedecer ao mesmo ciclo da
  -- anamnese", não um calendário independente.
  if not p_is_profissional then
    select o.anamnese_id, o.data_criacao
    into v_ultima_meta_propria_anamnese_id, v_ultima_meta_propria_data
    from public.objetivos_alimentares o
    where o.usuario_id = v_usuario_id
      and o.profissional_id is null
    order by o.data_criacao desc
    limit 1;

    if v_ultima_meta_propria_data is not null
       and v_ultima_meta_propria_data >= now() - interval '30 days'
       and v_ultima_meta_propria_anamnese_id is not distinct from v_anamnese_snapshot_id
    then
      raise exception 'N08_CARENCIA_MENSAL: Você só pode alterar sua meta de bem-estar 1x por mês.';
    end if;
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
    usuario_id, profissional_id, tipo_dia, calorias_alvo, proteina_g, carbo_g, gordura_g, vencimento_em, anamnese_id
  ) values (
    v_usuario_id, v_profissional_id, v_tipo_dia, v_calorias_alvo, v_proteina_g, v_carbo_g, v_gordura_g, v_vencimento_em,
    v_anamnese_snapshot_id
  )
  returning id into v_novo_id;

  -- Gap Crítico (RELATÓRIO 20260917_0001, item 1) — snapshot do Resultado
  -- Calculado dentro da anamnese que originou esse número. Continua aqui,
  -- inalterado, usando o MESMO `v_resultado_v1`/`v_anamnese_snapshot_id` já
  -- resolvidos acima (nenhuma segunda chamada à RPC pura).
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
  'N08 (RELATÓRIO 20260812_0010). RELATÓRIO 20260917_0001 (Gap Crítico): grava o snapshot de calcular_motor_metabolico_v1 em anamneses.resultado_motor_v1. RELATÓRIO 20261102_0002: o mesmo anamnese_id do snapshot também é gravado como FK direta em objetivos_alimentares.anamnese_id. RELATÓRIO 20261102_0003: N08_CARENCIA_MENSAL só bloqueia quando a última meta própria já está atrelada à MESMA anamnese vigente agora — uma anamnese nova sempre libera a gravação, mesmo dentro dos 30 dias. p_is_profissional=true (N10) nunca bloqueia, só devolve avisos; p_is_profissional=false (N11) levanta N08_TRAVA_CLINICA (Hard Block ANVISA), N08_PRIORIDADE_PROFISSIONAL ou N08_CARENCIA_MENSAL antes de sequer tentar validar/inserir.';

revoke execute on function public.validar_e_salvar_meta(jsonb, boolean) from public;
grant execute on function public.validar_e_salvar_meta(jsonb, boolean) to authenticated;
