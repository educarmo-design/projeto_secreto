-- N44 (fechamento) — auditoria de segurança, Parte 6 / decisão 97.
--
-- ACHADO (confirmado em produção em 2026-11-20): `resolver_usuario_id_por_email`
-- (SECURITY DEFINER, lê `auth.users`) era executável pelo papel `anon`. Qualquer
-- pessoa com a chave PUBLICÁVEL — que é pública por desenho, vai no bundle do
-- painel e no app — chamava `POST /rest/v1/rpc/resolver_usuario_id_por_email` e
-- recebia o UUID do usuário para qualquer e-mail cadastrado (e `null` para um
-- inexistente): enumeração de contas + vazamento de identificador.
--
-- CAUSA: a migration 20260713210000 fazia `revoke execute ... from public`,
-- mas o Supabase concede EXECUTE a `anon` e `authenticated` por DEFAULT
-- PRIVILEGES (grants explícitos aos papéis, não via PUBLIC). `revoke from
-- public` não remove esses grants, então a intenção documentada naquela
-- migration ("só chamável pela service_role") nunca foi verdadeira.
--
-- CORREÇÃO:
--   1) `resolver_usuario_id_por_email`: revoga de PUBLIC, anon e authenticated;
--      mantém só service_role (único chamador legítimo: a Edge Function
--      `manage-professional-link`, que usa a chave secreta).
--   2) RPCs que só fazem sentido com sessão (já validam `auth.uid()` /
--      `eh_admin()` no corpo): revoga de `anon`. Defesa em profundidade — o
--      corpo continua sendo a barreira de autorização; isto só impede que quem
--      não está logado sequer chegue lá. `authenticated` segue com EXECUTE:
--      nenhum chamador legítimo muda (o app e o painel só chamam logados).
--
-- DE PROPÓSITO NÃO TOCADAS (uma revogação aqui poderia quebrar RLS):
--   `eh_admin` — é chamada por policies com roles {public} (anon as avalia);
--   `tem_permissao`, `meu_perfil_seguro`, `validar_macro_personalizado`,
--   `match_alimentos`, `calcular_idade` e as funções de trigger. Ficam como
--   pendência registrada no log 20261120_0003 (mover RPCs administrativas para
--   fora do schema exposto é refatoração própria — decisão 97).
--
-- Sem tabela nova: nada de RLS/policy a criar. Idempotente (REVOKE/GRANT).

revoke execute on function public.resolver_usuario_id_por_email(text) from public;
revoke execute on function public.resolver_usuario_id_por_email(text) from anon;
revoke execute on function public.resolver_usuario_id_por_email(text) from authenticated;
grant  execute on function public.resolver_usuario_id_por_email(text) to service_role;

revoke execute on function public.admin_aprovar_vinculo(uuid) from public, anon;
revoke execute on function public.admin_atualizar_permissao_papel(uuid, uuid, boolean) from public, anon;
revoke execute on function public.admin_encerrar_vinculo(uuid) from public, anon;
revoke execute on function public.admin_listar_vinculos() from public, anon;
revoke execute on function public.admin_perfis_seguro(text) from public, anon;
revoke execute on function public.anamnese_historico_peso(uuid) from public, anon;
revoke execute on function public.calcular_motor_metabolico(uuid) from public, anon;
revoke execute on function public.calcular_motor_metabolico_v1(uuid) from public, anon;
revoke execute on function public.gerar_sugestao_meta(uuid) from public, anon;
revoke execute on function public.iniciar_rascunho_anamnese(uuid) from public, anon;
revoke execute on function public.processar_medias_smartwatch(uuid, timestamptz, timestamptz) from public, anon;
revoke execute on function public.profissional_atualizar_sexo_biologico(uuid, public.sexo_biologico_enum) from public, anon;
revoke execute on function public.profissional_salvar_anamnese(uuid, jsonb) from public, anon;
revoke execute on function public.validar_e_salvar_meta(jsonb, boolean) from public, anon;

-- `authenticated` precisa continuar chamando estas RPCs (grant explícito, como
-- a decisão 97 pede: nenhuma dependência de PUBLIC).
grant execute on function public.admin_aprovar_vinculo(uuid) to authenticated;
grant execute on function public.admin_atualizar_permissao_papel(uuid, uuid, boolean) to authenticated;
grant execute on function public.admin_encerrar_vinculo(uuid) to authenticated;
grant execute on function public.admin_listar_vinculos() to authenticated;
grant execute on function public.admin_perfis_seguro(text) to authenticated;
grant execute on function public.anamnese_historico_peso(uuid) to authenticated;
grant execute on function public.calcular_motor_metabolico(uuid) to authenticated;
grant execute on function public.calcular_motor_metabolico_v1(uuid) to authenticated;
grant execute on function public.gerar_sugestao_meta(uuid) to authenticated;
grant execute on function public.iniciar_rascunho_anamnese(uuid) to authenticated;
grant execute on function public.processar_medias_smartwatch(uuid, timestamptz, timestamptz) to authenticated;
grant execute on function public.profissional_atualizar_sexo_biologico(uuid, public.sexo_biologico_enum) to authenticated;
grant execute on function public.profissional_salvar_anamnese(uuid, jsonb) to authenticated;
grant execute on function public.validar_e_salvar_meta(jsonb, boolean) to authenticated;
