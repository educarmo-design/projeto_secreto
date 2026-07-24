-- F45 (Adendo v5.1, seção A.3) — Base nutricional para o cálculo
-- determinístico de calorias/macros do Passo 2 do F10 ("IA traduz, backend
-- calcula", A.2).
--
-- Duas tabelas, no mesmo espírito de `marcadores_referencia`
-- (20260713100000): dicionário estático, dado público do produto (nenhuma
-- linha aqui pertence a um usuário), curado por migration — NUNCA por
-- escrita do cliente.
--
--   1. `alimentos_referencia` — um alimento, com sua composição por 100g
--      (fonte: Tabela TACO/Unicamp; fallback USDA para itens industrializados
--      que a TACO não cobre) e os nomes/sinônimos que o Edge Function usa
--      para casar com o texto solto que o Gemini identifica na foto.
--   2. `alimentos_medidas_caseiras` — quantos gramas cada "medida caseira"
--      (colher de sopa, concha, unidade, fatia...) representa PARA aquele
--      alimento especificamente — a mesma "colher de sopa" pesa coisas
--      diferentes para arroz e para feijão, por isso é 1:N por alimento, não
--      uma tabela de conversão genérica única.
--
-- A.2 é a regra que faz estas tabelas existirem: o Gemini NUNCA calcula
-- caloria/grama — só identifica nome + medida caseira + confiança. Quem
-- multiplica é o Edge Function, consultando estas duas tabelas por uma regra
-- de três determinística. Ver supabase/functions/extract-metric-photo/index.ts.

-- ============================================================================
-- 1. alimentos_referencia
-- ============================================================================
create table alimentos_referencia (
  id uuid primary key default gen_random_uuid(),
  -- Nome canônico exatamente como na tabela-fonte (facilita auditoria/diff
  -- contra a publicação oficial da TACO/USDA).
  nome_taco text not null,
  -- Sinônimos que o texto livre do Gemini pode usar para o mesmo alimento
  -- (ex.: {"arroz", "arroz cozido", "arroz branco"}). O casamento no backend
  -- normaliza acento/caixa e tenta exato -> substring contra nome_taco e
  -- aliases, nesta ordem — nunca inventa um alimento que não está aqui.
  aliases text[] not null default '{}',
  fonte text not null default 'taco' check (fonte in ('taco', 'usda')),
  -- Composição por 100g da porção como seria fotografada no prato (cozida/
  -- preparada, quando aplicável) — é o único número usado no cálculo.
  calorias_kcal_100g numeric(7, 2) not null,
  proteinas_g_100g numeric(6, 2) not null,
  carboidratos_g_100g numeric(6, 2) not null,
  gorduras_g_100g numeric(6, 2) not null,
  criado_em timestamptz not null default now()
);

create index idx_alimentos_referencia_aliases
  on alimentos_referencia using gin (aliases);

alter table alimentos_referencia enable row level security;

-- Dicionário público do produto: todo usuário autenticado lê. Sem policy de
-- escrita para `authenticated` — mesmo padrão de marcadores_referencia,
-- curadoria é migration/service role.
create policy "alimentos_referencia_select_authenticated"
  on alimentos_referencia for select
  to authenticated
  using (true);

-- ============================================================================
-- 2. alimentos_medidas_caseiras
-- ============================================================================
create table alimentos_medidas_caseiras (
  id bigserial primary key,
  alimento_id uuid not null references alimentos_referencia (id) on delete cascade,
  -- Rótulo livre em pt-BR ("colher de sopa", "concha média", "unidade",
  -- "fatia", "xícara") — casado pelo mesmo normalizador do nome do alimento.
  medida text not null,
  gramas numeric(6, 2) not null check (gramas > 0),
  unique (alimento_id, medida)
);

create index idx_alimentos_medidas_caseiras_alimento
  on alimentos_medidas_caseiras (alimento_id);

alter table alimentos_medidas_caseiras enable row level security;

create policy "alimentos_medidas_caseiras_select_authenticated"
  on alimentos_medidas_caseiras for select
  to authenticated
  using (true);

-- ============================================================================
-- 3. GRANT explícito (Parte 0.10 — obrigatório em toda migration)
-- ============================================================================
-- Só SELECT. Sem INSERT/UPDATE/DELETE para `authenticated`: a curadoria do
-- catálogo nutricional é operação de migration/service role, nunca do
-- cliente — mesma regra de marcadores_referencia.
grant select on alimentos_referencia to authenticated;
grant select on alimentos_medidas_caseiras to authenticated;

-- ============================================================================
-- 4. Seed mínimo de validação (Critério de Aceite do Passo 2 do F10)
-- ============================================================================
-- ATENÇÃO — valores de melhor esforço a partir da Tabela TACO (Unicamp, 4ª
-- edição), por 100g da porção cozida/preparada, para DESTRAVAR o teste
-- ponta a ponta do pipeline "IA traduz, backend calcula". Assim como
-- marcadores_referencia nasceu com faixa_referencia NULA até curadoria
-- clínica formal, este seed de 5 itens é o mínimo para provar o cálculo —
-- NÃO é o catálogo nutricional completo nem substitui uma importação
-- oficial linha-a-linha da TACO/USDA (pendência registrada no relatório de
-- fim de tarefa).
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g)
values
  ('Arroz, branco, cozido',
   array['arroz', 'arroz branco', 'arroz cozido', 'arroz branco cozido'],
   'taco', 128, 2.5, 28.1, 0.2),
  ('Feijão, carioca, cozido',
   array['feijao', 'feijão', 'feijao carioca', 'feijão carioca', 'feijao cozido'],
   'taco', 76, 4.8, 13.6, 0.5),
  ('Carne, bovina, contrafilé, grelhado',
   array['bife', 'bife de boi', 'bife grelhado', 'contrafile', 'contrafilé', 'carne bovina grelhada'],
   'taco', 247, 32.7, 0, 12.6),
  ('Ovo, de galinha, frito',
   array['ovo frito', 'ovo', 'ovo de galinha frito'],
   'taco', 197, 13.5, 0.9, 15.8),
  ('Alface, lisa, crua',
   array['alface', 'alface crua', 'alface lisa'],
   'taco', 11, 1.1, 1.7, 0.2);

-- Medidas caseiras por alimento (ver nota acima: conjunto mínimo para o
-- Passo 2, não a lista exaustiva de conversões da TACO).
insert into alimentos_medidas_caseiras (alimento_id, medida, gramas)
select id, medida, gramas
from alimentos_referencia
cross join lateral (
  values
    ('colher de sopa', 25::numeric),
    ('escumadeira', 90::numeric)
) as m(medida, gramas)
where nome_taco = 'Arroz, branco, cozido';

insert into alimentos_medidas_caseiras (alimento_id, medida, gramas)
select id, medida, gramas
from alimentos_referencia
cross join lateral (
  values
    ('concha média', 80::numeric),
    ('colher de sopa', 30::numeric)
) as m(medida, gramas)
where nome_taco = 'Feijão, carioca, cozido';

insert into alimentos_medidas_caseiras (alimento_id, medida, gramas)
select id, medida, gramas
from alimentos_referencia
cross join lateral (
  values
    ('unidade média', 100::numeric),
    ('filé pequeno', 80::numeric)
) as m(medida, gramas)
where nome_taco = 'Carne, bovina, contrafilé, grelhado';

insert into alimentos_medidas_caseiras (alimento_id, medida, gramas)
select id, 'unidade', 50::numeric
from alimentos_referencia
where nome_taco = 'Ovo, de galinha, frito';

insert into alimentos_medidas_caseiras (alimento_id, medida, gramas)
select id, medida, gramas
from alimentos_referencia
cross join lateral (
  values
    ('folha', 15::numeric),
    ('xícara', 30::numeric)
) as m(medida, gramas)
where nome_taco = 'Alface, lisa, crua';
