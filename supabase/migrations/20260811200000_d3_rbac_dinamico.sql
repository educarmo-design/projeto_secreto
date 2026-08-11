-- D3 (RELATÓRIO 20260811_0005, ajuste do fundador) — Matriz de Permissões
-- DINÂMICA, em banco (RBAC M:N), não um documento estático. Substitui o
-- gap identificado no spike anterior (20260811_0004: "não existe artefato
-- central, autorização espalhada em ~65 create policy") por uma estrutura
-- que o Painel Web consegue LER e EDITAR em tempo real.
--
-- Importante: este RBAC novo é ADITIVO, não substitui o gate binário
-- existente (`is_admin`/`eh_profissional`/`tipo_profissional` em
-- perfis_usuarios, usados por `signInProfissional`/toda a RLS já em
-- produção). Migrar login/RLS existentes para depender só do RBAC novo é
-- uma mudança de escopo maior, fora desta tarefa — aqui só criamos a
-- estrutura + backfill dos papéis correspondentes ao estado atual, pronta
-- pra uso incremental (ex.: uma tela nova do N06 pode checar `tem_permissao`
-- desde já, sem esperar a migração completa do resto).

-- ============================================================================
-- 1. Tabelas
-- ============================================================================
create table if not exists papeis (
  id uuid primary key default gen_random_uuid(),
  nome_codigo text not null unique,
  nome_exibicao text not null
);

comment on table papeis is
  'Catálogo de papéis do RBAC dinâmico (D3) — RELATÓRIO 20260811_0005. Independente do enum tipo_profissional_saude (esse continua sendo o campo do cadastro/login antigo); nome_codigo aqui é livre, em minúsculas, sem acento.';

create table if not exists permissoes (
  id uuid primary key default gen_random_uuid(),
  modulo text not null,
  acao_codigo text not null,
  descricao text,
  unique (modulo, acao_codigo)
);

comment on table permissoes is
  'Catálogo de permissões granulares (D3) — cada linha é uma capacidade concreta do sistema (ex.: modulo=''alimentos'', acao_codigo=''criar''). O código completo usado por tem_permissao() é modulo || ''.'' || acao_codigo (ex.: ''alimentos.criar'').';

create table if not exists papeis_permissoes (
  papel_id uuid not null references papeis (id) on delete cascade,
  permissao_id uuid not null references permissoes (id) on delete cascade,
  primary key (papel_id, permissao_id)
);

comment on table papeis_permissoes is
  'A MATRIZ em si: quais permissões cada papel tem habilitadas. Escrita só via admin_atualizar_permissao_papel() — sem policy de INSERT/DELETE direta para authenticated (ver seção 4).';

create table if not exists usuario_papeis (
  usuario_id uuid not null references auth.users (id) on delete cascade,
  papel_id uuid not null references papeis (id) on delete cascade,
  primary key (usuario_id, papel_id)
);

comment on table usuario_papeis is
  'Quais papéis cada usuário acumula — M:N de verdade (um usuário pode ter vários papéis; um papel serve vários usuários), fechando o gap N01 apontado no spike anterior (lá só havia is_admin/eh_profissional, colunas fixas, não M:N).';

create index if not exists idx_usuario_papeis_usuario on usuario_papeis (usuario_id);
create index if not exists idx_papeis_permissoes_papel on papeis_permissoes (papel_id);

-- ============================================================================
-- 2. Seed — papéis padrão
-- ============================================================================
insert into papeis (nome_codigo, nome_exibicao) values
  ('admin', 'Administrador'),
  ('medico', 'Médico'),
  ('nutricionista', 'Nutricionista'),
  ('personal', 'Personal Trainer'),
  ('fisioterapeuta', 'Fisioterapeuta'),
  ('atleta', 'Atleta')
on conflict (nome_codigo) do nothing;

-- ============================================================================
-- 3. Seed — permissões por módulo
-- ============================================================================
insert into permissoes (modulo, acao_codigo, descricao) values
  ('usuarios', 'visualizar', 'Ver a lista de usuários (atletas) cadastrados'),
  ('usuarios', 'editar', 'Editar dados cadastrais de um usuário'),
  ('profissionais', 'visualizar', 'Ver a lista de profissionais cadastrados'),
  ('profissionais', 'aprovar', 'Aprovar ou rejeitar solicitação de acesso de profissional'),
  ('profissionais', 'editar', 'Editar dados cadastrais de um profissional'),
  ('vinculos', 'visualizar', 'Ver vínculos profissional-paciente'),
  ('atividades_fisicas', 'visualizar', 'Ver o dicionário de modalidades de atividade física'),
  ('atividades_fisicas', 'criar', 'Criar modalidade nova no dicionário'),
  ('atividades_fisicas', 'editar', 'Editar modalidade existente'),
  ('atividades_fisicas', 'excluir', 'Remover modalidade do dicionário'),
  ('alergias', 'visualizar', 'Ver o catálogo de alergias'),
  ('alergias', 'criar', 'Criar alergia nova no catálogo'),
  ('alergias', 'editar', 'Editar alergia existente'),
  ('alergias', 'excluir', 'Remover alergia do catálogo'),
  ('alimentos', 'visualizar', 'Ver o catálogo de alimentos (TACO)'),
  ('alimentos', 'criar', 'Criar alimento novo no catálogo'),
  ('alimentos', 'editar', 'Editar alimento existente'),
  ('alimentos', 'excluir', 'Remover alimento do catálogo'),
  ('configuracoes', 'visualizar', 'Ver as configurações do sistema'),
  ('configuracoes', 'editar', 'Editar configurações do sistema'),
  ('telemetria', 'visualizar', 'Ver métricas de telemetria de um paciente vinculado'),
  ('permissoes', 'gerenciar', 'Editar a própria Matriz de Permissões (habilitar/desabilitar papel x permissão)')
on conflict (modulo, acao_codigo) do nothing;

-- ============================================================================
-- 4. RLS
-- ============================================================================
alter table papeis enable row level security;
alter table permissoes enable row level security;
alter table papeis_permissoes enable row level security;
alter table usuario_papeis enable row level security;

-- papeis/permissoes: catálogo, leitura restrita a admin (só a tela
-- AdminMatrizPermissoes usa isto hoje; nada impede abrir para todo
-- authenticated no futuro se alguma tela precisar exibir nome_exibicao).
create policy "papeis_select_admin" on papeis for select using (eh_admin());
create policy "papeis_insert_admin" on papeis for insert with check (eh_admin());
create policy "papeis_update_admin" on papeis for update using (eh_admin()) with check (eh_admin());
create policy "papeis_delete_admin" on papeis for delete using (eh_admin());

create policy "permissoes_select_admin" on permissoes for select using (eh_admin());
create policy "permissoes_insert_admin" on permissoes for insert with check (eh_admin());
create policy "permissoes_update_admin" on permissoes for update using (eh_admin()) with check (eh_admin());
create policy "permissoes_delete_admin" on permissoes for delete using (eh_admin());

-- papeis_permissoes: SELECT admin (a tela lê a matriz inteira direto);
-- SEM policy de INSERT/UPDATE/DELETE para authenticated — toda escrita
-- passa por admin_atualizar_permissao_papel() (SECURITY DEFINER, ignora
-- RLS por rodar como dono da tabela), nunca um UPDATE/INSERT direto do
-- cliente. Mesmo princípio de vinculos_profissional_paciente
-- (20260713170000): a tabela mais sensível do RBAC não tem porta de
-- escrita direta nenhuma.
create policy "papeis_permissoes_select_admin" on papeis_permissoes for select using (eh_admin());

-- usuario_papeis: um usuário pode ver os PRÓPRIOS papéis; admin vê/edita
-- todos (a tela de atribuir papel a usuário, se/quando existir, usa isto).
create policy "usuario_papeis_select_own_or_admin"
  on usuario_papeis for select
  using (auth.uid() = usuario_id or eh_admin());
create policy "usuario_papeis_insert_admin" on usuario_papeis for insert with check (eh_admin());
create policy "usuario_papeis_update_admin" on usuario_papeis for update using (eh_admin()) with check (eh_admin());
create policy "usuario_papeis_delete_admin" on usuario_papeis for delete using (eh_admin());

grant select, insert, update, delete on papeis, permissoes, usuario_papeis to authenticated;
-- papeis_permissoes: só select — sem insert/update/delete pra authenticated
-- de propósito (ver comentário da policy acima). Toda escrita passa por
-- admin_atualizar_permissao_papel() (SECURITY DEFINER, roda como dono da
-- tabela — não precisa de GRANT de escrita para authenticated).
grant select on papeis_permissoes to authenticated;

-- ============================================================================
-- 5. Backfill — pontes do gate binário antigo pros papéis novos
-- ============================================================================
-- Não migra login/RLS existentes (fora do escopo desta tarefa — ver
-- cabeçalho), só garante que quem já é admin/profissional aprovado no
-- modelo antigo já aparece com o papel correspondente marcado na Matriz,
-- em vez dela nascer vazia. Idempotente (on conflict do nothing).
insert into usuario_papeis (usuario_id, papel_id)
select p.id, papel.id
from perfis_usuarios p
join papeis papel on papel.nome_codigo = 'admin'
where p.is_admin = true
on conflict do nothing;

insert into usuario_papeis (usuario_id, papel_id)
select p.id, papel.id
from perfis_usuarios p
join papeis papel on papel.nome_codigo = case p.tipo_profissional
  when 'Medico' then 'medico'
  when 'Nutricionista' then 'nutricionista'
  when 'Personal_Trainer' then 'personal'
  when 'Fisioterapeuta' then 'fisioterapeuta'
  else null
end
where p.eh_profissional = true
  and p.status_aprovacao = 'aprovado'
  and p.tipo_profissional is not null
on conflict do nothing;

-- ============================================================================
-- 6. RPCs
-- ============================================================================

-- tem_permissao: STABLE + SECURITY DEFINER (ignora RLS de propósito — um
-- usuário comum precisa conseguir checar "eu tenho X?" mesmo sem SELECT
-- direto em usuario_papeis/papeis_permissoes/permissoes). Só devolve um
-- boolean, nunca dado de outra pessoa: não há risco de vazamento em expor
-- isso amplamente, é o mesmo nível de sensibilidade de eh_admin().
create or replace function public.tem_permissao(p_usuario_id uuid, p_permissao_codigo text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.usuario_papeis up
    join public.papeis_permissoes pp on pp.papel_id = up.papel_id
    join public.permissoes perm on perm.id = pp.permissao_id
    where up.usuario_id = p_usuario_id
      and (perm.modulo || '.' || perm.acao_codigo) = p_permissao_codigo
  );
$$;

comment on function public.tem_permissao(uuid, text) is
  'D3 (RELATÓRIO 20260811_0005): true se p_usuario_id tem, por qualquer papel que acumule, a permissão p_permissao_codigo (formato ''modulo.acao'', ex.: ''alimentos.criar''). SECURITY DEFINER de propósito — não depende do chamador ter SELECT nas tabelas do RBAC.';

revoke execute on function public.tem_permissao(uuid, text) from public;
grant execute on function public.tem_permissao(uuid, text) to authenticated;

-- admin_atualizar_permissao_papel: ÚNICA porta de escrita de
-- papeis_permissoes. Checa eh_admin() explicitamente (não confia só na
-- ausência de policy de INSERT/DELETE — defesa em profundidade, mesmo
-- padrão de admin_perfis_seguro/outras RPCs administrativas deste projeto).
create or replace function public.admin_atualizar_permissao_papel(
  p_papel_id uuid,
  p_permissao_id uuid,
  p_habilitado boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.eh_admin() then
    raise exception 'Apenas administradores podem alterar a Matriz de Permissões.';
  end if;

  if p_habilitado then
    insert into public.papeis_permissoes (papel_id, permissao_id)
    values (p_papel_id, p_permissao_id)
    on conflict (papel_id, permissao_id) do nothing;
  else
    delete from public.papeis_permissoes
    where papel_id = p_papel_id and permissao_id = p_permissao_id;
  end if;
end;
$$;

comment on function public.admin_atualizar_permissao_papel(uuid, uuid, boolean) is
  'D3 (RELATÓRIO 20260811_0005): habilita (p_habilitado=true) ou desabilita (false) uma permissão para um papel — a ação de toggle da tela AdminMatrizPermissoes.tsx. Lança exceção se o chamador não for admin (checagem no SERVIDOR, não confia no roteamento do painel).';

revoke execute on function public.admin_atualizar_permissao_papel(uuid, uuid, boolean) from public;
grant execute on function public.admin_atualizar_permissao_papel(uuid, uuid, boolean) to authenticated;
