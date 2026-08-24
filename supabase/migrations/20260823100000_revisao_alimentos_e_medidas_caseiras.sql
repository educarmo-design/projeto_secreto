-- RELATÓRIO 20260823_0004 — correção do achado da investigação
-- 20260823_0003 (categoria_consumo nunca chegava no Flutter) + pedido
-- explícito do fundador: curadoria em massa do catálogo TACO
-- (`alimentos_referencia`, 637 linhas) e das medidas caseiras
-- (`alimentos_medidas_caseiras`).
--
-- Parte 1 desta correção: campos de REVISÃO HUMANA — como a curadoria dos
-- 637 alimentos + medidas caseiras vai ser feita em massa por IA (Gemini,
-- ver script `web_painel/scripts/curar_catalogo_alimentos_ia.ts`), qualquer
-- item que a IA não tiver confiança de classificar corretamente precisa
-- ficar SINALIZADO, não silenciosamente errado — mesmo espírito do CSV de
-- auditoria (`docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA*.csv`), mas agora
-- como campo de verdade no banco, visível/filtrável pela tela
-- AdminAlimentos.tsx reformulada (RELATÓRIO 20260823_0004), não um arquivo
-- solto.

alter table alimentos_referencia
  add column revisao_necessaria boolean not null default false,
  add column observacao_revisao text;

alter table alimentos_medidas_caseiras
  add column revisao_necessaria boolean not null default false,
  add column observacao_revisao text;

comment on column alimentos_referencia.revisao_necessaria is
  'true quando o item precisa de revisão/validação humana — curadoria automática (bulk IA ou script) marcou baixa confiança em algum campo (categoria_consumo, aliases, unidade_medida_padrao, etc.). Nunca setado por escrita do cliente comum, só pela curadoria (migration/script) ou pela tela AdminAlimentos.tsx.';
comment on column alimentos_referencia.observacao_revisao is
  'Texto livre explicando POR QUE revisao_necessaria=true (ex.: "nome ambíguo da TACO, categoria de consumo incerta"). Null quando revisao_necessaria=false.';

comment on column alimentos_medidas_caseiras.revisao_necessaria is
  'Mesma semântica de alimentos_referencia.revisao_necessaria, escopada à medida caseira específica (ex.: valor em gramas estimado por IA sem alta confiança para esta medida deste alimento).';
comment on column alimentos_medidas_caseiras.observacao_revisao is
  'Texto livre explicando POR QUE revisao_necessaria=true nesta medida caseira. Null quando revisao_necessaria=false.';

-- Índices parciais — a tela de revisão filtra "só quem precisa de
-- revisão", que é sempre uma minoria das linhas; índice parcial evita
-- escanear tudo.
create index idx_alimentos_referencia_revisao_necessaria
  on alimentos_referencia (revisao_necessaria)
  where revisao_necessaria = true;

create index idx_alimentos_medidas_caseiras_revisao_necessaria
  on alimentos_medidas_caseiras (revisao_necessaria)
  where revisao_necessaria = true;

-- GRANT (Parte 0.10): nenhum adicional necessário — as duas tabelas já têm
-- grant/policy de select para authenticated e insert/update/delete
-- admin-only (20260811230000_n06_escrita_admin_alimentos_e_vinculos.sql);
-- as 2 colunas novas entram automaticamente nesse escopo, sem policy
-- própria.
