-- Fundação de dados para as novas regras de Anamnese/Metas (RELATÓRIO
-- 20260915_0002) — pedido explícito do fundador: preparar backend/banco
-- ANTES de tocar no Flutter. 3 mudanças reais de schema + 1 RPC nova; os
-- outros 2 itens do pedido (campos altura/peso/sexo no perfil; catálogo +
-- estrutura relacional de alergias) JÁ EXISTIAM antes desta migration —
-- auditados abaixo, não redigitados.

-- ============================================================================
-- Parte 0 — Auditoria do que já existe (achado, sem alteração de schema)
-- ============================================================================
-- 1. altura/peso/sexo no PERFIL: `perfis_usuarios.altura_cm` (numeric,
--    20260811130000), `perfis_usuarios.peso_kg` (numeric, autodeclarado no
--    cadastro, 20260722120000 — reforçado continuamente pela telemetria em
--    `metricas_saude_diarias.peso_kg`, que é o que `calcular_motor_
--    metabolico` de fato consulta), `perfis_usuarios.sexo_biologico`
--    (ENUM M/F, 20260812100000) — os 3 já existem e já são os insumos reais
--    do Motor N07. Nenhuma coluna nova necessária; só reforço de comentário
--    abaixo, para não deixar a intenção implícita.
-- 2. ALERGIAS — catálogo + estrutura relacional pra múltiplas por usuário:
--    `alergias` (catálogo, 20260811210000) + `usuario_alergias` (N:N direto
--    no perfil) + `anamneses_alergias` (N:N versionado, uma cópia por
--    preenchimento de anamnese, 20260811240000) já cobrem exatamente o que
--    foi pedido. Nenhuma tabela nova necessária.
comment on column perfis_usuarios.altura_cm is
  'Insumo do Motor Metabólico N07 (Mifflin-St Jeor). Reforçado como parte da fundação de dados de Anamnese/Metas (RELATÓRIO 20260915_0002) — coluna já existia desde 20260811130000, sem alteração aqui.';
comment on column perfis_usuarios.peso_kg is
  'Peso autodeclarado no cadastro (colhido 1 vez) — NÃO é o que o Motor N07 usa para calcular TMB/TDEE (isso vem de metricas_saude_diarias.peso_kg, a última leitura válida, sincronizada continuamente). Reforçado como parte da fundação de dados de Anamnese/Metas (RELATÓRIO 20260915_0002) — coluna já existia desde 20260722120000, sem alteração aqui.';

-- ============================================================================
-- Parte 1 — Rotina por Dia da Semana (múltiplas atividades por dia)
-- ============================================================================
-- ACHADO: `anamneses_atividades` (20260811240000) já é N:N anamnese x
-- atividade, mas só tem 1 linha por (anamnese, atividade) com
-- `minutos_diarios` — um único número aplicado IMPLICITAMENTE a todo santo
-- dia da semana (é assim que `calcular_motor_metabolico` consome hoje). Não
-- dá pra representar "corro 30min seg/qua/sex, mas 60min domingo", nem
-- distinguir dias sem nenhuma atividade.
--
-- DECISÃO (Restrição da tarefa — "não tocar no Flutter"): em vez de alterar
-- `anamneses_atividades` (o app já grava linhas nela hoje, sem nenhuma
-- noção de dia da semana — mudar sua PK/colunas quebraria esse INSERT em
-- produção até uma tarefa FUTURA atualizar o Flutter), esta migration
-- ADICIONA uma tabela nova, paralela, opcional: `anamneses_atividades_dias`.
-- `anamneses_atividades` fica 100% intacta — zero risco pro app atual.
-- O Motor (Parte 3) usa a tabela nova QUANDO ela tem dado para a anamnese
-- ativa; senão cai no comportamento de hoje (minutos_diarios uniforme) —
-- ver `gerar_sugestao_meta`.
create table if not exists anamneses_atividades_dias (
  anamnese_id uuid not null references anamneses (id) on delete cascade,
  atividade_id smallint not null references tipos_atividades_fisicas (id),
  -- Convenção do Postgres (extract(dow from date)): 0 = domingo, 6 = sábado.
  -- Evita reinventar um enum próprio de dia-da-semana e qualquer conversão
  -- manual — o motor itera com generate_series(0, 6) direto.
  dia_semana smallint not null check (dia_semana between 0 and 6),
  minutos int not null check (minutos > 0 and minutos <= 1440),
  primary key (anamnese_id, atividade_id, dia_semana)
);

comment on table anamneses_atividades_dias is
  'Rotina de atividades por dia da semana (RELATÓRIO 20260915_0002) — granularidade nova, ADITIVA a anamneses_atividades (que continua existindo e sendo a única gravada pelo app Flutter até uma tarefa futura atualizar o frontend). Permite múltiplas atividades no mesmo dia (várias linhas com o mesmo dia_semana) e a MESMA atividade com durações diferentes em dias diferentes (mesmo atividade_id, dia_semana e minutos distintos). O Motor Metabólico usa esta tabela quando ela tem dado para a anamnese ativa; senão, cai no fallback de anamneses_atividades.minutos_diarios (comportamento uniforme de hoje).';
comment on column anamneses_atividades_dias.dia_semana is
  '0 = domingo, 1 = segunda, ..., 6 = sábado — mesma convenção de extract(dow from date) do Postgres.';
comment on column anamneses_atividades_dias.minutos is
  'Minutos NESTE dia específico (não "por dia" uniforme como em anamneses_atividades.minutos_diarios) — input do Motor Metabólico junto com tipos_atividades_fisicas.met_estimado.';

alter table anamneses_atividades_dias enable row level security;

-- Mesmo padrão exato de `anamneses_atividades` (20260811240000): dono ou
-- profissional com vínculo ATIVO lê; só o dono escreve/apaga.
-- `drop policy if exists` antes de cada `create policy` — Postgres não tem
-- `create policy if not exists`; sem isto, reaplicar esta migration (ex.:
-- correção de um bug achado depois do 1º `db push`) falha com "policy
-- already exists" na 2ª rodada (RESTRIÇÃO da tarefa: migração idempotente).
drop policy if exists "anamneses_atividades_dias_select_own_or_profissional" on anamneses_atividades_dias;
create policy "anamneses_atividades_dias_select_own_or_profissional"
  on anamneses_atividades_dias for select
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_atividades_dias.anamnese_id
        and (
          a.usuario_id = auth.uid()
          or exists (
            select 1 from vinculos_profissional_paciente v
            where v.profissional_id = auth.uid()
              and v.paciente_id = a.usuario_id
              and v.status = 'ativo'
          )
        )
    )
  );

drop policy if exists "anamneses_atividades_dias_insert_own" on anamneses_atividades_dias;
create policy "anamneses_atividades_dias_insert_own"
  on anamneses_atividades_dias for insert
  with check (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_atividades_dias.anamnese_id and a.usuario_id = auth.uid()
    )
  );

drop policy if exists "anamneses_atividades_dias_delete_own" on anamneses_atividades_dias;
create policy "anamneses_atividades_dias_delete_own"
  on anamneses_atividades_dias for delete
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_atividades_dias.anamnese_id and a.usuario_id = auth.uid()
    )
  );

grant select, insert, delete on anamneses_atividades_dias to authenticated;

-- ============================================================================
-- Parte 2 — Sugestão vs Meta: sugestao_meta (separada de objetivos_alimentares)
-- ============================================================================
-- `objetivos_alimentares` (20260812110000) já é a META REAL do usuário —
-- INSERT-only via `validar_e_salvar_meta` (Motor de Exceções N08),
-- versionada por (usuario_id, tipo_dia). Isso continua intocado.
--
-- O que faltava: o OUTPUT do Motor Metabólico (`calcular_motor_metabolico`)
-- nunca é persistido — é calculado ao vivo e devolvido, sem deixar rastro.
-- `sugestao_meta` é essa persistência: uma linha por rodada do motor,
-- nunca escrita direto em `objetivos_alimentares` (a "meta ativa" só muda
-- quando o usuário/profissional confirma via `validar_e_salvar_meta` —
-- essa RPC nova, Parte 3, NUNCA chama `validar_e_salvar_meta` nem faz
-- INSERT em `objetivos_alimentares`).
create table if not exists sugestao_meta (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users (id) on delete cascade,
  -- Nullable: o motor roda mesmo sem anamnese ativa (devolve avisos, mesmo
  -- espírito de "nunca lança exceção por dado faltante" de calcular_motor_
  -- metabolico) — não há anamnese nenhuma pra referenciar nesse caso.
  anamnese_id uuid references anamneses (id) on delete set null,
  -- Saída BRUTA e completa de calcular_motor_metabolico (tmb/gasto_
  -- sedentario/tef/insumos/formula_usada/avisos) — rastreabilidade total de
  -- "por que a sugestão saiu assim", sem duplicar cada campo em coluna própria.
  motor_resultado jsonb not null,
  -- Detalhe por dia da semana: objeto jsonb chaveado por "0".."6" (mesma
  -- convenção de anamneses_atividades_dias.dia_semana), cada valor com
  -- {gasto_atividade, tdee} daquele dia. "MÉDIA" fica em tdee_medio (coluna
  -- própria, não dentro do jsonb) — os dois conceitos pedidos pelo
  -- fundador ("média" e "detalhe por dia da semana") ficam explícitos e
  -- fáceis de consultar sem parsear jsonb pra pegar só a média.
  detalhe_por_dia jsonb not null,
  tdee_medio numeric,
  formula_usada text not null,
  avisos text[] not null default '{}',
  gerado_em timestamptz not null default now(),
  status_vigencia text not null default 'ativo'
    check (status_vigencia in ('ativo', 'historico'))
);

comment on table sugestao_meta is
  'RELATÓRIO 20260915_0002 — output do Motor Metabólico PERSISTIDO (antes só existia em memória, devolvido ao vivo por calcular_motor_metabolico). Separada, de propósito, de objetivos_alimentares (a meta REAL do usuário): sugestao_meta é gerada automaticamente a cada rodada do motor (RPC gerar_sugestao_meta), objetivos_alimentares só muda quando confirmada por validar_e_salvar_meta. Nunca uma escreve na outra. INSERT-only do ponto de vista do cliente — sem policy de INSERT para authenticated (só a RPC, security definer, grava).';
comment on column sugestao_meta.tdee_medio is
  'Média do TDEE dos 7 dias da semana (null se o motor não teve dados suficientes em nenhum dia) — o conceito de "média" pedido pelo fundador, ao lado do detalhe por dia em detalhe_por_dia.';
comment on column sugestao_meta.detalhe_por_dia is
  'Objeto jsonb chaveado por dia da semana ("0"=domingo .. "6"=sábado, mesma convenção de anamneses_atividades_dias.dia_semana) — cada valor: {"gasto_atividade": numeric|null, "tdee": numeric|null}.';

create index if not exists idx_sugestao_meta_usuario_status on sugestao_meta (usuario_id, status_vigencia);

alter table sugestao_meta enable row level security;

drop policy if exists "sugestao_meta_select_own" on sugestao_meta;
create policy "sugestao_meta_select_own"
  on sugestao_meta for select
  using (usuario_id = auth.uid());

-- Mesmo padrão de `objetivos_alimentares_select_profissional_vinculado`.
drop policy if exists "sugestao_meta_select_profissional_vinculado" on sugestao_meta;
create policy "sugestao_meta_select_profissional_vinculado"
  on sugestao_meta for select
  using (
    exists (
      select 1
      from vinculos_profissional_paciente v
      where v.profissional_id = auth.uid()
        and v.paciente_id = sugestao_meta.usuario_id
        and v.status = 'ativo'
    )
  );

-- SEM policy de INSERT/UPDATE/DELETE para `authenticated` — mesmo padrão de
-- `objetivos_alimentares`: só a RPC `gerar_sugestao_meta` (security
-- definer) grava.
grant select on sugestao_meta to authenticated;

-- Versionamento — mesmo padrão exato de `anamneses_trg_versionar`
-- (20260811240000): no máximo 1 sugestão "ativo" por usuário, a anterior
-- vira "historico" automaticamente.
create or replace function public.sugestao_meta_versionar_status_vigencia()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status_vigencia = 'ativo' then
    update public.sugestao_meta
    set status_vigencia = 'historico'
    where usuario_id = new.usuario_id
      and status_vigencia = 'ativo';
  end if;
  return new;
end;
$$;

drop trigger if exists sugestao_meta_trg_versionar on sugestao_meta;
create trigger sugestao_meta_trg_versionar
  before insert on sugestao_meta
  for each row
  execute function public.sugestao_meta_versionar_status_vigencia();

comment on trigger sugestao_meta_trg_versionar on sugestao_meta is
  'RELATÓRIO 20260915_0002: garante no máximo 1 sugestão "ativo" por usuário — a antiga vira "historico" automaticamente a cada nova rodada do motor. Mesmo padrão de anamneses_trg_versionar/objetivos_alimentares_trg_versionar.';

-- ============================================================================
-- Parte 3 — Motor Metabólico: iterar por dia da semana + gravar sugestão
-- ============================================================================
-- NÃO modifica `calcular_motor_metabolico` (assinatura/retorno intocados —
-- tem consumidores reais em produção: validar_e_salvar_meta, o App Flutter
-- via meta_bem_estar_repository.dart, e o Painel Web via
-- MotorMetabolicoCard.tsx/InserirMedicaoModal.tsx; mudar o contrato dela
-- quebraria os 3). Esta função nova REAPROVEITA calcular_motor_metabolico
-- para TMB/gasto_sedentario/tef/insumos (mesmíssima fórmula, chamada
-- internamente, zero duplicação) e ACRESCENTA a iteração por dia da semana
-- que faltava — puramente aditivo.
--
-- Para cada dia 0..6: soma o gasto_atividade daquele dia. Se a anamnese
-- ativa tem QUALQUER linha em anamneses_atividades_dias, usa-a (dado real
-- por dia); senão, cai no fallback de anamneses_atividades.minutos_diarios
-- aplicado a TODOS os 7 dias (mesmo cálculo que calcular_motor_metabolico
-- já fazia sozinho — preserva 100% de compatibilidade para quem ainda não
-- tem rotina detalhada por dia).
--
-- Nunca lança exceção por dado faltante (mesmo espírito do motor original)
-- — grava a sugestão mesmo com tdee_medio/detalhe null, propagando os
-- mesmos avisos que calcular_motor_metabolico já gera. NUNCA chama
-- validar_e_salvar_meta nem escreve em objetivos_alimentares — a meta ativa
-- só muda quando o usuário/profissional confirma explicitamente essa RPC
-- (fora do escopo desta tarefa, que é só preparar o backend).
create or replace function public.gerar_sugestao_meta(p_usuario_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_anamnese_id uuid;
  v_motor jsonb;
  v_gasto_sedentario numeric;
  v_peso_kg numeric;
  v_formula text;
  v_avisos text[];
  v_usa_detalhe_por_dia boolean;
  v_dia int;
  v_gasto_atividade_dia numeric;
  v_tdee_dia numeric;
  v_detalhe jsonb := '{}'::jsonb;
  v_soma_tdee numeric := 0;
  v_dias_com_tdee int := 0;
  v_tdee_medio numeric;
  v_sugestao_id uuid;
begin
  -- Mesmo guard de acesso de calcular_motor_metabolico/validar_e_salvar_meta.
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

  v_motor := public.calcular_motor_metabolico(p_usuario_id);
  v_gasto_sedentario := (v_motor->>'gasto_sedentario')::numeric;
  v_peso_kg := (v_motor->'insumos'->>'peso_kg')::numeric;
  v_formula := v_motor->>'formula_usada';
  select array(select jsonb_array_elements_text(v_motor->'avisos')) into v_avisos;

  select id into v_anamnese_id
  from public.anamneses
  where usuario_id = p_usuario_id and status_vigencia = 'ativo'
  limit 1;

  -- ACHADO (verificação ao vivo contra o banco real, atleta1000@teste.com,
  -- antes de fechar esta tarefa): NÃO adiciona 'sem_anamnese_ativa' aqui —
  -- calcular_motor_metabolico já adiciona esse mesmo aviso sozinho (dentro
  -- de v_motor->'avisos', já copiado para v_avisos acima) sempre que há
  -- peso mas falta anamnese. Adicionar de novo aqui duplicava o aviso.

  v_usa_detalhe_por_dia := v_anamnese_id is not null and exists (
    select 1 from public.anamneses_atividades_dias where anamnese_id = v_anamnese_id
  );

  for v_dia in 0..6 loop
    if v_peso_kg is null then
      -- Sem peso: o motor genuinamente não sabe o gasto de atividade —
      -- null, mesmo tratamento de calcular_motor_metabolico.
      v_gasto_atividade_dia := null;
    elsif v_anamnese_id is null then
      -- ACHADO (mesma verificação ao vivo): com peso mas sem anamnese
      -- ativa, o gasto de atividade é CONHECIDO como zero (não há
      -- atividade nenhuma declarada) — nunca null. Tratar os dois casos
      -- igual (como a 1ª versão desta função fazia) zerava o `tdee` dos 7
      -- dias inteiro sempre que faltava anamnese, mesmo quando
      -- gasto_sedentario já era um número real — divergia do
      -- `calcular_motor_metabolico` original, que corretamente devolve
      -- `tdee = gasto_sedentario + 0` nesse caso.
      v_gasto_atividade_dia := 0;
    elsif v_usa_detalhe_por_dia then
      select coalesce(sum(coalesce(t.met_estimado, 0) * v_peso_kg * (aad.minutos / 60.0)), 0)
      into v_gasto_atividade_dia
      from public.anamneses_atividades_dias aad
      join public.tipos_atividades_fisicas t on t.id = aad.atividade_id
      where aad.anamnese_id = v_anamnese_id and aad.dia_semana = v_dia;
    else
      -- Fallback: mesma query que calcular_motor_metabolico faz sozinha
      -- hoje, aplicada a cada um dos 7 dias (comportamento uniforme).
      select coalesce(sum(coalesce(t.met_estimado, 0) * v_peso_kg * (aa.minutos_diarios / 60.0)), 0)
      into v_gasto_atividade_dia
      from public.anamneses_atividades aa
      join public.tipos_atividades_fisicas t on t.id = aa.atividade_id
      where aa.anamnese_id = v_anamnese_id;
    end if;

    v_tdee_dia := case
      when v_gasto_sedentario is not null and v_gasto_atividade_dia is not null
      then v_gasto_sedentario + v_gasto_atividade_dia
      else null
    end;

    v_detalhe := v_detalhe || jsonb_build_object(
      v_dia::text,
      jsonb_build_object('gasto_atividade', v_gasto_atividade_dia, 'tdee', v_tdee_dia)
    );

    if v_tdee_dia is not null then
      v_soma_tdee := v_soma_tdee + v_tdee_dia;
      v_dias_com_tdee := v_dias_com_tdee + 1;
    end if;
  end loop;

  -- Só considera a média válida com os 7 dias completos — uma média sobre
  -- só 3 ou 4 dias com dado (ex.: gasto_sedentario ficou null no meio) seria
  -- enviesada e mentirosa apresentada como "a média da semana".
  v_tdee_medio := case when v_dias_com_tdee = 7 then v_soma_tdee / 7 else null end;

  insert into public.sugestao_meta (
    usuario_id, anamnese_id, motor_resultado, detalhe_por_dia, tdee_medio, formula_usada, avisos
  ) values (
    p_usuario_id, v_anamnese_id, v_motor, v_detalhe, v_tdee_medio, v_formula, v_avisos
  )
  returning id into v_sugestao_id;

  return jsonb_build_object(
    'id', v_sugestao_id,
    'motor_resultado', v_motor,
    'detalhe_por_dia', v_detalhe,
    'tdee_medio', v_tdee_medio,
    'formula_usada', v_formula,
    'avisos', to_jsonb(v_avisos)
  );
end;
$$;

comment on function public.gerar_sugestao_meta(uuid) is
  'RELATÓRIO 20260915_0002 — estende calcular_motor_metabolico (reaproveitada internamente, contrato dela intocado) iterando os 7 dias da semana: usa anamneses_atividades_dias quando a anamnese ativa tem rotina detalhada por dia, senão cai no fallback uniforme de anamneses_atividades.minutos_diarios (mesmo cálculo que o motor original já fazia). Grava o resultado em sugestao_meta (histórico versionado) — NUNCA escreve em objetivos_alimentares nem chama validar_e_salvar_meta; a meta ativa do usuário só muda por confirmação explícita, fora do escopo desta RPC.';

revoke execute on function public.gerar_sugestao_meta(uuid) from public;
grant execute on function public.gerar_sugestao_meta(uuid) to authenticated;
