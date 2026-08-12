-- N08 (Motor de Exceções, dupla via) + N10 (Prescrição Profissional) + N11
-- (Meta Self-Service do Atleta). RELATÓRIO 20260812_0010.
--
-- A "dupla via" inteira mora numa única RPC (`validar_e_salvar_meta`): o
-- Painel Web (profissional) e o App Flutter (atleta) chamam exatamente a
-- mesma função, com `p_is_profissional` mudando o comportamento das MESMAS
-- regras — nunca duas implementações da mesma matemática clínica. Ver o
-- comentário da função abaixo para a lógica completa.

-- ============================================================================
-- Parte 1 — Tabela de metas + versionamento
-- ============================================================================
create table objetivos_alimentares (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users (id) on delete cascade,
  -- Nullable: uma meta self-service (N11) não tem profissional. Quem
  -- prescreveu — não quem a meta é PARA (isso é `usuario_id`).
  profissional_id uuid references auth.users (id) on delete set null,
  tipo_dia text not null default 'PADRAO',
  calorias_alvo int not null,
  proteina_g int,
  carbo_g int,
  gordura_g int,
  data_criacao timestamptz not null default now(),
  -- Só usado por N10 (prescrição profissional, +7 dias por padrão no
  -- formulário React) — N11 self-service não define vencimento (fica NULL).
  vencimento_em timestamptz,
  status_vigencia text not null default 'ativo'
    check (status_vigencia in ('ativo', 'historico'))
);

comment on table objetivos_alimentares is
  'N10/N11 (RELATÓRIO 20260812_0010) — meta calórica/macros do usuário, prescrita por profissional (`profissional_id` preenchido) ou self-service (`profissional_id` null). INSERT-only do ponto de vista do cliente — toda gravação passa por validar_e_salvar_meta (Motor de Exceções N08), nunca um INSERT direto (não há policy de escrita para authenticated nesta tabela).';
comment on column objetivos_alimentares.tipo_dia is
  'Texto livre (ex.: PADRAO, TREINO, DESCANSO) — permite metas distintas coexistindo ATIVAS para dias diferentes do mesmo usuário; o versionamento (trigger abaixo) só substitui a meta ATIVA do MESMO tipo_dia.';

create index idx_objetivos_alimentares_usuario_tipo_status
  on objetivos_alimentares (usuario_id, tipo_dia, status_vigencia);

alter table objetivos_alimentares enable row level security;

create policy "objetivos_alimentares_select_own"
  on objetivos_alimentares for select
  using (usuario_id = auth.uid());

-- Mesmo padrão de `anamneses_select_profissional_vinculado`/
-- `metricas_saude_diarias_select_profissional_vinculado`: só vínculo ATIVO.
create policy "objetivos_alimentares_select_profissional_vinculado"
  on objetivos_alimentares for select
  using (
    exists (
      select 1
      from vinculos_profissional_paciente v
      where v.profissional_id = auth.uid()
        and v.paciente_id = objetivos_alimentares.usuario_id
        and v.status = 'ativo'
    )
  );

-- SEM policy de INSERT/UPDATE/DELETE para `authenticated` — de propósito.
-- O Motor de Exceções (N08) só existe se for IMPOSSÍVEL contornar,
-- inserindo direto na tabela; a única porta de escrita é
-- `validar_e_salvar_meta` (`security definer`, roda como o dono/postgres,
-- que ignora RLS). Mesmo espírito de `papeis_permissoes`
-- (`20260811200000_d3_rbac_dinamico.sql`).
grant select on objetivos_alimentares to authenticated;

-- ----------------------------------------------------------------------------
-- Trigger de versionamento — mesmo padrão de `anamneses_trg_versionar`
-- (`20260811240000`), com o escopo extra de `tipo_dia`: só a meta ATIVA do
-- MESMO usuário E MESMO tipo_dia vira histórico.
-- ----------------------------------------------------------------------------
create or replace function public.objetivos_alimentares_versionar_status_vigencia()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status_vigencia = 'ativo' then
    update public.objetivos_alimentares
    set status_vigencia = 'historico'
    where usuario_id = new.usuario_id
      and tipo_dia = new.tipo_dia
      and status_vigencia = 'ativo';
  end if;
  return new;
end;
$$;

create trigger objetivos_alimentares_trg_versionar
  before insert on objetivos_alimentares
  for each row
  execute function public.objetivos_alimentares_versionar_status_vigencia();

comment on trigger objetivos_alimentares_trg_versionar on objetivos_alimentares is
  'N10/N11 (RELATÓRIO 20260812_0010): garante no máximo 1 meta "ativo" por (usuario_id, tipo_dia) — a antiga vira "historico" automaticamente. Mesmo padrão de anamneses_trg_versionar.';

-- ============================================================================
-- Parte 2 — RPC Motor de Exceções (N08): validar_e_salvar_meta
-- ============================================================================
-- Dupla via, UMA função:
--   p_is_profissional = true  (N10, Painel Web) — vínculo ATIVO exigido com
--     o paciente; violação clínica vira WARNING na resposta, NUNCA bloqueia
--     o INSERT (o profissional decide, com o aviso na tela).
--   p_is_profissional = false (N11, App Flutter) — `usuario_id` é sempre
--     `auth.uid()` (o payload não pode mandar isso, evita um atleta criar
--     meta para outra pessoa); violação clínica vira RAISE EXCEPTION
--     (Hard Block ANVISA) — o INSERT nunca acontece.
--
-- Só para o caminho self-service (p_is_profissional = false), duas travas
-- ADICIONAIS rodam ANTES da validação clínica (ordem importa — a mensagem
-- de erro precisa ser a certa para a UI decidir o que mostrar):
--   1. Prioridade B2B (RESTRIÇÃO explícita da tarefa): se já existe uma
--      meta ATIVA do mesmo tipo_dia com profissional_id preenchido, o
--      atleta NÃO pode sobrescrevê-la — precisa ser o profissional a mudar.
--   2. Carência de 1x/mês: só conta metas AUTO-criadas (profissional_id is
--      null) — uma prescrição profissional não consome a cota self-service
--      do atleta.
--
-- Mensagens de erro prefixadas (`N08_...`) de propósito — o client
-- (React/Flutter) faz `error.message.includes('N08_TRAVA_CLINICA')` etc.
-- pra decidir qual modal/banner mostrar, mesmo padrão já usado em
-- `perfis_usuarios_maioridade`/`AcessoNaoAutorizadoError`.
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

  return jsonb_build_object(
    'sucesso', true,
    'id', v_novo_id,
    'violacao_clinica', v_violacao_clinica,
    'avisos', to_jsonb(v_warnings)
  );
end;
$$;

comment on function public.validar_e_salvar_meta(jsonb, boolean) is
  'N08 (RELATÓRIO 20260812_0010) — Motor de Exceções de dupla via: p_is_profissional=true (N10) nunca bloqueia, só devolve avisos; p_is_profissional=false (N11) levanta N08_TRAVA_CLINICA (Hard Block ANVISA), N08_PRIORIDADE_PROFISSIONAL (meta prescrita não pode ser sobrescrita pelo próprio atleta) ou N08_CARENCIA_MENSAL (1x/30 dias) antes de sequer tentar validar/inserir.';

revoke execute on function public.validar_e_salvar_meta(jsonb, boolean) from public;
grant execute on function public.validar_e_salvar_meta(jsonb, boolean) to authenticated;
