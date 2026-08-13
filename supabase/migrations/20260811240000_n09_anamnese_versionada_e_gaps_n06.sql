-- N09 (Anamnese Nutricional Versionada, self-service no app Flutter,
-- lib/features/nutricao) + 2 gaps de negócio no N06/Motor N07 pedidos pelo
-- fundador nesta tarefa (RELATÓRIO 20260811_0007).

-- ============================================================================
-- Parte 1 — Gaps N06 / Motor N07
-- ============================================================================

-- met_estimado (Metabolic Equivalent of Task) — usado pelo Motor N07
-- (futuro, não implementado nesta tarefa) para estimar gasto calórico de um
-- treino: kcal ≈ MET × peso_kg × horas. NULL até o Admin cadastrar via
-- AdminAtividadesFisicas.tsx — não existe fonte automática de MET por
-- modalidade hoje (o pacote `health` não devolve isso).
alter table tipos_atividades_fisicas
  add column if not exists met_estimado numeric(5, 2);

comment on column tipos_atividades_fisicas.met_estimado is
  'MET estimado da modalidade (RELATÓRIO 20260811_0007) — input do Motor N07 (futuro) para gasto calórico de treino. Curadoria manual do Admin, sem cálculo automático nesta tarefa.';

-- Catálogo de problemas de saúde (comorbidades autodeclaradas) — mesmo
-- espírito de `alergias` (20260811210000), mas mais simples por pedido
-- explícito do fundador: só id + nome, sem código/descrição.
create table if not exists problemas_saude (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique
);

comment on table problemas_saude is
  'Catálogo de problemas de saúde (comorbidades) autodeclarados na Anamnese (N09) — RELATÓRIO 20260811_0007. Curadoria por Admin (AdminProblemasSaude.tsx).';

alter table problemas_saude enable row level security;

create policy "problemas_saude_select_all"
  on problemas_saude for select
  to authenticated
  using (true);

create policy "problemas_saude_insert_admin"
  on problemas_saude for insert
  to authenticated
  with check (eh_admin());

create policy "problemas_saude_update_admin"
  on problemas_saude for update
  to authenticated
  using (eh_admin())
  with check (eh_admin());

create policy "problemas_saude_delete_admin"
  on problemas_saude for delete
  to authenticated
  using (eh_admin());

grant select, insert, update, delete on problemas_saude to authenticated;

-- ============================================================================
-- Parte 2 — N09: Anamnese Nutricional Versionada
-- ============================================================================
-- Cada preenchimento é uma LINHA NOVA em `anamneses` — nunca um UPDATE na
-- anterior (histórico completo preservado para consulta futura por um
-- profissional/auditoria). `status_vigencia` marca qual é a vigente; o
-- trigger da seção 2.3 garante no máximo 1 'ativo' por usuário.
create table anamneses (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users (id) on delete cascade,
  -- Nullable: preenchimento self-service (Passo 1 do N09) não tem
  -- profissional associado no momento — reservado para um fluxo futuro onde
  -- um profissional revisa/assina a anamnese do paciente vinculado.
  profissional_id uuid references auth.users (id) on delete set null,
  objetivo_codigo text not null
    check (objetivo_codigo in ('emagrecimento', 'manutencao', 'hipertrofia')),
  data_preenchimento timestamptz not null default now(),
  status_vigencia text not null default 'ativo'
    check (status_vigencia in ('ativo', 'historico'))
);

comment on table anamneses is
  'N09 — Anamnese Nutricional Versionada, self-service (lib/features/nutricao/anamnese_self_service_page.dart). INSERT-only do ponto de vista do cliente: um novo preenchimento é sempre uma linha nova, nunca um UPDATE — RELATÓRIO 20260811_0007.';
comment on column anamneses.status_vigencia is
  '"ativo" = versão vigente (no máximo 1 por usuário, garantido pelo trigger anamneses_trg_versionar); "historico" = substituída por um preenchimento mais recente. Nunca apagada.';

create index idx_anamneses_usuario_status on anamneses (usuario_id, status_vigencia);

alter table anamneses enable row level security;

create policy "anamneses_select_own"
  on anamneses for select
  using (usuario_id = auth.uid());

create policy "anamneses_insert_own"
  on anamneses for insert
  with check (usuario_id = auth.uid());

-- Mesmo padrão de `metricas_saude_diarias_select_profissional_vinculado`
-- (`20260713140000_saneamento_grants_e_unificacao_rls.sql`): só vínculo
-- ATIVO (não `em_carencia`/`pendente`) dá leitura ao profissional. Não há
-- tela no Painel Web usando isso ainda (fora do escopo desta tarefa,
-- restrição explícita), mas a RLS já fica correta para quando existir —
-- consistente com o resto dos dados clínicos deste projeto.
create policy "anamneses_select_profissional_vinculado"
  on anamneses for select
  using (
    exists (
      select 1
      from vinculos_profissional_paciente v
      where v.profissional_id = auth.uid()
        and v.paciente_id = anamneses.usuario_id
        and v.status = 'ativo'
    )
  );

grant select, insert on anamneses to authenticated;

-- ----------------------------------------------------------------------------
-- 2.1 — anamneses_alergias (N:N)
-- ----------------------------------------------------------------------------
create table anamneses_alergias (
  anamnese_id uuid not null references anamneses (id) on delete cascade,
  alergia_id uuid not null references alergias (id) on delete cascade,
  primary key (anamnese_id, alergia_id)
);

alter table anamneses_alergias enable row level security;

create policy "anamneses_alergias_select_own_or_profissional"
  on anamneses_alergias for select
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_alergias.anamnese_id
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

create policy "anamneses_alergias_insert_own"
  on anamneses_alergias for insert
  with check (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_alergias.anamnese_id and a.usuario_id = auth.uid()
    )
  );

create policy "anamneses_alergias_delete_own"
  on anamneses_alergias for delete
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_alergias.anamnese_id and a.usuario_id = auth.uid()
    )
  );

grant select, insert, delete on anamneses_alergias to authenticated;

-- ----------------------------------------------------------------------------
-- 2.2 — anamneses_problemas_saude (N:N)
-- ----------------------------------------------------------------------------
create table anamneses_problemas_saude (
  anamnese_id uuid not null references anamneses (id) on delete cascade,
  problema_saude_id uuid not null references problemas_saude (id) on delete cascade,
  primary key (anamnese_id, problema_saude_id)
);

alter table anamneses_problemas_saude enable row level security;

create policy "anamneses_problemas_saude_select_own_or_profissional"
  on anamneses_problemas_saude for select
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_problemas_saude.anamnese_id
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

create policy "anamneses_problemas_saude_insert_own"
  on anamneses_problemas_saude for insert
  with check (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_problemas_saude.anamnese_id and a.usuario_id = auth.uid()
    )
  );

create policy "anamneses_problemas_saude_delete_own"
  on anamneses_problemas_saude for delete
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_problemas_saude.anamnese_id and a.usuario_id = auth.uid()
    )
  );

grant select, insert, delete on anamneses_problemas_saude to authenticated;

-- ----------------------------------------------------------------------------
-- 2.3 — anamneses_atividades (N:N com atributo minutos_diarios)
-- ----------------------------------------------------------------------------
create table anamneses_atividades (
  anamnese_id uuid not null references anamneses (id) on delete cascade,
  atividade_id smallint not null references tipos_atividades_fisicas (id),
  minutos_diarios int not null check (minutos_diarios > 0 and minutos_diarios <= 1440),
  primary key (anamnese_id, atividade_id)
);

comment on column anamneses_atividades.minutos_diarios is
  'Minutos por dia dedicados a esta modalidade, conforme autodeclarado na anamnese — input do Motor N07 (futuro) junto com tipos_atividades_fisicas.met_estimado. Teto de 1440 (minutos num dia) é só sanidade de digitação, não validação clínica.';

alter table anamneses_atividades enable row level security;

create policy "anamneses_atividades_select_own_or_profissional"
  on anamneses_atividades for select
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_atividades.anamnese_id
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

create policy "anamneses_atividades_insert_own"
  on anamneses_atividades for insert
  with check (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_atividades.anamnese_id and a.usuario_id = auth.uid()
    )
  );

create policy "anamneses_atividades_delete_own"
  on anamneses_atividades for delete
  using (
    exists (
      select 1 from anamneses a
      where a.id = anamneses_atividades.anamnese_id and a.usuario_id = auth.uid()
    )
  );

grant select, insert, delete on anamneses_atividades to authenticated;

-- ----------------------------------------------------------------------------
-- 2.4 — Trigger de versionamento (pedido explícito do fundador)
-- ----------------------------------------------------------------------------
-- BEFORE INSERT: quando o app manda um preenchimento novo com
-- status_vigencia = 'ativo' (o valor padrão da coluna — o app nunca precisa
-- mandar isso explicitamente), qualquer linha 'ativo' pré-existente do MESMO
-- usuário vira 'historico' ANTES do INSERT novo se completar. `security
-- definer` (mesmo padrão de `private.tg_perfis_usuarios_cifrar_pii` e
-- `perfis_usuarios_bloquear_auto_promocao`) é necessário porque a linha
-- ativa antiga pertence ao MESMO usuário que está inserindo — a RLS de
-- `anamneses` não tem policy de UPDATE para `authenticated` (o cliente nunca
-- deveria editar uma anamnese antiga diretamente), então sem
-- `security definer` este UPDATE seria bloqueado pela própria RLS.
--
-- Guard `if new.status_vigencia = 'ativo'`: um INSERT que já chega marcado
-- como 'historico' (não é o caminho do app hoje, mas nada impede uma
-- migration futura de backfill) não deveria apagar a vigência de ninguém.
create or replace function public.anamneses_versionar_status_vigencia()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status_vigencia = 'ativo' then
    update public.anamneses
    set status_vigencia = 'historico'
    where usuario_id = new.usuario_id
      and status_vigencia = 'ativo';
  end if;
  return new;
end;
$$;

create trigger anamneses_trg_versionar
  before insert on anamneses
  for each row
  execute function public.anamneses_versionar_status_vigencia();

comment on trigger anamneses_trg_versionar on anamneses is
  'N09 (RELATÓRIO 20260811_0007): garante no máximo 1 anamnese "ativo" por usuário — a antiga vira "historico" automaticamente quando uma nova é preenchida.';
