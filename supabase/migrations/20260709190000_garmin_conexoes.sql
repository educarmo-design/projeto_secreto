-- ONDA 3 — Garmin Gateway (supabase/functions/garmin-gateway/): armazena o
-- vínculo OAuth 1.0a por aluno com a Garmin Training API.
--
-- Sem esta tabela, garmin-gateway/index.ts não teria como saber qual
-- garmin_user_id/access_token corresponde a um `paciente_id_anonimo` — é
-- exatamente o que a Ação 2 (agendar na agenda do relógio) precisa para
-- saber ONDE agendar, e o que falha defensivamente com HTTP 422 quando o
-- aluno ainda não conectou a própria conta.
--
-- O fluxo que POPULA esta tabela (o consentimento OAuth 1.0a
-- three-legged do lado do aluno — abrir o consentimento da Garmin, trocar
-- o request token pelo access token) fica no app mobile e está fora do
-- escopo desta migration; aqui só se cria a tabela onde esse fluxo,
-- quando existir, vai escrever.
--
-- access_token/access_token_secret ficam em texto plano — diferente de
-- nome/telefone no app mobile (que saem como ciphertext AES-256-GCM via
-- CryptoStorageService) porque o modelo de ameaça é outro: esta linha
-- nunca é lida por nenhum cliente, só pela service role key dentro da Edge
-- Function (que roda inteiramente no servidor) — não há binário/APK do
-- qual esse valor possa ser extraído por engenharia reversa, que era
-- exatamente o risco que a criptografia client-side do app mobile existe
-- para mitigar. RLS abaixo ainda restringe a leitura da própria linha ao
-- próprio usuário (para uma futura tela de "gerenciar minhas conexões");
-- a Edge Function em si usa a service role, que ignora RLS.
create table garmin_conexoes (
  usuario_id_anonimo uuid primary key references auth.users (id) on delete cascade,
  garmin_user_id text not null,
  access_token text not null,
  access_token_secret text not null,
  conectado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

alter table garmin_conexoes enable row level security;

create policy "garmin_conexoes_select_own"
  on garmin_conexoes for select
  using (auth.uid() = usuario_id_anonimo);

create policy "garmin_conexoes_insert_own"
  on garmin_conexoes for insert
  with check (auth.uid() = usuario_id_anonimo);

create policy "garmin_conexoes_update_own"
  on garmin_conexoes for update
  using (auth.uid() = usuario_id_anonimo)
  with check (auth.uid() = usuario_id_anonimo);
