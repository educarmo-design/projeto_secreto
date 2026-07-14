-- Sala de Espera — onboarding de profissionais com aprovação por Admin.
--
-- Hoje `perfis_usuarios_insert_own`/`perfis_usuarios_update_own`
-- (20260706191827_core_schema.sql) só checam `auth.uid() = id`, sem
-- restrição de COLUNA — ou seja, qualquer usuário autenticado já poderia se
-- autopromover a profissional só fazendo
-- `update perfis_usuarios set eh_profissional = true where id = auth.uid()`.
-- Isso nunca foi explorado porque nenhuma tela do painel web fazia esse
-- update, mas com a UI de "Solicitar Acesso" prestes a existir (que SIM
-- escreve na própria linha durante o cadastro), a lacuna passa a ser
-- alcançável a partir do próprio formulário público. Esta migration fecha
-- essa lacuna ao mesmo tempo em que introduz o fluxo de aprovação.

-- ============================================================================
-- 1. Enum de status + colunas novas
-- ============================================================================
create type status_aprovacao_usuario as enum ('pendente', 'aprovado', 'rejeitado');

alter table perfis_usuarios
  add column status_aprovacao status_aprovacao_usuario not null default 'pendente',
  add column is_admin boolean not null default false;

-- Backfill: contas que já operam como profissional hoje (provisionadas à mão,
-- de antes deste fluxo existir) não podem ficar retroativamente bloqueadas
-- por um status 'pendente' que elas nunca solicitaram.
update perfis_usuarios
  set status_aprovacao = 'aprovado'
  where eh_profissional = true;

-- ============================================================================
-- 2. Trigger: nenhum usuário se autopromove, nem editando a própria linha
-- ============================================================================
-- `with check` de RLS não compara NEW contra OLD (não tem como expressar "essa
-- coluna não pode mudar" só com `auth.uid() = id`), então a barreira real tem
-- que ser um trigger BEFORE UPDATE: se quem está fazendo a escrita não é
-- admin, as 3 colunas que concedem privilégio voltam à força para o valor que
-- já estava salvo, não importa o que o payload do UPDATE tentou enviar. Isso
-- vale tanto para o dono editando a própria linha quanto para qualquer futura
-- policy que venha a permitir tocar a linha de outro — a trava não depende de
-- qual policy liberou o UPDATE.
--
-- `security definer` é necessário para o `select is_admin` de dentro da
-- função conseguir ler a própria linha do ator sem depender de qual policy de
-- SELECT está ativa no momento (evita qualquer risco de recursão de RLS).
create or replace function perfis_usuarios_bloquear_auto_promocao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ator uuid := auth.uid();
  ator_eh_admin boolean;
begin
  -- `auth.uid()` só existe quando a escrita passou pelo PostgREST com um JWT
  -- (é dali que a policy de RLS lê o ator). Uma sessão direta no Postgres —
  -- psql, o SQL Editor do Supabase Studio, uma migration — não carrega esse
  -- JWT, então `auth.uid()` vem NULL: é o próprio operador do banco escrevendo,
  -- não um usuário da API. Esse é justamente o caminho documentado para
  -- bootstrapar o primeiro Admin (`update perfis_usuarios set is_admin =
  -- true ...` rodado à mão) — se a trava tratasse "sem ator" como "não é
  -- admin", ela reverteria o próprio bootstrap e ninguém conseguiria virar
  -- Admin nunca. A trava é só contra o caminho HTTP/API de um usuário
  -- autenticado não-admin.
  if ator is null then
    return new;
  end if;

  select is_admin into ator_eh_admin
  from perfis_usuarios
  where id = ator;

  if coalesce(ator_eh_admin, false) then
    return new;
  end if;

  new.eh_profissional := old.eh_profissional;
  new.status_aprovacao := old.status_aprovacao;
  new.is_admin := old.is_admin;
  return new;
end;
$$;

create trigger perfis_usuarios_trg_bloquear_auto_promocao
  before update on perfis_usuarios
  for each row execute function perfis_usuarios_bloquear_auto_promocao();

-- ============================================================================
-- 3. INSERT: mesma trava, aplicada no cadastro inicial
-- ============================================================================
-- O trigger acima só existe para UPDATE (precisa de um OLD para reverter). No
-- INSERT não há OLD — a única defesa possível é o próprio `with check`
-- recusar a linha se ela já nascer com privilégio. A UI de "Solicitar Acesso"
-- nunca precisa enviar essas 3 colunas (todas têm o default seguro), então
-- isto não quebra o cadastro legítimo — só barra um payload adulterado.
drop policy "perfis_usuarios_insert_own" on perfis_usuarios;

create policy "perfis_usuarios_insert_own"
  on perfis_usuarios for insert
  with check (
    auth.uid() = id
    and eh_profissional = false
    and status_aprovacao = 'pendente'
    and is_admin = false
  );

-- ============================================================================
-- 4. Admin enxerga e decide sobre solicitações de outros usuários
-- ============================================================================
-- Tentativa inicial (revertida após validar contra um banco local): embutir
-- `exists (select 1 from perfis_usuarios me where me.id = auth.uid() and
-- me.is_admin = true)` diretamente no `using`/`with check` de uma policy de
-- `perfis_usuarios` sobre a PRÓPRIA `perfis_usuarios` — Postgres detecta isso
-- como recursão infinita (`42P17`) e a query falha com HTTP 500, mesmo a
-- policy `_select_own` já liberando essa mesma linha por outro caminho. RLS
-- não faz "short-circuit" por policy que já autorizaria a linha: cada
-- subselect contra a tabela reavalia TODAS as policies da tabela de novo.
--
-- A saída padrão do Postgres/Supabase para "checar uma coluna da própria
-- linha do ator sem reentrar na RLS" é indireção por função `security
-- definer` — executa com o dono da função (postgres), que não está sujeito a
-- RLS (a tabela não tem `force row level security`). Mesmo truque que o
-- trigger da seção 2 já usa com sucesso.
create or replace function eh_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select coalesce(
    (select is_admin from perfis_usuarios where id = auth.uid()),
    false
  );
$$;

create policy "perfis_usuarios_select_admin"
  on perfis_usuarios for select
  using (eh_admin());

create policy "perfis_usuarios_update_admin"
  on perfis_usuarios for update
  using (eh_admin())
  with check (eh_admin());
