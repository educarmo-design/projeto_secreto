-- N06 (RELATÓRIO 20260811_0006) — fecha o CRUD completo do módulo de
-- manutenção do Painel Web: escrita de admin no catálogo de alimentos
-- (revertendo, por instrução explícita do fundador nesta tarefa, a trava
-- deliberada da migration original) e RPCs D2 para a tela de Vínculos.
--
-- ============================================================================
-- Parte 1 — Auditoria de escrita para admin (pedida no CONTEXTO da tarefa)
-- ============================================================================
-- alergias (20260811210000), configuracoes_sistema (20260811210000) e
-- tipos_atividades_fisicas (20260811220000) JÁ tinham policy de INSERT/
-- UPDATE/DELETE para eh_admin() antes desta migration — conferido lendo as
-- migrations, não presumido. Só `alimentos_referencia` (e sua tabela filha
-- `alimentos_medidas_caseiras`, as "porções"/medidas caseiras que o Admin
-- também precisa gerenciar para cadastrar um alimento útil) ainda tinha a
-- trava original de `20260716120000_alimentos_referencia_taco.sql`
-- ("curadoria é migration/service role").
--
-- Esta tarefa pede explicitamente "o Admin precisa conseguir gerenciar o
-- catálogo de alimentos" — reversão intencional e autorizada da decisão
-- anterior, não um bypass silencioso.
--
-- RESSALVA que continua verdadeira e não é resolvida por esta migration
-- (documentada aqui e no componente React): `nome_taco`/`aliases`
-- alimentam `cache_sinonimos_alimentos` (embeddings semânticos usados pela
-- Edge Function `search-food`, `20260727120000_setup_nutricao_semantica.sql`).
-- Um INSERT/UPDATE feito pelo Admin aqui NÃO recalcula o embedding
-- correspondente — o alimento fica utilizável no cálculo de calorias
-- imediatamente, mas só entra na busca semântica por sinônimo depois que o
-- job de re-embed rodar. Fora do escopo desta tarefa (pipeline de
-- embeddings, não tela de CRUD).

create policy "alimentos_referencia_insert_admin"
  on alimentos_referencia for insert
  to authenticated
  with check (eh_admin());

create policy "alimentos_referencia_update_admin"
  on alimentos_referencia for update
  to authenticated
  using (eh_admin())
  with check (eh_admin());

create policy "alimentos_referencia_delete_admin"
  on alimentos_referencia for delete
  to authenticated
  using (eh_admin());

create policy "alimentos_medidas_caseiras_insert_admin"
  on alimentos_medidas_caseiras for insert
  to authenticated
  with check (eh_admin());

create policy "alimentos_medidas_caseiras_update_admin"
  on alimentos_medidas_caseiras for update
  to authenticated
  using (eh_admin())
  with check (eh_admin());

create policy "alimentos_medidas_caseiras_delete_admin"
  on alimentos_medidas_caseiras for delete
  to authenticated
  using (eh_admin());

grant insert, update, delete on alimentos_referencia to authenticated;
grant insert, update, delete on alimentos_medidas_caseiras to authenticated;

-- ============================================================================
-- Parte 2 — RPCs D2 para a tela de Vínculos (prof×usuário)
-- ============================================================================
-- Mesmo padrão de `admin_perfis_seguro` (20260811210000): `security definer`,
-- `set search_path = ''`, decifra nome via `private.pii_decrypt`, escopado a
-- `eh_admin()`. Nenhuma chave PGP chega ao client.

create or replace function public.admin_listar_vinculos()
returns table (
  id uuid,
  profissional_id uuid,
  profissional_nome text,
  paciente_id uuid,
  paciente_nome text,
  status public.status_vinculo,
  tipo_pagador public.tipo_pagador_vinculo,
  tipo_produto public.tipo_produto_vinculo,
  data_inicio date,
  data_saida date,
  fim_carencia date,
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
    v.id,
    v.profissional_id,
    private.pii_decrypt(prof.nome) as profissional_nome,
    v.paciente_id,
    private.pii_decrypt(pac.nome)  as paciente_nome,
    v.status,
    v.tipo_pagador,
    v.tipo_produto,
    v.data_inicio,
    v.data_saida,
    v.fim_carencia,
    v.criado_em
  from public.vinculos_profissional_paciente v
  join public.perfis_usuarios prof on prof.id = v.profissional_id
  join public.perfis_usuarios pac on pac.id = v.paciente_id
  order by v.criado_em desc;
end;
$$;

comment on function public.admin_listar_vinculos() is
  'N06 (RELATÓRIO 20260811_0006): lista todos os vínculos profissional×paciente com nome decifrado (D2) dos dois lados, escopado a admin. Base da tela AdminVinculos.tsx.';

revoke execute on function public.admin_listar_vinculos() from public;
grant execute on function public.admin_listar_vinculos() to authenticated;

-- Encerrar manualmente: mesma lógica de negócio da Edge Function
-- `manage-professional-link` (ação `encerrar_vinculo`) — grava
-- `fim_carencia` como hoje + 30 dias (F.5), idempotente se já encerrado.
-- Só o Admin pode chamar (vinculos_profissional_paciente não tem policy de
-- UPDATE alguma para authenticated — nem para os dois lados do vínculo, que
-- encerram via Edge Function com service_role; esta RPC é a ÚNICA porta de
-- escrita direta em SQL na tabela, e só para admin).
create or replace function public.admin_encerrar_vinculo(p_vinculo_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.eh_admin() then
    raise exception 'Acesso restrito a administradores.';
  end if;

  update public.vinculos_profissional_paciente
  set status = 'encerrado',
      data_saida = current_date,
      fim_carencia = current_date + interval '30 days',
      atualizado_em = now()
  where id = p_vinculo_id
    and status <> 'encerrado';
end;
$$;

comment on function public.admin_encerrar_vinculo(uuid) is
  'N06 (RELATÓRIO 20260811_0006): Admin encerra manualmente um vínculo (mesma regra de fim_carencia de 30 dias da Edge Function manage-professional-link). Idempotente — encerrar um vínculo já encerrado não faz nada.';

revoke execute on function public.admin_encerrar_vinculo(uuid) from public;
grant execute on function public.admin_encerrar_vinculo(uuid) to authenticated;

-- Aprovar manualmente um vínculo `pendente` (o convite existe, mas o
-- paciente ainda não aceitou pelo app) — mesma transição de
-- `aceitarVinculo` na Edge Function: `data_inicio` passa a ser o dia da
-- aprovação, não o dia do convite original.
create or replace function public.admin_aprovar_vinculo(p_vinculo_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.eh_admin() then
    raise exception 'Acesso restrito a administradores.';
  end if;

  update public.vinculos_profissional_paciente
  set status = 'ativo',
      data_inicio = current_date,
      atualizado_em = now()
  where id = p_vinculo_id
    and status = 'pendente';
end;
$$;

comment on function public.admin_aprovar_vinculo(uuid) is
  'N06 (RELATÓRIO 20260811_0006): Admin aprova manualmente um vínculo pendente (pendente -> ativo), mesma regra de data_inicio da Edge Function manage-professional-link. Sem efeito se o vínculo não estiver pendente (ex.: já ativo/encerrado).';

revoke execute on function public.admin_aprovar_vinculo(uuid) from public;
grant execute on function public.admin_aprovar_vinculo(uuid) to authenticated;
