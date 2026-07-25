-- Cadastro Dinâmico (Base + Profissional) — tela de auth completa.
--
-- `perfis_usuarios` já tinha `eh_profissional`/`tipo_profissional`
-- (20260706191827_core_schema.sql) — o que faltava para o formulário de
-- cadastro pedido eram três colunas novas:
--   1. `idade`/`peso_kg` — coletados uma vez no cadastro (autodeclarado).
--      NÃO substituem a telemetria contínua de `metricas_saude_diarias.
--      peso_kg` (Onda 1.5) nem a idade calculável a partir de uma futura
--      `data_nascimento` real — são só o valor inicial que o usuário digitou
--      na hora de criar a conta.
--   2. `registro_profissional` — número do conselho (CRM/CRN/CREFITO/CREF),
--      texto livre porque cada conselho tem formato próprio; sem validação
--      de formato aqui (fica para uma curadoria/validação futura, fora do
--      escopo desta tela).
--
-- Nenhuma policy nova: `perfis_usuarios_select_own`/`_insert_own`/
-- `_update_own` (já existentes) cobrem as colunas novas automaticamente —
-- RLS do Postgres é por LINHA, não por coluna.

alter table perfis_usuarios
  add column idade int,
  add column peso_kg numeric(5, 2),
  add column registro_profissional text;

-- GRANT explícito (Parte 0.10 — obrigatório em toda migração). Reafirma o
-- privilégio mesmo que o projeto já funcione sob os defaults antigos do
-- Postgres (main ainda não tem a migração de saneamento de GRANTs que
-- endureceu isso formalmente) — depois desta migração, `perfis_usuarios`
-- não depende mais desse acidente histórico.
grant select, insert, update on perfis_usuarios to authenticated;
