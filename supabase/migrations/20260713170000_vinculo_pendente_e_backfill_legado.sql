-- Motor de Vínculos, parte SQL: (1) o status `pendente` que sustenta o
-- consentimento do paciente e (2) o backfill das relações de cuidado legadas.
--
-- Contexto: 20260713140000 unificou a RLS no vínculo ativo, o que deixou o
-- painel B2B mudo — não existe um único vínculo no banco, e
-- `vinculos_profissional_paciente` não tem policy de INSERT (de propósito: o
-- vínculo é a unidade de faturamento, e o cliente não pode emitir os próprios
-- slots). A porta de entrada passa a ser a Edge Function
-- `manage-professional-link`, que usa a service role. Esta migration prepara o
-- schema para ela e recupera o que já existia.

-- ============================================================================
-- 1. status `pendente` — consentimento do paciente
-- ============================================================================
-- Sem isto, `criar_vinculo` produziria um vínculo já ATIVO, e a RLS liberaria
-- na hora exames, métricas e anomalias do paciente. Ou seja: qualquer
-- profissional autenticado que conhecesse (ou adivinhasse) o UUID de um usuário
-- passaria a ler os dados clínicos dele — reabrindo pela API exatamente o
-- buraco que a RLS Zero Trust fechou, e sem o titular saber, ver ou poder
-- impedir (F.3: "você decide exatamente o que cada profissional vê").
--
-- Com `pendente`, o convite existe no banco mas NÃO autoriza nada: todas as
-- policies de terceiro exigem `status = 'ativo'`, e o índice único parcial
-- (`where status <> 'encerrado'`) já impede convite duplicado no mesmo par.
-- Só o próprio paciente promove pendente -> ativo (ação `aceitar_vinculo`).
--
-- ADD VALUE aqui e uso do valor só na Edge Function: um enum recém-estendido
-- não pode ser usado na MESMA transação que o estendeu, e o backfill abaixo
-- grava 'ativo' (valor antigo), então esta migration é segura como um todo.
alter type status_vinculo add value if not exists 'pendente';

-- ============================================================================
-- 2. Backfill das relações de cuidado legadas
-- ============================================================================
-- `planejamento_clinico` era, até 20260713140000, a fonte de autorização do
-- painel web: o profissional lia a telemetria de quem já tinha prescrição dele.
-- Essas duplas são relações de cuidado REAIS e já consentidas na prática (o
-- profissional atendeu aquele paciente), então entram direto como 'ativo' — não
-- como 'pendente'. É o que devolve o painel ao ar sem obrigar cada paciente
-- existente a aceitar de novo um vínculo que, para ele, já existia.
--
-- Só os pares ÚNICOS: um profissional com 10 prescrições para o mesmo paciente
-- vira 1 vínculo (o vínculo consome 1 slot — F.2 —, e duplicá-lo inflaria a
-- contagem de pacientes ativos e, no futuro, a fatura).
--
-- `data_inicio` = a data da PRIMEIRA prescrição daquele par, não `current_date`:
-- é a data em que a relação de cuidado de fato começou. Inventar "hoje" aqui
-- falsificaria o histórico do vínculo.
--
-- Idempotente: `on conflict ... do nothing` apoiado no índice único parcial
-- `uniq_vinculo_vivo_por_par` (20260713100000) — repetir a migration não
-- duplica nem falha, e um par que JÁ tenha vínculo vivo (criado entretanto pela
-- Edge Function) é preservado como está, nunca sobrescrito.
--
-- O `where profissional_id <> paciente_id_anonimo` protege a constraint
-- `vinculo_sem_autovinculo`: se algum profissional registrou uma prescrição para
-- si mesmo (teste, conta de demonstração), a linha é ignorada em vez de abortar
-- a migration inteira.
insert into vinculos_profissional_paciente
  (profissional_id, paciente_id, status, tipo_pagador, tipo_produto, data_inicio)
select
  pc.profissional_id,
  pc.paciente_id_anonimo,
  'ativo'::status_vinculo,
  'profissional'::tipo_pagador_vinculo,
  'sem_garmin'::tipo_produto_vinculo,
  min(pc.criado_em)::date
from planejamento_clinico pc
where pc.profissional_id <> pc.paciente_id_anonimo
group by pc.profissional_id, pc.paciente_id_anonimo
on conflict (profissional_id, paciente_id) where status <> 'encerrado'
do nothing;

-- `tipo_produto = 'sem_garmin'` para todos os legados, de propósito: o pacote
-- que cada profissional paga (F.2 — a dimensão "com/sem Garmin") ainda não
-- existe no banco (entra com o faturamento). Assumir 'com_garmin' aqui daria de
-- graça o recurso mais caro do produto a toda a base legada; o downgrade seria
-- pior de reverter do que o upgrade.
