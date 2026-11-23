-- N43 Etapa 2 (Documento Mestre v9.2.1, Parte V1 [PENDENTE] N43; investigação na
-- Etapa 1: docs/log_dev/20261123_0001_investigacao_n43_etapa1_sono_e_tipo_refeicao.md).
--
-- Três mudanças, todas aditivas (nenhuma coluna existente muda; nenhum dado é
-- reescrito; nenhuma função/RPC é criada ou alterada ⇒ a postura da decisão 97
-- para funções não se aplica aqui):
--
--   1) `metricas_saude_diarias`: instantes CRUS de início/fim do sono + fuso.
--   2) `coleta_diaria`: tipo da refeição.
--   3) `configuracoes_sistema`: janela (em minutos) para unir segmentos de sono
--      — regra 16, nada de constante mágica no app.
--
-- ---------------------------------------------------------------------------
-- 1) SONO — regra G.9 (dado derivado de evento guarda-se CRU)
-- ---------------------------------------------------------------------------
-- Antes: só minutos (`minutos_sono`, `sono_*_minutos`); os instantes chegavam
-- do Health Connect e eram descartados na agregação diária.
--
--   sono_inicio / sono_fim   instantes absolutos (timestamptz, UTC) do início do
--                            primeiro e do fim do último estágio de UMA noite já
--                            consolidada (segmentos separados por menos que a
--                            janela de `configuracoes_sistema` viram um só).
--   sono_offset_minutos      deslocamento do fuso local (minutos a leste de UTC,
--                            ex.: -180 = UTC-03:00) VIGENTE em `sono_inicio`.
--                            Sem isto o servidor não sabe que hora local foi: o
--                            histórico de fuso mora só no aparelho.
--   sono_segmentos_qtd       quantos segmentos restaram após a união. Se for > 1
--                            a noite é AMBÍGUA (ex.: noite + cochilo no mesmo
--                            `data_referencia`): o app NÃO escolhe um deles —
--                            regra 23 — e deixa `sono_inicio`/`sono_fim` NULOS;
--                            esta contagem é o sinal visível de que houve
--                            ambiguidade (e não "sem dado").
--
-- NÃO se grava aqui "a que noite o sono pertence": `data_referencia` segue como
-- já era (heurística existente, inalterada) e cada consumidor futuro deriva sua
-- própria noite a partir dos instantes crus.
alter table public.metricas_saude_diarias
  add column if not exists sono_inicio          timestamptz,
  add column if not exists sono_fim             timestamptz,
  add column if not exists sono_offset_minutos  integer,
  add column if not exists sono_segmentos_qtd   smallint;

alter table public.metricas_saude_diarias
  add constraint metricas_saude_sono_inicio_fim_juntos
    check ((sono_inicio is null) = (sono_fim is null)),
  add constraint metricas_saude_sono_fim_apos_inicio
    check (sono_inicio is null or sono_fim >= sono_inicio),
  add constraint metricas_saude_sono_offset_em_faixa
    check (sono_offset_minutos is null or sono_offset_minutos between -840 and 840),
  add constraint metricas_saude_sono_segmentos_positivo
    check (sono_segmentos_qtd is null or sono_segmentos_qtd >= 1),
  add constraint metricas_saude_sono_instantes_exigem_offset
    check (sono_inicio is null or sono_offset_minutos is not null);

comment on column public.metricas_saude_diarias.sono_inicio is
  'N43: instante cru (UTC) do início da noite consolidada. NULL = sem dado OU noite ambígua (ver sono_segmentos_qtd > 1).';
comment on column public.metricas_saude_diarias.sono_fim is
  'N43: instante cru (UTC) do fim da noite consolidada. NULL junto com sono_inicio.';
comment on column public.metricas_saude_diarias.sono_offset_minutos is
  'N43: offset do fuso local (minutos a leste de UTC) vigente em sono_inicio.';
comment on column public.metricas_saude_diarias.sono_segmentos_qtd is
  'N43: nº de segmentos após a união pela janela de configuracoes_sistema. >1 = noite ambígua (instantes não gravados, regra 23).';

-- ---------------------------------------------------------------------------
-- 2) TIPO DA REFEIÇÃO — coluna dedicada, não chave de `valor_jsonb`
-- ---------------------------------------------------------------------------
-- Escolha documentada: coluna dedicada porque (a) o domínio é fechado e vira
-- CHECK no banco (a chave de jsonb aceitaria qualquer texto); (b) é filtro/
-- agrupamento natural dos templates (coluna, não extração de jsonb); (c)
-- `payloadRevisado()` também é o `payload_jsonb` das favoritas — o tipo da
-- REFEIÇÃO CONSUMIDA não deve vazar para dentro do payload reaproveitável.
-- Mesmos 4 códigos de `alimentos_favoritos.tipo_refeicao`.
--
-- NULO é permitido de propósito: as 360 refeições já gravadas não têm tipo e
-- NÃO são preenchidas por hora (regra 23 — nada de chute retroativo). A
-- obrigatoriedade para refeições NOVAS está no app (seletor sem valor padrão);
-- uma CHECK `NOT VALID` impediria gravar refeição pelo app antigo ainda
-- instalado — fica como endurecimento futuro, depois do rollout do app.
alter table public.coleta_diaria
  add column if not exists tipo_refeicao text;

alter table public.coleta_diaria
  add constraint coleta_diaria_tipo_refeicao_valido
    check (tipo_refeicao is null or tipo_refeicao in ('cafe_da_manha', 'almoco', 'lanche', 'jantar')),
  add constraint coleta_diaria_tipo_refeicao_so_em_refeicao
    check (tipo_refeicao is null or atributo = 'refeicao');

comment on column public.coleta_diaria.tipo_refeicao is
  'N43: cafe_da_manha | almoco | lanche | jantar. Só para atributo = refeicao. NULL = refeição anterior ao N43 (não inferida, regra 23).';

-- ---------------------------------------------------------------------------
-- 3) CONFIGURAÇÃO — janela de união de segmentos de sono (regra 16)
-- ---------------------------------------------------------------------------
-- Valor inicial 30 min (editável no painel, Admin > Configurações): dois
-- segmentos separados por MENOS que isto viram uma noite só. Os estágios do
-- Health Connect costumam ser contíguos; lacunas curtas são falha de captura do
-- relógio, não um novo sono.
insert into public.configuracoes_sistema (chave, valor, descricao)
values (
  'cliente_sono_uniao_segmentos_minutos',
  '30',
  'N43: segmentos de sono separados por MENOS que N minutos são unidos numa só noite (sono_inicio/sono_fim). Lido pelo app.'
)
on conflict (chave) do nothing;

-- Hoje `configuracoes_sistema` só é legível por administrador (eh_admin()), então
-- o app do usuário comum não alcançaria o valor acima. Policy ESTREITA: qualquer
-- usuário logado LÊ (só SELECT) as chaves com prefixo `cliente_`. Convenção:
-- nunca guardar segredo/valor sensível em chave `cliente_*` — ela é legível por
-- todo usuário autenticado. Escrita continua só do administrador.
create policy configuracoes_sistema_select_cliente
  on public.configuracoes_sistema
  for select
  to authenticated
  using (chave like 'cliente\_%' escape '\');

-- ---------------------------------------------------------------------------
-- RLS + GRANT explícitos (regra 10) nas três tabelas tocadas
-- ---------------------------------------------------------------------------
-- RLS já está ligado e as policies por `auth.uid()` já cobrem as colunas novas
-- (policy é por linha, não por coluna). Reafirmado aqui de forma idempotente.
alter table public.metricas_saude_diarias enable row level security;
alter table public.coleta_diaria          enable row level security;
alter table public.configuracoes_sistema  enable row level security;

-- `anon` tinha DML completo por default privileges do Supabase; as policies já
-- o bloqueavam, mas sem login não há motivo para ele sequer alcançar estas
-- tabelas (mesma causa do achado do N44: revoke de PUBLIC não remove grant
-- explícito a `anon`). Nenhum fluxo legítimo usa `anon` aqui.
revoke all on table public.metricas_saude_diarias from anon;
revoke all on table public.coleta_diaria          from anon;
revoke all on table public.configuracoes_sistema  from anon;

-- Grants nominais a `authenticated` (já existiam; as policies decidem a linha).
grant select, insert, update on table public.metricas_saude_diarias to authenticated;
grant select, insert, update, delete on table public.coleta_diaria to authenticated;
grant select, insert, update, delete on table public.configuracoes_sistema to authenticated;
