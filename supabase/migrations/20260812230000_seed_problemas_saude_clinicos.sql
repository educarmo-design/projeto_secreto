-- N09 (RELATÓRIO 20260812_0012) — Carga inicial (seed) de `problemas_saude`.
-- DML puro, sem alteração de estrutura: a tabela (`id uuid pk default
-- gen_random_uuid()`, `nome text unique`) já existe desde
-- `20260811240000_n09_anamnese_versionada_e_gaps_n06.sql` e nasceu vazia —
-- o fundador pediu uma lista curada de patologias clinicamente relevantes
-- pra nutrição, pra padronizar a Anamnese em vez de cada usuário/profissional
-- digitar o nome livremente.
--
-- `on conflict (nome) do nothing` (a coluna já tem `unique`, então o
-- conflito é detectável sem precisar nomear a constraint) — reexecutar esta
-- migration, ou rodar `db push` de novo num ambiente onde ela já rodou, não
-- duplica nada. Ordem alfabética, exatamente a lista pedida.
insert into problemas_saude (id, nome) values
  (gen_random_uuid(), 'Anemia'),
  (gen_random_uuid(), 'Câncer (Oncologia)'),
  (gen_random_uuid(), 'Diabetes Gestacional'),
  (gen_random_uuid(), 'Diabetes Mellitus Tipo 1'),
  (gen_random_uuid(), 'Diabetes Mellitus Tipo 2'),
  (gen_random_uuid(), 'Dislipidemia (Colesterol/Triglicerídeos)'),
  (gen_random_uuid(), 'Doença Celíaca'),
  (gen_random_uuid(), 'Doença de Crohn'),
  (gen_random_uuid(), 'Doença do Refluxo Gastroesofágico (DRGE)'),
  (gen_random_uuid(), 'Doença Renal Crônica'),
  (gen_random_uuid(), 'Esteatose Hepática (Gordura no Fígado)'),
  (gen_random_uuid(), 'Gastrite / Úlcera Gástrica'),
  (gen_random_uuid(), 'Gota / Hiperuricemia'),
  (gen_random_uuid(), 'Hipertensão Arterial Sistêmica (HAS)'),
  (gen_random_uuid(), 'Hipertireoidismo'),
  (gen_random_uuid(), 'Hipotireoidismo'),
  (gen_random_uuid(), 'Osteoporose / Osteopenia'),
  (gen_random_uuid(), 'Retocolite Ulcerativa'),
  (gen_random_uuid(), 'Síndrome do Intestino Irritável (SII)'),
  (gen_random_uuid(), 'Síndrome dos Ovários Policísticos (SOP)')
on conflict (nome) do nothing;
