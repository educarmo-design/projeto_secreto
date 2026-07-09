-- medicamentos_usuario: módulo "Medicamentos do Dia" do Perfil 2 (Guardião
-- Clínico / Sênior). Não existia nenhuma tabela de medicamentos até aqui —
-- resultados_exames (Onda 1.5) cobre exames, mas nada cobria prescrições
-- recorrentes.
--
-- ultima_dose_tomada_em fica na própria linha (em vez de uma tabela de log
-- separada) porque o dashboard só precisa responder "já tomei a dose de
-- hoje?" — comparar sua data com a data de hoje é suficiente; um histórico
-- completo de doses fica fora do escopo desta ONDA.

create table medicamentos_usuario (
  id uuid primary key default gen_random_uuid(),
  usuario_id_anonimo uuid not null references auth.users (id) on delete cascade,
  nome_medicamento text not null,
  dosagem text,
  horario time not null,
  ativo boolean not null default true,
  ultima_dose_tomada_em timestamptz,
  criado_em timestamptz not null default now()
);

create index idx_medicamentos_usuario_usuario_horario
  on medicamentos_usuario (usuario_id_anonimo, horario);

alter table medicamentos_usuario enable row level security;

create policy "medicamentos_usuario_select_own"
  on medicamentos_usuario for select
  using (auth.uid() = usuario_id_anonimo);

create policy "medicamentos_usuario_insert_own"
  on medicamentos_usuario for insert
  with check (auth.uid() = usuario_id_anonimo);

create policy "medicamentos_usuario_update_own"
  on medicamentos_usuario for update
  using (auth.uid() = usuario_id_anonimo)
  with check (auth.uid() = usuario_id_anonimo);
