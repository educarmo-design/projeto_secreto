-- Lookup de e-mail -> UUID para o convite B2B (painel web do profissional).
--
-- Problema: `manage-professional-link`/`criar_vinculo` exige `paciente_id`
-- (UUID) — mas o profissional, no mundo real, só conhece o e-mail do
-- paciente. E `perfis_usuarios.email` não serve para essa busca: ele sai
-- cifrado AES-256-GCM no cliente antes do insert (mesmo padrão de
-- `nome`/`telefone` — ver `cadastro_controller.dart`), então uma comparação
-- `where email = <texto que o profissional digitou>` nunca bateria com o
-- ciphertext guardado. O e-mail em texto plano só existe em `auth.users`
-- (gerido pelo GoTrue, necessário para login/recuperação de senha).
--
-- `auth.users` não é exposta pelo PostgREST e não deve ser: por trás dela
-- também tem `encrypted_password`, tokens de sessão, etc. Esta função é o
-- único portal — devolve SÓ o `id`, nunca a linha inteira, e só é chamável
-- pela service_role (nunca por `anon`/`authenticated`), então mesmo que
-- existisse um endpoint público capaz de invocar funções, o painel web e o
-- app não teriam privilégio de executar isto diretamente. Só a Edge Function
-- `manage-professional-link` (que já segura a service role) pode chamá-la —
-- ver `resolverPacienteIdPorEmail` em
-- supabase/functions/manage-professional-link/index.ts.
--
-- Risco residual aceito conscientemente: isto é um oráculo de existência de
-- e-mail (permite descobrir se um e-mail está cadastrado). Mitigado por
-- (a) só um profissional autenticado e com `eh_profissional = true` consegue
-- chegar a este caminho (checagem já existente em `criarVinculo`), não é uma
-- rota anônima; (b) o critério de aceite explicitamente pede a mensagem
-- "Paciente não encontrado" distinta — é uma troca deliberada de UX (o
-- profissional precisa saber se digitou o e-mail errado) por um oráculo
-- restrito a uma população pequena e já autenticada/autorizada, não o público
-- geral.
create or replace function resolver_usuario_id_por_email(email_busca text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from auth.users where lower(email) = lower(email_busca) limit 1;
$$;

-- `security definer` roda com o privilégio de quem CRIOU a função (o papel de
-- migração, que tem acesso a auth.users), não de quem chama — é assim que a
-- service_role, que por si só não teria select em auth.users, consegue
-- invocar isto. `set search_path = ''` fecha o vetor clássico de sequestro de
-- search_path em funções SECURITY DEFINER: com o path vazio, só schemas
-- explicitamente qualificados (aqui, `auth.users`) resolvem — pg_catalog
-- continua implicitamente disponível para `lower()`.
revoke execute on function resolver_usuario_id_por_email(text) from public;
grant execute on function resolver_usuario_id_por_email(text) to service_role;
