-- Etapa Estrutural do B2B — Adendo v4.0, seções C (Dicionário de
-- Biomarcadores), F (Modelo Multi-profissional e Vínculos) e G.1
-- (resultados_exames em EAV).
--
-- Três entregas nesta migration:
--   1. `marcadores_referencia` — tabela-dicionário estática (C.4).
--   2. `vinculos_profissional_paciente` — o vínculo como unidade central de
--      slot e faturamento do SaaS multi-assento (F.2).
--   3. `resultados_exames` — REESTRUTURAÇÃO da tabela existente (colunas
--      fixas, Onda 1.5) para o modelo EAV que G.1 define. Ver bloco 3.
--
-- Zero Trust: um profissional só lê exames de um paciente se existir um
-- vínculo ATIVO entre os dois. Não existe policy que dê a um profissional
-- acesso amplo a pacientes — a permissão é sempre escopada a uma relação
-- que já existe no banco (mesmo princípio de
-- 20260709180000_painel_web_profissional_rls.sql).

-- ============================================================================
-- 1. marcadores_referencia — dicionário de biomarcadores (C.4)
-- ============================================================================
-- Dá à IA o contexto semântico (faixa, direção saudável, categoria) sem
-- hardcode no app, e separa a tradução i18n do dado bruto: o resultado guarda
-- só `marcador_codigo`; o nome exibido em pt/en/es sai daqui.

create type categoria_marcador as enum (
  'metabolico',
  'lipidico',
  'tireoide',
  'figado',
  'rim',
  'sangue',
  'inflamacao',
  'vitaminas_minerais',
  'hormonios',
  'outros'
);

-- Como interpretar o valor contra a faixa: 'maior_melhor' (ex. HDL),
-- 'menor_melhor' (ex. LDL, ApoB) ou 'faixa' (ótimo é estar dentro do
-- intervalo — ex. TSH).
create type direcao_saudavel_marcador as enum (
  'maior_melhor',
  'menor_melhor',
  'faixa'
);

create table marcadores_referencia (
  marcador_codigo text primary key,
  nome_exibicao_pt text not null,
  nome_exibicao_en text not null,
  nome_exibicao_es text not null,
  categoria categoria_marcador not null,
  unidade_padrao text,
  faixa_referencia_min numeric(12, 4),
  faixa_referencia_max numeric(12, 4),
  direcao_saudavel direcao_saudavel_marcador not null,
  criado_em timestamptz not null default now()
);

alter table marcadores_referencia enable row level security;

-- Dicionário é dado público do produto (nenhum dado pessoal): todo usuário
-- autenticado lê. NENHUMA policy de escrita para `authenticated` — a curadoria
-- do dicionário é feita por migration/service role, nunca pelo cliente.
create policy "marcadores_referencia_select_authenticated"
  on marcadores_referencia for select
  to authenticated
  using (true);

-- --- Seed: núcleo brasileiro de reconhecimento do OCR (C.2) ----------------
-- IMPORTANTE — `faixa_referencia_min/max` entram NULAS de propósito. As faixas
-- variam por sexo, idade e metodologia do laboratório; publicá-las aqui como
-- número fixo inventado seria dar ao produto um limiar clínico que ninguém
-- curou. O preenchimento é um passo de CURADORIA CLÍNICA separado (deve ser
-- feito por profissional habilitado, em migration própria).
--
-- Até lá o produto não regride: `resultados_exames` guarda a faixa que o
-- próprio laudo do laboratório trouxe (valor_referencia_min/max, bloco 3), e é
-- essa que a UI usa. A faixa do dicionário é o FALLBACK genérico para quando o
-- PDF não traz faixa nenhuma.
--
-- `direcao_saudavel` e `categoria` já vão preenchidas: são semânticas
-- (não são limiar clínico) e é delas que a IA precisa para ler a série.
insert into marcadores_referencia
  (marcador_codigo, nome_exibicao_pt, nome_exibicao_en, nome_exibicao_es, categoria, unidade_padrao, direcao_saudavel)
values
  -- Metabólico
  ('blood_glucose',    'Glicose de jejum',        'Fasting glucose',       'Glucosa en ayunas',        'metabolico',         'mg/dL',  'faixa'),
  ('hba1c',            'Hemoglobina glicada',     'HbA1c',                 'Hemoglobina glicosilada',  'metabolico',         '%',      'menor_melhor'),
  ('insulin',          'Insulina',                'Insulin',               'Insulina',                 'metabolico',         'µUI/mL', 'faixa'),
  ('homa_ir',          'HOMA-IR',                 'HOMA-IR',               'HOMA-IR',                  'metabolico',         null,     'menor_melhor'),
  -- Lipídico
  ('total_cholesterol','Colesterol total',        'Total cholesterol',     'Colesterol total',         'lipidico',           'mg/dL',  'faixa'),
  ('ldl',              'Colesterol LDL',          'LDL cholesterol',       'Colesterol LDL',           'lipidico',           'mg/dL',  'menor_melhor'),
  ('hdl',              'Colesterol HDL',          'HDL cholesterol',       'Colesterol HDL',           'lipidico',           'mg/dL',  'maior_melhor'),
  ('triglycerides',    'Triglicérides',           'Triglycerides',         'Triglicéridos',            'lipidico',           'mg/dL',  'menor_melhor'),
  ('apob',             'ApoB',                    'ApoB',                  'ApoB',                     'lipidico',           'mg/dL',  'menor_melhor'),
  ('lpa',              'Lp(a)',                   'Lp(a)',                 'Lp(a)',                    'lipidico',           'mg/dL',  'menor_melhor'),
  -- Tireoide
  ('tsh',              'TSH',                     'TSH',                   'TSH',                      'tireoide',           'µUI/mL', 'faixa'),
  ('free_t4',          'T4 livre',                'Free T4',               'T4 libre',                 'tireoide',           'ng/dL',  'faixa'),
  ('t3',               'T3',                      'T3',                    'T3',                       'tireoide',           'ng/dL',  'faixa'),
  -- Fígado
  ('ast',              'AST (TGO)',               'AST (SGOT)',            'AST (TGO)',                'figado',             'U/L',    'menor_melhor'),
  ('alt',              'ALT (TGP)',               'ALT (SGPT)',            'ALT (TGP)',                'figado',             'U/L',    'menor_melhor'),
  ('ggt',              'Gama GT (GGT)',           'GGT',                   'Gamma GT (GGT)',           'figado',             'U/L',    'menor_melhor'),
  -- Rim
  ('creatinine',       'Creatinina',              'Creatinine',            'Creatinina',               'rim',                'mg/dL',  'faixa'),
  ('urea',             'Ureia',                   'Urea',                  'Urea',                     'rim',                'mg/dL',  'faixa'),
  ('egfr',             'Taxa de filtração glomerular (TFG)', 'eGFR',       'Tasa de filtración glomerular', 'rim',           'mL/min/1.73m²', 'maior_melhor'),
  ('microalbuminuria', 'Microalbuminúria',        'Microalbuminuria',      'Microalbuminuria',         'rim',                'mg/L',   'menor_melhor'),
  -- Sangue (hemograma: agregado + componentes que o PDF brasileiro reporta)
  ('cbc',              'Hemograma completo',      'Complete blood count',  'Hemograma completo',       'sangue',             null,     'faixa'),
  ('hemoglobin',       'Hemoglobina',             'Hemoglobin',            'Hemoglobina',              'sangue',             'g/dL',   'faixa'),
  ('hematocrit',       'Hematócrito',             'Hematocrit',            'Hematocrito',              'sangue',             '%',      'faixa'),
  ('leukocytes',       'Leucócitos',              'Leukocytes',            'Leucocitos',               'sangue',             '/mm³',   'faixa'),
  ('platelets',        'Plaquetas',               'Platelets',             'Plaquetas',                'sangue',             '/mm³',   'faixa'),
  -- Inflamação
  ('hs_crp',           'PCR ultrassensível',      'hs-CRP',                'PCR ultrasensible',        'inflamacao',         'mg/L',   'menor_melhor'),
  ('homocysteine',     'Homocisteína',            'Homocysteine',          'Homocisteína',             'inflamacao',         'µmol/L', 'menor_melhor'),
  -- Vitaminas / minerais
  ('vitamin_d',        'Vitamina D (25-OH)',      'Vitamin D (25-OH)',     'Vitamina D (25-OH)',       'vitaminas_minerais', 'ng/mL',  'faixa'),
  ('vitamin_b12',      'Vitamina B12',            'Vitamin B12',           'Vitamina B12',             'vitaminas_minerais', 'pg/mL',  'faixa'),
  ('ferritin',         'Ferritina',               'Ferritin',              'Ferritina',                'vitaminas_minerais', 'ng/mL',  'faixa'),
  ('iron',             'Ferro sérico',            'Serum iron',            'Hierro sérico',            'vitaminas_minerais', 'µg/dL',  'faixa'),
  -- Hormônios
  ('testosterone',     'Testosterona total',      'Total testosterone',    'Testosterona total',       'hormonios',          'ng/dL',  'faixa'),
  ('cortisol',         'Cortisol',                'Cortisol',              'Cortisol',                 'hormonios',          'µg/dL',  'faixa'),
  -- Outros
  ('uric_acid',        'Ácido úrico',             'Uric acid',             'Ácido úrico',              'outros',             'mg/dL',  'faixa');

-- ============================================================================
-- 2. vinculos_profissional_paciente — motor do SaaS multi-assento (F.2)
-- ============================================================================
create type status_vinculo as enum ('ativo', 'em_carencia', 'encerrado');
create type tipo_pagador_vinculo as enum ('profissional', 'individual');
create type tipo_produto_vinculo as enum ('com_garmin', 'sem_garmin');

create table vinculos_profissional_paciente (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null references auth.users (id) on delete cascade,
  paciente_id uuid not null references auth.users (id) on delete cascade,
  status status_vinculo not null default 'ativo',
  -- Quem paga ESTE vínculo. F.2: o mesmo paciente pode ser acompanhado por
  -- vários profissionais ao mesmo tempo, e cada um paga o seu próprio acesso
  -- (N vínculos = N slots, um por profissional — não é cobrança dupla).
  tipo_pagador tipo_pagador_vinculo not null default 'profissional',
  -- Herdado do pacote do profissional; é o que habilita/desabilita o botão
  -- "enviar treino ao Garmin" NESTE relacionamento.
  tipo_produto tipo_produto_vinculo not null default 'sem_garmin',
  data_inicio date not null default current_date,
  data_saida date,
  fim_carencia date,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint vinculo_sem_autovinculo check (profissional_id <> paciente_id)
);

-- Um profissional não pode ter DOIS vínculos vivos com o mesmo paciente — isso
-- inflaria a contagem de slots do pacote dele (F.2: "o vínculo consome 1 slot"
-- e a contagem de pacientes ativos = nº de vínculos ativos). Parcial de
-- propósito: `encerrado` fica de fora, então re-vincular um ex-paciente
-- continua possível sem apagar o histórico do vínculo antigo.
create unique index uniq_vinculo_vivo_por_par
  on vinculos_profissional_paciente (profissional_id, paciente_id)
  where status <> 'encerrado';

-- Contagem de slots e lista de pacientes do painel web.
create index idx_vinculos_profissional_status
  on vinculos_profissional_paciente (profissional_id, status);

-- Caminho quente das policies de RLS abaixo (`exists` por paciente) e da
-- verificação server-side de "acesso ativo" no login/refresh (F.5/F41).
create index idx_vinculos_paciente_status
  on vinculos_profissional_paciente (paciente_id, status);

alter table vinculos_profissional_paciente enable row level security;

-- Leitura: os dois lados da relação. O paciente PRECISA ver os próprios
-- vínculos — é o que sustenta a promessa de F.3 ("você decide exatamente o que
-- cada profissional vê"): não dá para revogar o que não se enxerga.
create policy "vinculos_select_participantes"
  on vinculos_profissional_paciente for select
  using (auth.uid() = profissional_id or auth.uid() = paciente_id);

-- NENHUMA policy de INSERT/UPDATE/DELETE para `authenticated`, de propósito.
-- O vínculo é a unidade de FATURAMENTO (F.2): se o cliente pudesse inserir a
-- própria linha via REST, um profissional criaria slots ilimitados sem passar
-- pelo teto do pacote que ele paga — a cobrança por faixa deixaria de valer.
-- Criar/encerrar vínculo é operação server-side (Edge Function com service
-- role, que valida o pacote e o teto de slots antes de gravar), mesma
-- justificativa de `esteira_trial_estado` e `garmin_conexoes`.

-- ============================================================================
-- 3. resultados_exames — de colunas fixas para EAV (G.1)
-- ============================================================================
-- A tabela JÁ EXISTE (criada em 20260708174650_reestruturacao_colunas_fixas_
-- onda_1_5.sql com `tipo_exame` em texto livre) e já é lida em produção pela
-- Pasta Digital de Exames do dashboard sênior. G.1 do Adendo v4 SUBSTITUI essa
-- modelagem pelo formato longo/EAV, então aqui ela é reestruturada NO LUGAR —
-- não recriada — para preservar as linhas existentes.
--
-- Renomear em vez de dropar+criar mantém os dados, e o Postgres reescreve
-- sozinho as policies e o índice que referenciam as colunas renomeadas (guarda
-- a expressão já parseada, não o texto), então `resultados_exames_select_own`
-- e as demais continuam válidas apontando para o novo nome da coluna.

alter table resultados_exames rename column usuario_id_anonimo to usuario_id;
-- O rename de coluna não renomeia a FK, que ficaria como
-- `resultados_exames_usuario_id_anonimo_fkey` — nome de uma coluna que não
-- existe mais.
alter table resultados_exames
  rename constraint resultados_exames_usuario_id_anonimo_fkey
  to resultados_exames_usuario_id_fkey;
alter table resultados_exames rename column valor_resultado to valor_numerico;
alter table resultados_exames rename column unidade_medida to unidade;
alter table resultados_exames rename column data_exame to data_coleta;

alter table resultados_exames
  add column marcador_codigo text references marcadores_referencia (marcador_codigo),
  add column valor_texto text,
  -- G.1: 'pdf_exame' é a origem-padrão (o exame vem do PDF que o usuário
  -- enviou). Fica extensível para entrada manual / integração direta de lab.
  add column origem text not null default 'pdf_exame'
    check (origem in ('pdf_exame', 'manual', 'integracao_laboratorio')),
  -- C.3 ("guarda graciosamente o valor bruto do que não conhece"): o rótulo
  -- exatamente como saiu do laudo. É o que evita perder dado quando o OCR
  -- encontra um exame fora do dicionário — e é o destino do antigo
  -- `tipo_exame` no backfill abaixo.
  add column rotulo_original text;

-- Backfill: o `tipo_exame` em texto livre vira (a) o código normalizado, quando
-- reconhecido no dicionário, e (b) SEMPRE o rótulo original, reconhecido ou
-- não. Linhas cujo exame não está no núcleo C.2 ficam com `marcador_codigo`
-- nulo e o rótulo preservado — nenhuma linha é perdida nem inventada.
update resultados_exames
set
  rotulo_original = tipo_exame,
  marcador_codigo = case lower(trim(tipo_exame))
    when 'glicose'                then 'blood_glucose'
    when 'glicemia'               then 'blood_glucose'
    when 'glicose de jejum'       then 'blood_glucose'
    when 'glicemia de jejum'      then 'blood_glucose'
    when 'hba1c'                  then 'hba1c'
    when 'hemoglobina glicada'    then 'hba1c'
    when 'insulina'               then 'insulin'
    when 'homa-ir'                then 'homa_ir'
    when 'colesterol total'       then 'total_cholesterol'
    when 'ldl'                    then 'ldl'
    when 'colesterol ldl'         then 'ldl'
    when 'hdl'                    then 'hdl'
    when 'colesterol hdl'         then 'hdl'
    when 'triglicerides'          then 'triglycerides'
    when 'triglicérides'          then 'triglycerides'
    when 'triglicerídeos'         then 'triglycerides'
    when 'apob'                   then 'apob'
    when 'apolipoproteína b'      then 'apob'
    when 'lp(a)'                  then 'lpa'
    when 'lipoproteína (a)'       then 'lpa'
    when 'tsh'                    then 'tsh'
    when 't4 livre'               then 'free_t4'
    when 't3'                     then 't3'
    when 'ast'                    then 'ast'
    when 'tgo'                    then 'ast'
    when 'alt'                    then 'alt'
    when 'tgp'                    then 'alt'
    when 'ggt'                    then 'ggt'
    when 'gama gt'                then 'ggt'
    when 'creatinina'             then 'creatinine'
    when 'ureia'                  then 'urea'
    when 'uréia'                  then 'urea'
    when 'tfg'                    then 'egfr'
    when 'egfr'                   then 'egfr'
    when 'microalbuminúria'       then 'microalbuminuria'
    when 'hemograma'              then 'cbc'
    when 'hemograma completo'     then 'cbc'
    when 'hemoglobina'            then 'hemoglobin'
    when 'hematócrito'            then 'hematocrit'
    when 'leucócitos'             then 'leukocytes'
    when 'plaquetas'              then 'platelets'
    when 'pcr'                    then 'hs_crp'
    when 'pcr ultrassensível'     then 'hs_crp'
    when 'proteína c reativa'     then 'hs_crp'
    when 'homocisteína'           then 'homocysteine'
    when 'vitamina d'             then 'vitamin_d'
    when 'vitamina b12'           then 'vitamin_b12'
    when 'b12'                    then 'vitamin_b12'
    when 'ferritina'              then 'ferritin'
    when 'ferro'                  then 'iron'
    when 'testosterona'           then 'testosterone'
    when 'cortisol'               then 'cortisol'
    when 'ácido úrico'            then 'uric_acid'
    when 'acido urico'            then 'uric_acid'
    else null
  end;

alter table resultados_exames drop column tipo_exame;

-- Colunas PRESERVADAS da Onda 1.5 (G.1 não as lista, mas dropá-las seria perda
-- de dado e regressão de feature):
--   `valor_referencia_min` / `valor_referencia_max` — a faixa que O PRÓPRIO
--     LAUDO daquele laboratório reportou. É mais fiel que a faixa genérica do
--     dicionário (varia por método, sexo e idade), e é o que a Pasta Digital
--     usa hoje para marcar um resultado fora da faixa. O dicionário (C.4) é o
--     fallback para quando o PDF não traz faixa.
--   `observacoes` — texto livre do laudo já gravado nas linhas existentes.
--
-- Toda linha precisa identificar O QUE foi medido (código normalizado ou, na
-- pior hipótese, o rótulo bruto do laudo) e carregar ALGUM valor (numérico ou,
-- para resultados não-numéricos — "não reagente", "negativo" —, textual). Sem
-- isso a linha é ruído na série temporal.
--
-- `resultados_exames_identifica_marcador` valida imediatamente: `tipo_exame`
-- era NOT NULL, então toda linha legada saiu do backfill com `rotulo_original`
-- preenchido. Já `resultados_exames_tem_valor` entra NOT VALID: `valor_numerico`
-- sempre foi nulável, e uma linha antiga sem valor nenhum faria esta migration
-- ABORTAR em produção. NOT VALID passa a exigir a regra de toda escrita nova
-- sem varrer o passado; um `validate constraint` pode vir depois, junto da
-- limpeza dessas linhas (se existirem).
alter table resultados_exames
  add constraint resultados_exames_identifica_marcador
    check (marcador_codigo is not null or rotulo_original is not null),
  add constraint resultados_exames_tem_valor
    check (valor_numerico is not null or valor_texto is not null) not valid;

-- Índice composto exigido por G.1: é o caminho da série temporal por marcador
-- ("evolução do LDL deste usuário"), que é como a IA e o painel do profissional
-- leem exame. O índice antigo (usuario_id, data_coleta desc) sobrevive ao
-- rename e continua servindo à timeline cronológica da Pasta Digital.
create index idx_resultados_exames_usuario_marcador_data
  on resultados_exames (usuario_id, marcador_codigo, data_coleta desc);

-- --- RLS: leitura do profissional cruzada com o vínculo ativo --------------
-- As policies de SELECT/INSERT/UPDATE "own" herdadas da Onda 1.5 continuam
-- valendo (o dono do dado lê e escreve o próprio dado, e nada mais).
--
-- Esta acrescenta a ÚNICA porta de leitura de terceiro: o profissional. Ela é
-- permissiva (soma-se à "own", não a substitui) e o `exists` é o Zero Trust —
-- sem uma linha ATIVA em vinculos_profissional_paciente ligando os dois, o
-- profissional não enxerga uma única linha de exame do paciente.
--
-- `status = 'ativo'` (e não `<> 'encerrado'`) é deliberado: vínculo
-- `em_carencia` NÃO dá leitura. A carência existe para o paciente manter o
-- acesso dele ao próprio app enquanto decide (F.5) — não para estender o acesso
-- do profissional a um paciente que já saiu da carteira.
--
-- Nenhuma policy de escrita para o profissional: exame é dado do paciente, e o
-- profissional lê. Quem escreve é o dono (ou a Edge Function de extração do PDF
-- com service role).
create policy "resultados_exames_select_profissional_vinculado"
  on resultados_exames for select
  using (
    exists (
      select 1
      from vinculos_profissional_paciente v
      where v.profissional_id = auth.uid()
        and v.paciente_id = resultados_exames.usuario_id
        and v.status = 'ativo'
    )
  );

-- ============================================================================
-- 4. GRANTs explícitos ao papel `authenticated`
-- ============================================================================
-- RLS filtra LINHAS, mas só depois de o papel ter privilégio na TABELA. O
-- Postgres do Supabase atual tem os default privileges endurecidos: uma tabela
-- criada por `postgres` no schema public nasce com `authenticated=Dxtm`
-- (TRUNCATE/REFERENCES/TRIGGER) e NENHUM select/insert/update. Confirmado neste
-- repositório rodando `supabase db reset` num banco limpo: sem os grants
-- abaixo, o cliente leva "permission denied for table resultados_exames" e as
-- policies acima nunca chegam a ser avaliadas.
--
-- Por isso os grants são explícitos, e no menor privilégio que cada policy já
-- pressupõe — não `grant all`:
grant select on marcadores_referencia to authenticated;
-- Escrita no dicionário é curadoria (migration/service role), nunca do cliente.

grant select on vinculos_profissional_paciente to authenticated;
-- Sem insert/update/delete: criar ou encerrar vínculo é server-side, senão o
-- profissional emite os próprios slots e fura o teto do pacote que paga.

grant select, insert, update on resultados_exames to authenticated;
-- Sem delete: apagar exame é operação de titular via LGPD, não do dia a dia.
