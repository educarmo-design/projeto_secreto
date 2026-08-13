-- N06 (RELATÓRIO 20260811_0005) — catálogos de manutenção (alergias,
-- configurações do sistema) + a RPC de decifra D2 escopada a admin que o
-- spike anterior (20260811_0004) identificou como o gap real por trás de
-- AdminDashboard.tsx mostrando ciphertext em vez de nome/e-mail.

-- ============================================================================
-- 1. Catálogo de alergias
-- ============================================================================
-- Mesmo padrão de tipos_atividades_fisicas (20260811160000): catálogo
-- público de leitura, escrita só admin.
create table if not exists alergias (
  id uuid primary key default gen_random_uuid(),
  nome_codigo text not null unique,
  nome_exibicao text not null,
  descricao text
);

comment on table alergias is
  'Catálogo de alergias conhecidas — N06, RELATÓRIO 20260811_0005. Populado inicialmente pela tela AdminAlergias.tsx (sem seed fixo nesta migration: ao contrário de tipos_atividades_fisicas, não há uma lista oficial "comum a Android/iOS" para alergias — o catálogo nasce vazio e cresce pela tela administrativa).';

alter table alergias enable row level security;

create policy "alergias_select_all" on alergias for select to authenticated using (true);
create policy "alergias_insert_admin" on alergias for insert with check (eh_admin());
create policy "alergias_update_admin" on alergias for update using (eh_admin()) with check (eh_admin());
create policy "alergias_delete_admin" on alergias for delete using (eh_admin());

grant select on alergias to authenticated;
grant insert, update, delete on alergias to authenticated;

-- ============================================================================
-- 2. Associação usuário x alergia (N:N)
-- ============================================================================
create table if not exists usuario_alergias (
  usuario_id uuid not null references auth.users (id) on delete cascade,
  alergia_id uuid not null references alergias (id) on delete cascade,
  observacao text,
  criado_em timestamptz not null default now(),
  primary key (usuario_id, alergia_id)
);

comment on table usuario_alergias is
  'Quais alergias cada usuário declarou ter — N:N usuário x catálogo. N06, RELATÓRIO 20260811_0005.';

alter table usuario_alergias enable row level security;

-- Dono gerencia as próprias alergias; admin vê/gerencia todas (suporte,
-- auditoria) — mesmo padrão de usuario_papeis acima nesta mesma tarefa.
create policy "usuario_alergias_select_own_or_admin"
  on usuario_alergias for select
  using (auth.uid() = usuario_id or eh_admin());
create policy "usuario_alergias_insert_own_or_admin"
  on usuario_alergias for insert
  with check (auth.uid() = usuario_id or eh_admin());
create policy "usuario_alergias_delete_own_or_admin"
  on usuario_alergias for delete
  using (auth.uid() = usuario_id or eh_admin());

grant select, insert, delete on usuario_alergias to authenticated;

-- ============================================================================
-- 3. Configurações do sistema
-- ============================================================================
-- ACHADO DO SPIKE ANTERIOR (20260811_0004): não há, em nenhum PRD/Adendo
-- acessível, uma definição do que "Configurações" deveria conter — esta
-- migration cria só a INFRAESTRUTURA (chave/valor, o desenho mais neutro
-- possível), não presume nenhum parâmetro de negócio específico. As 2 linhas
-- de seed abaixo são só para a tela AdminConfiguracoes.tsx ter algo pra
-- exibir/editar no dia 1 — não são uma decisão de produto, e devem ser
-- revistas/substituídas assim que o fundador definir o escopo real.
create table if not exists configuracoes_sistema (
  chave text primary key,
  valor text,
  descricao text,
  atualizado_em timestamptz not null default now()
);

comment on table configuracoes_sistema is
  'Configurações globais do sistema, chave/valor — N06, RELATÓRIO 20260811_0005. Escopo de negócio AINDA NÃO DEFINIDO pelo fundador (ver spike 20260811_0004); infraestrutura genérica de propósito, para não travar o N06 numa decisão de produto pendente.';

alter table configuracoes_sistema enable row level security;

-- Admin-only (select+write): sem saber o que vai morar aqui, o padrão mais
-- seguro é não expor a authenticated em geral — fácil de abrir depois
-- (`for select to authenticated using (true)`) se algum valor precisar ser
-- lido pelo app/painel sem ser admin (ex.: uma feature flag pública).
create policy "configuracoes_sistema_select_admin" on configuracoes_sistema for select using (eh_admin());
create policy "configuracoes_sistema_insert_admin" on configuracoes_sistema for insert with check (eh_admin());
create policy "configuracoes_sistema_update_admin" on configuracoes_sistema for update using (eh_admin()) with check (eh_admin());
create policy "configuracoes_sistema_delete_admin" on configuracoes_sistema for delete using (eh_admin());

grant select, insert, update, delete on configuracoes_sistema to authenticated;

insert into configuracoes_sistema (chave, valor, descricao) values
  ('manutencao_programada', 'false', 'Quando "true", o painel/app deveriam exibir aviso de manutenção (uso ainda não ligado a nenhuma tela — placeholder de exemplo).'),
  ('idade_minima_anos', '18', 'Espelha a CHECK constraint perfis_usuarios_maioridade (N03) — texto, não é o que de fato aplica a trava; existe aqui só para exibição/consulta pela tela de configurações.')
on conflict (chave) do nothing;

-- ============================================================================
-- 4. RPC de decifra D2 escopada a admin
-- ============================================================================
-- Corrige o gap concreto do spike anterior: AdminDashboard.tsx faz
-- `select nome, email from perfis_usuarios` direto, que desde
-- 20260730160000 devolve só ciphertext. Mesmo padrão de meu_perfil_seguro()
-- (SECURITY DEFINER, search_path='', chama private.pii_decrypt já
-- existente), mas escopado por eh_admin() em vez de auth.uid() — e
-- devolvendo MÚLTIPLAS linhas, com filtro opcional por status_aprovacao.
--
-- Restrição de segurança (Regra desta tarefa): nenhuma chave PGP sai do
-- servidor — a função só devolve TEXTO JÁ DECIFRADO como colunas normais de
-- retorno, exatamente como qualquer outra RPC; a chave em si nunca aparece
-- em nenhum payload, nunca é passada como argumento nem exposta em log.
create or replace function public.admin_perfis_seguro(p_status_aprovacao text default null)
returns table (
  id uuid,
  nome text,
  telefone text,
  email text,
  nickname text,
  eh_profissional boolean,
  tipo_profissional public.tipo_profissional_saude,
  registro_profissional text,
  status_aprovacao public.status_aprovacao_usuario,
  is_admin boolean,
  data_nascimento date,
  idade int,
  criado_em timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.eh_admin() then
    raise exception 'Acesso restrito a administradores.';
  end if;

  return query
  select
    p.id,
    private.pii_decrypt(p.nome)     as nome,
    private.pii_decrypt(p.telefone) as telefone,
    private.pii_decrypt(p.email)    as email,
    p.nickname,
    p.eh_profissional,
    p.tipo_profissional,
    p.registro_profissional,
    p.status_aprovacao,
    p.is_admin,
    p.data_nascimento,
    public.calcular_idade(p.data_nascimento) as idade,
    p.criado_em
  from public.perfis_usuarios p
  where p_status_aprovacao is null
     or p.status_aprovacao = p_status_aprovacao::public.status_aprovacao_usuario;
end;
$$;

comment on function public.admin_perfis_seguro(text) is
  'N06 (RELATÓRIO 20260811_0005): lista perfis com PII decifrada (nome/telefone/email), escopada a admin (eh_admin()) — substitui o select direto quebrado de AdminDashboard.tsx desde o D2 (20260730160000). p_status_aprovacao filtra por status; null lista todos. Chave PGP nunca sai do servidor: só o texto já decifrado volta como coluna de retorno.';

revoke execute on function public.admin_perfis_seguro(text) from public;
grant execute on function public.admin_perfis_seguro(text) to authenticated;

-- ============================================================================
-- GRANT (Parte 0.10): nenhum adicional necessário em perfis_usuarios — a RPC
-- roda SECURITY DEFINER (dono = postgres), não depende de GRANT/RLS de
-- perfis_usuarios para o chamador authenticated.
