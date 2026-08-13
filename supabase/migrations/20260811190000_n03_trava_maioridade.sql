-- N03 (RELATÓRIO 20260811_0005, ajuste do fundador) — trava de maioridade
-- (18+) nas TRÊS pontas: banco (este arquivo), Painel Web React (client-side)
-- e App Flutter (client-side). O banco é a barreira REAL (Zero Trust, mesmo
-- princípio de toda RLS deste projeto) — as duas validações client-side são
-- só UX, evitando a viagem de rede pra descobrir um erro que já dava pra
-- saber na hora. Sem esta constraint, um cliente malicioso que ignorasse as
-- duas telas conseguiria gravar qualquer data de nascimento.

-- ============================================================================
-- 1. CHECK constraint — bloqueia data_nascimento de menor de 18 anos
-- ============================================================================
-- NOT VALID de propósito (mesmo padrão já usado em
-- 20260713100000_estruturas_b2b_v4.sql para constraint nova sobre tabela com
-- dado existente): não há garantia de que toda linha já gravada de
-- data_nascimento (mesmo sendo "só contas de teste", D2 §9.1) já respeita
-- 18+, e falhar a migration inteira por causa de uma linha antiga seria
-- pior do que só travar dado NOVO a partir de agora. NULL passa livre —
-- ninguém é forçado a preencher retroativamente.
alter table perfis_usuarios
  add constraint perfis_usuarios_maioridade
  check (
    data_nascimento is null
    or data_nascimento <= current_date - interval '18 years'
  )
  not valid;

comment on constraint perfis_usuarios_maioridade on perfis_usuarios is
  'N03 (RELATÓRIO 20260811_0005): bloqueia INSERT/UPDATE com data_nascimento de menor de 18 anos. NOT VALID — não revalida linhas antigas, só trava escrita nova. Espelhada por validação client-side no Painel Web (LoginPage.tsx) e no App Flutter (perfil_usuario_page.dart), mas esta é a barreira real.';

-- ============================================================================
-- 2. Função de idade — NÃO é coluna gerada
-- ============================================================================
-- Postgres exige que a expressão de uma coluna GERADA (`generated always as
-- (...) stored`) seja IMUTÁVEL — só pode depender de OUTRAS colunas da MESMA
-- linha, nunca do relógio. "Idade a partir de hoje" depende de CURRENT_DATE,
-- que muda todo dia — não é imutável, o Postgres rejeita essa definição na
-- hora de criar a coluna. Uma função STABLE (não IMMUTABLE, por causa do
-- CURRENT_DATE; não SECURITY DEFINER, porque não lê nada sensível — só faz
-- aritmética sobre o argumento recebido) é o jeito correto de expressar
-- "idade derivada de data_nascimento" no Postgres.
create or replace function public.calcular_idade(p_data_nascimento date)
returns int
language sql
stable
set search_path = ''
as $$
  select case
    when p_data_nascimento is null then null
    else extract(year from age(current_date, p_data_nascimento))::int
  end;
$$;

comment on function public.calcular_idade(date) is
  'Idade em anos completos a partir de data_nascimento — N03, RELATÓRIO 20260811_0005. Não é generated column (CURRENT_DATE não é IMMUTABLE). Uso: select id, calcular_idade(data_nascimento) as idade from perfis_usuarios — RLS da tabela-base continua se aplicando normalmente (a função não eleva privilégio, só calcula sobre o valor já visível ao chamador).';

grant execute on function public.calcular_idade(date) to authenticated;

-- ============================================================================
-- GRANT (Parte 0.10): nenhum novo necessário em perfis_usuarios — já concede
-- select/insert/update a authenticated desde migrations anteriores; a CHECK
-- constraint nova só restringe QUAIS valores passam, não quem pode escrever.
