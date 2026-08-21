-- RELATÓRIO 20260820 — achado real do fundador (device físico,
-- atleta1000@teste.com): treinos de força (13/08, 04/08, 30/07 e "em
-- resumo todos") não aparecem na tela nem gravam no banco. Causa raiz:
-- `tipos_atividades_fisicas` (20260811160000_atividades_fisicas_calorias_
-- granulares.sql) foi semeado só com os tipos da seção "Both" do enum
-- `HealthWorkoutActivityType` do pacote `health` — comuns a Android E
-- iOS. Treino de força NUNCA foi "Both": confirmado lendo o enum completo
-- (lib/src/heath_data_types.dart) — STRENGTH_TRAINING/WEIGHTLIFTING são
-- Android-only, FUNCTIONAL_STRENGTH_TRAINING/TRADITIONAL_STRENGTH_TRAINING
-- são iOS-only. Ficou de fora dos dois lados por construção, não por
-- acidente pontual. `HealthSyncService._processarTreinos.tipo_atividade_
-- codigo references tipos_atividades_fisicas(nome_codigo)` rejeita
-- (FK) qualquer código ausente daqui — o `catch` best-effort do loop
-- engole a PostgrestException e segue pros próximos treinos, sem
-- nenhum rastro visível pro fundador.
--
-- Decisão desta tarefa (confirmada com o fundador): adicionar os 4
-- códigos, não só os 2 do Android do caso relatado agora — cobre o
-- iOS também de uma vez, evita o mesmo bug reaparecer quando o iOS for
-- testado de verdade (o app já gera o projeto iOS desde o RELATÓRIO
-- 20260813_0018, ainda não verificável neste ambiente Windows).

insert into tipos_atividades_fisicas (nome_codigo, nome_exibicao) values
  ('STRENGTH_TRAINING', 'Treino de Força'),
  ('WEIGHTLIFTING', 'Levantamento de Peso'),
  ('FUNCTIONAL_STRENGTH_TRAINING', 'Treino de Força Funcional'),
  ('TRADITIONAL_STRENGTH_TRAINING', 'Treino de Força Tradicional')
on conflict (nome_codigo) do nothing;
