-- ONDA 3 — Fundação do Painel Web Profissional (web_painel/).
--
-- Sem esta migration, o painel web não conseguiria ler NENHUMA linha de
-- dados de paciente: as policies originais de metricas_saude_diarias e
-- eventos_anomalias_saude (20260706191827_core_schema.sql /
-- 20260708174650_reestruturacao_colunas_fixas_onda_1_5.sql) só permitem
-- `auth.uid() = usuario_id_anonimo` — ou seja, só o próprio paciente lê os
-- próprios dados. Um Médico/Nutricionista logado no painel web nunca é
-- `usuario_id_anonimo`, então precisa de uma policy própria.
--
-- O vínculo de autorização usado aqui é `planejamento_clinico`: um
-- profissional só enxerga os dados brutos de um paciente para quem ele já
-- registrou pelo menos uma prescrição (`profissional_id = auth.uid()` e
-- `paciente_id_anonimo` = o paciente em questão). Isso é Zero Trust por
-- padrão — a permissão nunca é "todo profissional vê todo paciente", é
-- sempre escopada a uma relação de cuidado que já existe no banco.

-- ============================================================================
-- 1. Novo papel profissional: Auditoria de Seguradora
-- ============================================================================
alter type tipo_profissional_saude add value if not exists 'Auditoria_Seguradora';

-- ============================================================================
-- 2. metricas_saude_diarias: leitura por profissional vinculado
-- ============================================================================
create policy "metricas_saude_diarias_select_profissional_vinculado"
  on metricas_saude_diarias for select
  using (
    exists (
      select 1
      from planejamento_clinico pc
      where pc.profissional_id = auth.uid()
        and pc.paciente_id_anonimo = metricas_saude_diarias.usuario_id_anonimo
    )
  );

-- ============================================================================
-- 3. eventos_anomalias_saude: leitura por profissional vinculado
-- ============================================================================
create policy "eventos_anomalias_saude_select_profissional_vinculado"
  on eventos_anomalias_saude for select
  using (
    exists (
      select 1
      from planejamento_clinico pc
      where pc.profissional_id = auth.uid()
        and pc.paciente_id_anonimo = eventos_anomalias_saude.usuario_id_anonimo
    )
  );

-- ============================================================================
-- 4. View de perfil restrita para PatientList.tsx/PatientDetails.tsx
-- ============================================================================
-- `perfis_usuarios` não pode ganhar uma policy de SELECT ampla equivalente
-- às duas acima: RLS é por LINHA, não por COLUNA — uma policy que libera a
-- linha inteira também exporia `email` (guardado em texto plano nesta
-- tabela, diferente de `nome`/`telefone`, que já saem do app mobile como
-- ciphertext AES-256-GCM — ver `CryptoStorageService`/
-- `cadastro_controller.dart`) para qualquer profissional vinculado, mesmo
-- que o painel web só peça `nickname`/`data_nascimento`/`geo_ranking_id`.
--
-- Esta view resolve isso restringindo no nível de COLUNA: só expõe os 4
-- campos que `PatientList`/`PatientDetails` realmente usam, nunca
-- nome/telefone/email/endereço. `security_invoker = true` faz a view
-- rodar com o papel de quem a está consultando (não do dono da view) — o
-- `where exists (...)` abaixo é o que realmente autoriza cada linha, não a
-- RLS nativa de `perfis_usuarios` (que continua intocada e só libera
-- `auth.uid() = id`, exatamente como antes desta migration).
create view perfis_pacientes_vinculados
with (security_invoker = true) as
select
  p.id,
  p.nickname,
  p.data_nascimento,
  p.geo_ranking_id
from perfis_usuarios p
where exists (
  select 1
  from planejamento_clinico pc
  where pc.profissional_id = auth.uid()
    and pc.paciente_id_anonimo = p.id
);

grant select on perfis_pacientes_vinculados to authenticated;
