-- [TAREFA 1 - DB] Categorização de alimentos e pesos padrão
-- Missão: Mover inteligência de estimação de peso do Edge Function para o PostgreSQL
-- Integridade: UPDATE APENAS de alimentos confirmados; pendentes vão para CSV de auditoria
--
-- Colunas adicionadas:
--   - categoria_consumo: enum conceitual ('liquido_frio', 'liquido_quente', 'unidade', 'fatia', 'peso_livre')
--   - unidade_medida_padrao: 'g' para sólidos, 'ml' para líquidos
--   - medida_padrao_nome: rótulo amigável ('Copo Pequeno', 'Fatia Média', 'Unidade', etc.)
--   - medida_padrao_qtd: valor numérico exato (5, 20, 30, 250, etc.)

-- ============================================================================
-- 1. Adicionar colunas à tabela alimentos_referencia
-- ============================================================================
alter table alimentos_referencia
  add column categoria_consumo varchar(50),
  add column unidade_medida_padrao varchar(5),
  add column medida_padrao_nome varchar(100),
  add column medida_padrao_qtd numeric(8, 2);

-- ============================================================================
-- 2. UPDATES CONFIRMADOS (Alimentos com certeza absoluta do peso típico)
-- Filosofia: Melhor ser conservador (falsos negativos) do que inflado (falsos positivos)
-- ============================================================================

-- Arroz (já tem medida caseira; categorizar como peso_livre)
update alimentos_referencia
set
  categoria_consumo = 'peso_livre',
  unidade_medida_padrao = 'g',
  medida_padrao_nome = 'Porção padrão',
  medida_padrao_qtd = 100
where nome_taco = 'Arroz, branco, cozido';

-- Feijão (já tem medida caseira; categorizar como peso_livre)
update alimentos_referencia
set
  categoria_consumo = 'peso_livre',
  unidade_medida_padrao = 'g',
  medida_padrao_nome = 'Porção padrão',
  medida_padrao_qtd = 100
where nome_taco = 'Feijão, carioca, cozido';

-- Bife (já tem medida caseira; categorizar como peso_livre)
update alimentos_referencia
set
  categoria_consumo = 'peso_livre',
  unidade_medida_padrao = 'g',
  medida_padrao_nome = 'Porção média',
  medida_padrao_qtd = 100
where nome_taco = 'Carne, bovina, contrafilé, grelhado';

-- Ovo (já tem "unidade média" = 50g; confirmar)
update alimentos_referencia
set
  categoria_consumo = 'unidade',
  unidade_medida_padrao = 'g',
  medida_padrao_nome = 'Unidade',
  medida_padrao_qtd = 50
where nome_taco = 'Ovo, de galinha, frito';

-- Alface (peso_livre)
update alimentos_referencia
set
  categoria_consumo = 'peso_livre',
  unidade_medida_padrao = 'g',
  medida_padrao_nome = 'Porção padrão',
  medida_padrao_qtd = 50
where nome_taco = 'Alface, lisa, crua';

-- ============================================================================
-- 3. INSERTS DE ALIMENTOS CONFIRMADOS (SEM medida caseira cadastrada)
-- Esses são alimentos órfãos que agora ganham categoria + peso
-- ============================================================================

-- Pão de queijo (unidade, 30g)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Pão de queijo',
   array['pao de queijo', 'pãozinho', 'pao queijo', 'biscoito de queijo'],
   'taco',
   324, 10.5, 29.0, 18.0,
   'unidade', 'g', 'Unidade', 30)
on conflict do nothing;

-- Azeitona (unidade, 5g)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Azeitona, preta',
   array['azeitona', 'azeitona preta', 'oliva'],
   'taco',
   265, 1.7, 7.0, 26.8,
   'unidade', 'g', 'Unidade', 5)
on conflict do nothing;

-- Presunto (fatia, 20g)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Presunto',
   array['presunto', 'presunto laticinado'],
   'taco',
   144, 25.0, 1.0, 5.0,
   'fatia', 'g', 'Fatia', 20)
on conflict do nothing;

-- Queijo (fatia, 30g)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Queijo meia cura',
   array['queijo', 'queijo meia cura', 'queijo branco'],
   'taco',
   298, 26.0, 1.0, 23.0,
   'fatia', 'g', 'Fatia', 30)
on conflict do nothing;

-- Coxinha (unidade, 100g)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Coxinha',
   array['coxinha', 'coxinha de frango', 'coxinha de galinha'],
   'usda',
   280, 12.0, 20.0, 16.0,
   'unidade', 'g', 'Unidade', 100)
on conflict do nothing;

-- Pastel (unidade, 100g)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Pastel',
   array['pastel', 'pastel de queijo', 'pastel de carne'],
   'usda',
   280, 10.0, 25.0, 16.0,
   'unidade', 'g', 'Unidade', 100)
on conflict do nothing;

-- Café (líquido quente, 200ml)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Café, coado',
   array['cafe', 'café', 'café coado', 'cafe coado'],
   'taco',
   2, 0.2, 0, 0,
   'liquido_quente', 'ml', 'Xícara padrão', 200)
on conflict do nothing;

-- Chá (líquido quente, 200ml)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Chá, coado',
   array['cha', 'chá', 'chá preto', 'cha preto', 'chá verde', 'cha verde'],
   'taco',
   1, 0, 0, 0,
   'liquido_quente', 'ml', 'Xícara padrão', 200)
on conflict do nothing;

-- Suco Natural (líquido frio, 250ml)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Suco de laranja, natural',
   array['suco', 'suco de laranja', 'suco natural', 'suco fresco'],
   'taco',
   44, 0.7, 10.4, 0.2,
   'liquido_frio', 'ml', 'Copo médio', 250)
on conflict do nothing;

-- Refrigerante (líquido frio, 250ml) — Nota: valores nutricionais típicos de refrigerante normal
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Refrigerante, cola',
   array['refrigerante', 'refrigerante cola', 'refrigerante de cola', 'coca'],
   'usda',
   41, 0, 10.5, 0,
   'liquido_frio', 'ml', 'Copo médio', 250)
on conflict do nothing;

-- Leite (líquido frio, 200ml)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Leite, integral',
   array['leite', 'leite integral', 'leite de vaca'],
   'taco',
   61, 3.3, 4.8, 3.3,
   'liquido_frio', 'ml', 'Copo pequeno', 200)
on conflict do nothing;

-- Água comum/mineral (líquido frio, 0 kcal)
insert into alimentos_referencia
  (nome_taco, aliases, fonte, calorias_kcal_100g, proteinas_g_100g, carboidratos_g_100g, gorduras_g_100g,
   categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd)
values
  ('Água, comum/mineral',
   array['agua', 'água', 'agua mineral', 'agua filtrada', 'agua destilada'],
   'taco',
   0, 0, 0, 0,
   'liquido_frio', 'ml', 'Copo médio', 250)
on conflict do nothing;

-- ============================================================================
-- 3. ÍNDICE para queries rápidas por categoria
-- ============================================================================
create index idx_alimentos_referencia_categoria
  on alimentos_referencia (categoria_consumo)
  where categoria_consumo is not null;

-- ============================================================================
-- 4. COMENTÁRIOS DESCRITIVOS (Parte 0.10 — Documentação SQL)
-- ============================================================================
comment on column alimentos_referencia.categoria_consumo is
  'Tipo de consumo: liquido_frio, liquido_quente, unidade, fatia, peso_livre. Nulo = pendente de revisão.';
comment on column alimentos_referencia.unidade_medida_padrao is
  'Unidade da medida padrão: "g" para sólidos/porções, "ml" para líquidos.';
comment on column alimentos_referencia.medida_padrao_nome is
  'Rótulo amigável para exibição (ex: "Unidade", "Fatia", "Copo Pequeno").';
comment on column alimentos_referencia.medida_padrao_qtd is
  'Quantidade numérica exata (5 para uma azeitona, 200 para uma xícara de café, etc.)';
