-- FK direta `objetivos_alimentares.anamnese_id -> anamneses.id` (RELATÓRIO
-- 20261102_0002) — substitui a correlação por JANELA DE TEMPO introduzida
-- no RELATÓRIO 20261102_0001 (sem FK). O fundador rejeitou a heurística por
-- data: "Correlação por data é frágil e viola boas práticas de modelagem
-- relacional. O vínculo DEVE ser feito exclusivamente por Chave Estrangeira
-- (FK) direta (anamnese_id)."
--
-- ============================================================================
-- Parte 1 — Coluna + FK
-- ============================================================================
-- Nullable: nem toda meta tem uma anamnese com dados antropométricos
-- completos por trás (ver Parte 2 — mesmo gap que `anamneses.resultado_motor_v1`
-- já documentava: `calcular_motor_metabolico_v1` só resolve `anamnese_id`
-- quando existe pelo menos uma anamnese com peso_kg E altura_cm preenchidos).
alter table objetivos_alimentares
  add column if not exists anamnese_id uuid references anamneses (id) on delete cascade;

comment on column objetivos_alimentares.anamnese_id is
  'RELATÓRIO 20261102_0002 — FK direta para a anamnese que serviu de insumo (peso/altura, SSOT) ao cálculo que originou esta meta. Gravada por validar_e_salvar_meta a partir do MESMO anamnese_id que calcular_motor_metabolico_v1 já resolvia para o snapshot em anamneses.resultado_motor_v1 — não é um valor novo/inventado, só passou a ser persistido aqui também. NULL quando o usuário não tinha nenhuma anamnese com dados antropométricos completos no momento em que a meta foi salva.';

create index idx_objetivos_alimentares_anamnese_id
  on objetivos_alimentares (anamnese_id);

-- ============================================================================
-- Parte 2 — validar_e_salvar_meta: grava a FK no INSERT (não mais só depois)
-- ============================================================================
-- Mesmo corpo de `20260917120000` — a ÚNICA mudança é a ORDEM: a chamada a
-- `calcular_motor_metabolico_v1` (e a leitura de `insumos.anamnese_id`) sobe
-- para ANTES do INSERT em `objetivos_alimentares`, para que `anamnese_id`
-- já vá dentro do próprio INSERT, não como um UPDATE separado depois. O
-- resto do fluxo (snapshot gravado em `anamneses.resultado_motor_v1`) continua
-- idêntico — é o MESMO resultado (`v_resultado_v1`), calculado uma vez só.
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

  -- ── FK direta (RELATÓRIO 20261102_0002) ────────────────────────────────
  -- Resolvida ANTES do INSERT (diferente de `20260917120000`, que só
  -- calculava isto depois, só para o snapshot em `anamneses`). `insumos.
  -- anamnese_id` é a MESMA anamnese que serviu de SSOT de peso/altura para
  -- `v_motor` acima — null quando o usuário não tem nenhuma anamnese com os
  -- dois campos preenchidos (não bloqueia o salvamento da meta).
  v_resultado_v1 := public.calcular_motor_metabolico_v1(v_usuario_id);
  v_anamnese_snapshot_id := (v_resultado_v1->'insumos'->>'anamnese_id')::uuid;

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
  'N08 (RELATÓRIO 20260812_0010). RELATÓRIO 20260917_0001 (Gap Crítico): grava o snapshot de calcular_motor_metabolico_v1 em anamneses.resultado_motor_v1. RELATÓRIO 20261102_0002: o MESMO anamnese_id do snapshot agora também é gravado como FK direta em objetivos_alimentares.anamnese_id (dentro do próprio INSERT) — substitui a correlação por janela de tempo do RELATÓRIO 20261102_0001. p_is_profissional=true (N10) nunca bloqueia, só devolve avisos; p_is_profissional=false (N11) levanta N08_TRAVA_CLINICA (Hard Block ANVISA), N08_PRIORIDADE_PROFISSIONAL ou N08_CARENCIA_MENSAL antes de sequer tentar validar/inserir.';

revoke execute on function public.validar_e_salvar_meta(jsonb, boolean) from public;
grant execute on function public.validar_e_salvar_meta(jsonb, boolean) to authenticated;

-- ============================================================================
-- Parte 3 — Backfill retroativo (registros existentes, anamnese_id ainda null)
-- ============================================================================
-- GAP HONESTO, documentado (não escondido): para linhas já existentes, NÃO
-- EXISTE nenhuma FK histórica gravada no momento do INSERT original (a
-- coluna não existia ainda) — reconstruir o vínculo retroativamente exige,
-- por definição, inferir qual era a anamnese "ativa" quando aquela meta foi
-- salva. A Restrição "proibido comparação de data" é sobre a CONSULTA em
-- runtime do app (Parte 4/Flutter — essa sim passa a usar SÓ a FK, nunca
-- mais um filtro de data); este UPDATE de backfill é um evento ÚNICO, que
-- roda uma vez nesta migration, popula a coluna, e nunca mais é necessário
-- depois (todo INSERT novo já grava a FK real via Parte 2). Critério: a
-- anamnese mais recente do mesmo usuário com data_preenchimento <= à
-- data_criacao da meta (a anamnese que já existia quando a meta foi salva).
update public.objetivos_alimentares o
set anamnese_id = (
  select a.id
  from public.anamneses a
  where a.usuario_id = o.usuario_id
    and a.data_preenchimento <= o.data_criacao
  order by a.data_preenchimento desc
  limit 1
)
where o.anamnese_id is null;
