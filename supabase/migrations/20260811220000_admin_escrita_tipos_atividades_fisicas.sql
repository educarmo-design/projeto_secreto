-- N06 (RELATÓRIO 20260811_0005) — `tipos_atividades_fisicas`
-- (`20260811160000_atividades_fisicas_calorias_granulares.sql`) só tinha
-- policy de SELECT (`tipos_atividades_fisicas_select_all`) — na tarefa
-- anterior o dicionário era só semeado por INSERT direto na migration, sem
-- nenhuma tela de manutenção prevista ainda. Agora que `AdminAtividadesFisicas.tsx`
-- precisa criar/editar/remover modalidades, falta a policy de escrita —
-- diferente de `alimentos_referencia`, que tem a restrição de escrita
-- DELIBERADA e documentada ("curadoria é migration/service role", por causa
-- da sincronia com embeddings semânticos) — `tipos_atividades_fisicas` não
-- tinha essa mesma razão, só nunca precisou de escrita via painel até agora.
create policy "tipos_atividades_fisicas_insert_admin"
  on tipos_atividades_fisicas for insert
  with check (eh_admin());

create policy "tipos_atividades_fisicas_update_admin"
  on tipos_atividades_fisicas for update
  using (eh_admin())
  with check (eh_admin());

create policy "tipos_atividades_fisicas_delete_admin"
  on tipos_atividades_fisicas for delete
  using (eh_admin());

grant insert, update, delete on tipos_atividades_fisicas to authenticated;
