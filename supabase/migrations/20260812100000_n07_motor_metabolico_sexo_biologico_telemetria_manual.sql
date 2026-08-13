-- N07 (Motor Metabólico: Mifflin-St Jeor + Katch-McArdle + PAL decomposto +
-- TEF isolado) + fechamento de dependências: sexo biológico e telemetria
-- manual do profissional. RELATÓRIO 20260812_0008.

-- ============================================================================
-- Parte 1 — Auditoria e fix do sexo biológico
-- ============================================================================
-- AUDITORIA (achado, não presumido): `perfis_usuarios.sexo_biologico`
-- JÁ EXISTIA desde `20260706191827_core_schema.sql` — mas como `text` livre,
-- sem CHECK/ENUM, e NUNCA foi coletado por nenhuma tela (nem App, nem
-- Painel). Conferido com uma consulta real antes desta migration: 10 linhas
-- (dados de seed fictício, `seed_cloud.ts`) já tinham o campo preenchido,
-- mas com os valores por extenso em português — 'feminino'/'masculino' —,
-- não os códigos 'M'/'F' pedidos nesta tarefa. A conversão de tipo abaixo
-- migra esses valores; qualquer valor inesperado que não seja
-- 'feminino'/'masculino'/'M'/'F'/NULL faz o cast pro ENUM falhar e aborta a
-- migration inteira (mesmo espírito do autoteste de `20260730160000_d2_pii_
-- criptografia_repouso.sql`: falhar alto, nunca continuar com dado ambíguo).
create type sexo_biologico_enum as enum ('M', 'F');

alter table perfis_usuarios
  alter column sexo_biologico type sexo_biologico_enum
  using (
    case sexo_biologico
      when 'feminino' then 'F'
      when 'masculino' then 'M'
      else sexo_biologico
    end
  )::sexo_biologico_enum;

comment on column perfis_usuarios.sexo_biologico is
  'Sexo biológico (ENUM M/F, RELATÓRIO 20260812_0008) — insumo do Motor Metabólico N07 (Mifflin-St Jeor precisa dele quando não há massa magra medida). Editável pelo próprio usuário no app (perfil_usuario_page.dart) e, para o profissional vinculado, via RPC profissional_atualizar_sexo_biologico (nunca update direto — perfis_usuarios não abre policy de UPDATE alguma para quem não é o dono da linha ou admin).';

-- ----------------------------------------------------------------------------
-- Leitura pelo profissional: estende a view já existente
-- `perfis_pacientes_vinculados` (`20260713140000_saneamento_grants_e_
-- unificacao_rls.sql`) — mesmas 4 colunas de antes + sexo_biologico.
-- `security_invoker = false`/`security_barrier = true` preservados
-- (o `create or replace view` sem a cláusula `with (...)` manteria as
-- opções já definidas, mas declarar de novo explicitamente documenta a
-- intenção sem depender de "ficou assim por acidente").
-- ----------------------------------------------------------------------------
create or replace view perfis_pacientes_vinculados
with (security_invoker = false, security_barrier = true) as
select
  p.id,
  p.nickname,
  p.data_nascimento,
  p.geo_ranking_id,
  p.sexo_biologico
from perfis_usuarios p
where exists (
  select 1
  from vinculos_profissional_paciente v
  where v.profissional_id = auth.uid()
    and v.paciente_id = p.id
    and v.status = 'ativo'
);

-- ----------------------------------------------------------------------------
-- Escrita pelo profissional: RPC dedicada (NÃO torna a view acima
-- atualizável) — escreve só a coluna `sexo_biologico`, nunca
-- nickname/data_nascimento/geo_ranking_id, que não fazem parte do escopo
-- desta tarefa e têm implicações próprias (data_nascimento é a trava de
-- maioridade N03; editar isso por aqui seria escopo indevido). Mesmo padrão
-- de `admin_atualizar_permissao_papel`/`admin_encerrar_vinculo`: RPC
-- `security definer` como ÚNICA porta de escrita cross-usuário, escopada e
-- re-validada no servidor — `perfis_usuarios` continua sem qualquer policy
-- de UPDATE para quem não é o dono ou admin.
-- ----------------------------------------------------------------------------
create or replace function public.profissional_atualizar_sexo_biologico(
  p_paciente_id uuid,
  p_sexo_biologico public.sexo_biologico_enum
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is distinct from p_paciente_id
     and not exists (
       select 1 from public.vinculos_profissional_paciente v
       where v.profissional_id = auth.uid()
         and v.paciente_id = p_paciente_id
         and v.status = 'ativo'
     )
     and not public.eh_admin()
  then
    raise exception 'Sem vínculo ativo com este paciente.';
  end if;

  update public.perfis_usuarios
  set sexo_biologico = p_sexo_biologico
  where id = p_paciente_id;
end;
$$;

comment on function public.profissional_atualizar_sexo_biologico(uuid, public.sexo_biologico_enum) is
  'RELATÓRIO 20260812_0008 — permite o próprio usuário, um profissional com vínculo ATIVO, ou um admin, gravar sexo_biologico de um paciente. Única porta de escrita cross-usuário dessa coluna.';

revoke execute on function public.profissional_atualizar_sexo_biologico(uuid, public.sexo_biologico_enum) from public;
grant execute on function public.profissional_atualizar_sexo_biologico(uuid, public.sexo_biologico_enum) to authenticated;

-- ============================================================================
-- Parte 2 — Telemetria manual do profissional (peso/massa magra)
-- ============================================================================
-- `metricas_saude_diarias` só tinha INSERT/UPDATE para o PRÓPRIO usuário
-- (`_insert_own`/`_update_own`, Onda 1.5) — o profissional só tinha SELECT
-- via vínculo. Estas 2 policies novas replicam a mesma condição de vínculo
-- ATIVO já usada em `metricas_saude_diarias_select_profissional_vinculado`,
-- agora para escrita. O Painel Web (InserirMedicaoModal.tsx) faz um
-- `.upsert()` de UMA linha por vez — não um lote — então o bug histórico de
-- "upsert destrutivo" (RELATÓRIO 20260811_0001: colunas ausentes viravam
-- NULL explícito quando MÚLTIPLAS linhas heterogêneas iam num único INSERT)
-- não se aplica aqui.
create policy "metricas_saude_diarias_insert_profissional_vinculado"
  on metricas_saude_diarias for insert
  with check (
    exists (
      select 1
      from vinculos_profissional_paciente v
      where v.profissional_id = auth.uid()
        and v.paciente_id = metricas_saude_diarias.usuario_id_anonimo
        and v.status = 'ativo'
    )
  );

create policy "metricas_saude_diarias_update_profissional_vinculado"
  on metricas_saude_diarias for update
  using (
    exists (
      select 1
      from vinculos_profissional_paciente v
      where v.profissional_id = auth.uid()
        and v.paciente_id = metricas_saude_diarias.usuario_id_anonimo
        and v.status = 'ativo'
    )
  )
  with check (
    exists (
      select 1
      from vinculos_profissional_paciente v
      where v.profissional_id = auth.uid()
        and v.paciente_id = metricas_saude_diarias.usuario_id_anonimo
        and v.status = 'ativo'
    )
  );

comment on policy "metricas_saude_diarias_insert_profissional_vinculado" on metricas_saude_diarias is
  'RELATÓRIO 20260812_0008 — permite o profissional com vínculo ATIVO registrar telemetria manual (peso/massa magra) pelo Painel Web. RLS é a barreira real; a checagem de conflito ("já existe dado neste dia?") é feita pelo cliente ANTES do upsert, só como UX de confirmação — não como segurança.';

-- ============================================================================
-- Parte 3 — Engine N07: calcular_motor_metabolico(p_usuario_id uuid)
-- ============================================================================
-- Modelo "PAL decomposto": em vez de um único multiplicador (1.2/1.55/1.9)
-- aplicado à TMB pra estimar TUDO de uma vez (o que soma exercício duas
-- vezes quando o usuário também loga treinos), este motor separa:
--   gasto_sedentario = TMB × 1.2 (piso de vida sedentária, sem exercício)
--   gasto_atividade  = Σ(MET × peso_kg × horas/dia) das atividades da
--                      anamnese ATIVA (N09) — o exercício deliberado, à parte
--   tdee             = gasto_sedentario + gasto_atividade (NUNCA soma TEF)
--   tef              = 10% da TMB — só OUTPUT informativo, isolado de
--                      propósito ("anti double-count", pedido do fundador)
--
-- TMB: Katch-McArdle (370 + 21.6×massa_magra) quando há massa magra medida
-- (mais precisa, não depende de idade/sexo/altura); senão Mifflin-St Jeor
-- usando a fórmula real e completa do método — TMB = 10×peso + 6.25×altura
-- − 5×idade + s (s = +5 homem, −161 mulher). O ARQUIVOS desta tarefa listou
-- só "idade, peso e sexo" como insumos do Mifflin, mas a fórmula
-- Mifflin-St Jeor de verdade também usa altura — omiti-la produziria um
-- número sistematicamente errado sob o nome de uma fórmula conhecida, e
-- `perfis_usuarios.altura_cm` já existe e já é coletado (Perfil Físico,
-- RELATÓRIO 20260810_0006). Decisão registrada aqui e no Relatório Humano
-- para o fundador poder reverter se a omissão for intencional.
--
-- Sem dado suficiente para nenhuma fórmula, o motor NÃO lança exceção —
-- devolve tmb/gasto_sedentario/tdee null e formula_usada =
-- 'dados_insuficientes', com o array `avisos` dizendo exatamente o que
-- falta. Isso é deliberado: o motor "roda em tempo real" conforme o
-- fundador pediu, e o usuário pode estar no meio do preenchimento do
-- perfil/anamnese quando o App ou o Painel chamam a RPC pra simular.
create or replace function public.calcular_motor_metabolico(p_usuario_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_idade int;
  v_sexo public.sexo_biologico_enum;
  v_altura_cm numeric;
  v_peso_kg numeric;
  v_massa_magra_kg numeric;
  v_anamnese_id uuid;
  v_tmb numeric;
  v_formula text;
  v_gasto_sedentario numeric;
  v_gasto_atividade numeric;
  v_tef numeric;
  v_tdee numeric;
  v_avisos text[] := '{}';
begin
  if auth.uid() is distinct from p_usuario_id
     and not exists (
       select 1 from public.vinculos_profissional_paciente v
       where v.profissional_id = auth.uid()
         and v.paciente_id = p_usuario_id
         and v.status = 'ativo'
     )
     and not public.eh_admin()
  then
    raise exception 'Sem acesso ao Motor Metabólico deste usuário.';
  end if;

  select public.calcular_idade(p.data_nascimento), p.sexo_biologico, p.altura_cm
  into v_idade, v_sexo, v_altura_cm
  from public.perfis_usuarios p
  where p.id = p_usuario_id;

  -- Última leitura VÁLIDA (não-nula) de cada métrica — podem vir de dias
  -- diferentes (ex.: peso sincroniza todo dia pela balança, massa magra só
  -- quando a balança de bioimpedância mede).
  select m.peso_kg into v_peso_kg
  from public.metricas_saude_diarias m
  where m.usuario_id_anonimo = p_usuario_id and m.peso_kg is not null
  order by m.data_referencia desc
  limit 1;

  select m.massa_magra_kg into v_massa_magra_kg
  from public.metricas_saude_diarias m
  where m.usuario_id_anonimo = p_usuario_id and m.massa_magra_kg is not null
  order by m.data_referencia desc
  limit 1;

  -- TMB
  if v_massa_magra_kg is not null then
    v_tmb := 370 + (21.6 * v_massa_magra_kg);
    v_formula := 'katch_mcardle';
  elsif v_peso_kg is not null and v_idade is not null and v_sexo is not null and v_altura_cm is not null then
    v_tmb := (10 * v_peso_kg) + (6.25 * v_altura_cm) - (5 * v_idade)
             + (case v_sexo when 'M' then 5 else -161 end);
    v_formula := 'mifflin_st_jeor';
  else
    v_tmb := null;
    v_formula := 'dados_insuficientes';
    if v_massa_magra_kg is null then v_avisos := array_append(v_avisos, 'sem_massa_magra'); end if;
    if v_peso_kg is null then v_avisos := array_append(v_avisos, 'sem_peso'); end if;
    if v_idade is null then v_avisos := array_append(v_avisos, 'sem_data_nascimento'); end if;
    if v_sexo is null then v_avisos := array_append(v_avisos, 'sem_sexo_biologico'); end if;
    if v_altura_cm is null then v_avisos := array_append(v_avisos, 'sem_altura'); end if;
  end if;

  v_gasto_sedentario := case when v_tmb is not null then v_tmb * 1.2 else null end;
  v_tef := case when v_tmb is not null then v_tmb * 0.10 else null end;

  -- Gasto de Atividade (EAT): Σ(MET × peso × horas/dia) das atividades da
  -- anamnese ATIVA (N09). `coalesce(met_estimado, 0)`: modalidade sem MET
  -- cadastrado pelo Admin ainda (AdminAtividadesFisicas.tsx) contribui 0,
  -- não quebra a soma inteira.
  select id into v_anamnese_id
  from public.anamneses
  where usuario_id = p_usuario_id and status_vigencia = 'ativo'
  limit 1;

  if v_peso_kg is null then
    v_gasto_atividade := null;
    v_avisos := array_append(v_avisos, 'sem_peso_para_gasto_atividade');
  elsif v_anamnese_id is null then
    v_gasto_atividade := 0;
    v_avisos := array_append(v_avisos, 'sem_anamnese_ativa');
  else
    select coalesce(sum(coalesce(t.met_estimado, 0) * v_peso_kg * (aa.minutos_diarios / 60.0)), 0)
    into v_gasto_atividade
    from public.anamneses_atividades aa
    join public.tipos_atividades_fisicas t on t.id = aa.atividade_id
    where aa.anamnese_id = v_anamnese_id;
  end if;

  v_tdee := case
    when v_gasto_sedentario is not null and v_gasto_atividade is not null
    then v_gasto_sedentario + v_gasto_atividade
    else null
  end;

  return jsonb_build_object(
    'tmb', v_tmb,
    'gasto_sedentario', v_gasto_sedentario,
    'gasto_atividade', v_gasto_atividade,
    'tef', v_tef,
    'tdee', v_tdee,
    'formula_usada', v_formula,
    'insumos', jsonb_build_object(
      'idade', v_idade,
      'sexo_biologico', v_sexo,
      'altura_cm', v_altura_cm,
      'peso_kg', v_peso_kg,
      'massa_magra_kg', v_massa_magra_kg
    ),
    'avisos', to_jsonb(v_avisos)
  );
end;
$$;

comment on function public.calcular_motor_metabolico(uuid) is
  'N07 (RELATÓRIO 20260812_0008) — TMB (Katch-McArdle se houver massa magra, senão Mifflin-St Jeor completa), PAL decomposto (gasto_sedentario = TMB×1.2 + gasto_atividade das atividades da anamnese ativa, MET×peso×horas), TEF isolado (10% da TMB, informativo, NUNCA somado ao tdee). Nunca lança exceção por dado faltante — devolve formula_usada=dados_insuficientes e o array avisos.';

revoke execute on function public.calcular_motor_metabolico(uuid) from public;
grant execute on function public.calcular_motor_metabolico(uuid) to authenticated;
