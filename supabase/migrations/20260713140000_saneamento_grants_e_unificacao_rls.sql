-- Saneamento de Segurança e Unificação de RLS.
--
-- Duas correções independentes, ambas descobertas ao validar a migration
-- anterior (20260713100000_estruturas_b2b_v4.sql) num banco nascido do zero:
--
--   1. GRANTs. Nenhuma das tabelas originais concede DML ao papel
--      `authenticated`. O Postgres atual do Supabase tem os default privileges
--      endurecidos: uma tabela criada por `postgres` no schema public nasce com
--      `authenticated=Dxtm` (TRUNCATE/REFERENCES/TRIGGER) e nenhum
--      SELECT/INSERT/UPDATE. Como o privilégio de TABELA é avaliado ANTES da
--      RLS, o cliente leva "permission denied" e as policies nunca chegam a
--      rodar — um deploy limpo sobe com o app inteiro sem conseguir ler nada.
--      (O projeto hospedado hoje provavelmente escapa disso por ter sido
--      provisionado sob os defaults antigos; esta migration torna o schema
--      autossuficiente e para de depender desse acidente histórico.)
--
--   2. Dupla fonte de autorização. `metricas_saude_diarias` e
--      `eventos_anomalias_saude` (e a view `perfis_pacientes_vinculados`) ainda
--      autorizam o profissional via `planejamento_clinico` — herança de
--      20260709180000, de quando não existia tabela de vínculo. Com
--      `vinculos_profissional_paciente` (Adendo v4, F.2) o vínculo passa a ser
--      a ÚNICA fonte de verdade sobre quem acompanha quem.
--
-- Nada aqui afeta a regra "o dono lê e escreve o próprio dado": todas as
-- policies `_own` seguem intocadas.

-- ============================================================================
-- 1. GRANTs explícitos ao papel `authenticated`
-- ============================================================================
-- NUNCA ao papel `anon`: usuário não autenticado não tem o que fazer em tabela
-- clínica. (O login anônimo do Supabase emite JWT com role `authenticated` —
-- `anonymous_users` é lida por usuário anônimo AUTENTICADO, não por `anon`.)
--
-- Sem DELETE em nenhuma tabela: o app não apaga dado. Exclusão é operação de
-- titular (LGPD), feita server-side.
--
-- O privilégio concedido espelha exatamente as policies que cada tabela já tem
-- — conceder além disso seria privilégio morto hoje e uma porta aberta no dia
-- em que alguém criasse a policy correspondente sem reparar no grant.

-- Perfil e gamificação (policies own: select/insert/update)
grant select, insert, update on perfis_usuarios to authenticated;
grant select, insert, update on anonymous_users to authenticated;
grant select, insert, update on progresso_gamificacao to authenticated;

-- Dados clínicos e de telemetria (policies own: select/insert/update)
grant select, insert, update on metricas_saude_diarias to authenticated;
grant select, insert, update on diario_alimentar_diario to authenticated;
grant select, insert, update on eventos_treino to authenticated;
grant select, insert, update on medicamentos_usuario to authenticated;

-- Prescrição: o profissional insere, os dois lados leem/atualizam.
grant select, insert, update on planejamento_clinico to authenticated;

-- Anomalias: SEM update. A tabela é a Caixa Preta (Adendo v4, G.5) e nunca teve
-- policy de UPDATE — o evento é gravado uma vez e não se reescreve. Conceder
-- update aqui seria privilégio sem policy que o respalde.
grant select, insert on eventos_anomalias_saude to authenticated;

-- Esteira dos 14 dias: SÓ select. A ausência de policy de escrita é deliberada
-- (20260712150000) — se o cliente pudesse escrever a própria linha, manipularia
-- o próprio congelamento do trial. Toda escrita é da Edge Function
-- `calculate-recovery-mode` com service role.
grant select on esteira_trial_estado to authenticated;

-- `garmin_conexoes` fica DE FORA, de propósito. Ela guarda access_token e
-- access_token_secret do OAuth da Garmin em TEXTO PLANO, e a própria migration
-- que a criou (20260709190000) justifica o texto plano assim: "esta linha nunca
-- é lida por nenhum cliente, só pela service role key dentro da Edge Function
-- (...) não há binário/APK do qual esse valor possa ser extraído". Conceder
-- select ao papel `authenticated` faria exatamente o que aquela justificativa
-- descarta: colocar o token ao alcance do app. As policies `_own` que existem lá
-- ficam inertes (privilégio de tabela ausente) — que é o comportamento seguro.
-- Se um dia a tela de "gerenciar minhas conexões" existir, ela deve ler por uma
-- view que exponha `garmin_user_id`/`conectado_em` e NUNCA os tokens (mesmo
-- padrão de restrição por COLUNA já usado em `perfis_pacientes_vinculados`).

-- ============================================================================
-- 2. Unificação do Zero Trust no vínculo
-- ============================================================================
-- Antes: bastava o profissional ter registrado UMA prescrição em
-- `planejamento_clinico` para um paciente para ler a telemetria dele — e a
-- policy de INSERT daquela tabela deixa qualquer profissional criar prescrição
-- para QUALQUER paciente_id. Ou seja: a leitura de dado clínico de terceiro era
-- autoconcedida por um INSERT. Depois desta migration, prescrição não autoriza
-- mais nada: só o vínculo ativo autoriza.
--
-- `status = 'ativo'` (e não `<> 'encerrado'`): vínculo em carência não dá
-- leitura ao profissional — a carência existe para o PACIENTE manter acesso ao
-- próprio app enquanto decide (F.5), não para estender o acesso de quem já não
-- o acompanha. Mesma regra já aplicada em `resultados_exames`.

-- --- metricas_saude_diarias ------------------------------------------------
drop policy "metricas_saude_diarias_select_profissional_vinculado"
  on metricas_saude_diarias;

create policy "metricas_saude_diarias_select_profissional_vinculado"
  on metricas_saude_diarias for select
  using (
    exists (
      select 1
      from vinculos_profissional_paciente v
      where v.profissional_id = auth.uid()
        and v.paciente_id = metricas_saude_diarias.usuario_id_anonimo
        and v.status = 'ativo'
    )
  );

-- --- eventos_anomalias_saude -----------------------------------------------
drop policy "eventos_anomalias_saude_select_profissional_vinculado"
  on eventos_anomalias_saude;

create policy "eventos_anomalias_saude_select_profissional_vinculado"
  on eventos_anomalias_saude for select
  using (
    exists (
      select 1
      from vinculos_profissional_paciente v
      where v.profissional_id = auth.uid()
        and v.paciente_id = eventos_anomalias_saude.usuario_id_anonimo
        and v.status = 'ativo'
    )
  );

-- --- perfis_pacientes_vinculados -------------------------------------------
-- A view é a TERCEIRA porta de leitura do profissional (nickname/nascimento/
-- geo do paciente, para PatientList/PatientDetails) e também autorizava por
-- `planejamento_clinico`. Deixá-la assim manteria aberto exatamente o buraco que
-- os dois DROPs acima fecham. Mesmas colunas, mesma ordem, mesmos tipos: o
-- `create or replace` não muda o contrato para o painel web, único leitor.
--
-- E corrige um BUG que a validação por teste expôs: a view nasceu (20260709180000)
-- com `security_invoker = true`, o que faz as tabelas-base serem lidas com o
-- papel de QUEM CONSULTA — logo a RLS de `perfis_usuarios` (que só libera
-- `auth.uid() = id`) barrava o profissional, e a view devolvia ZERO linhas para
-- todo mundo. A lista de pacientes do painel web nunca funcionou. O comentário
-- de lá afirma o oposto ("o `where exists` é o que realmente autoriza, não a RLS
-- nativa de perfis_usuarios") — o que só valeria SEM security_invoker.
--
-- A correção é justamente essa: sem `security_invoker`, a view roda com o papel
-- do dono (postgres, que ignora RLS) e o `where exists` abaixo passa a ser, de
-- fato, a única autorização — que é o desenho pretendido. A restrição por COLUNA
-- continua sendo a razão de a view existir: expõe 4 campos e NUNCA
-- nome/telefone/email/endereço (o `email` está em texto plano em
-- `perfis_usuarios`, e uma policy de RLS liberaria a linha inteira).
--
-- `security_barrier` impede que uma função barata injetada no WHERE do
-- consumidor seja avaliada ANTES do `exists` do vínculo e vaze linha de paciente
-- não-vinculado — necessário porque agora a view é quem autoriza.
create or replace view perfis_pacientes_vinculados
with (security_invoker = false, security_barrier = true) as
select
  p.id,
  p.nickname,
  p.data_nascimento,
  p.geo_ranking_id
from perfis_usuarios p
where exists (
  select 1
  from vinculos_profissional_paciente v
  where v.profissional_id = auth.uid()
    and v.paciente_id = p.id
    and v.status = 'ativo'
);

grant select on perfis_pacientes_vinculados to authenticated;
