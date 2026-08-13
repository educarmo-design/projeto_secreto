# 20260812_0011_seed_problemas_saude — Carga inicial de `problemas_saude`

Log de Máquina (Regra 10.3 — append-only). DML puro (sem alteração de
estrutura) populando o catálogo `problemas_saude` (N09), que nasceu vazio
em `20260811240000_n09_anamnese_versionada_e_gaps_n06.sql`.

## O que foi feito

- Nova migration `20260812230000_seed_problemas_saude_clinicos.sql`:
  `insert into problemas_saude (id, nome) values (gen_random_uuid(),
  '...'), ... on conflict (nome) do nothing;` com os 20 problemas de saúde
  pedidos, em ordem alfabética, exatamente como listados na tarefa.
- `on conflict (nome) do nothing` usa a constraint `unique` que a coluna já
  tinha desde a criação da tabela — reexecutar esta migration (ou rodar
  `db push` de novo num ambiente onde ela já rodou) não duplica nada.
- Nenhuma mudança de DDL — só o `INSERT`, como pedido.

## Verificação

- `npx supabase db push`: migration aplicada sem erro, sem violar
  constraint nenhuma.
- Reconferido direto no banco: as 20 linhas pedidas estão presentes, com
  `id` UUID válido e distinto em cada uma.
- **Achado, não modificado**: a tabela já tinha 1 linha pré-existente antes
  desta migration — `"DIABETE TIPO 2"` (grafia/capitalização diferentes de
  `"Diabetes Mellitus Tipo 2"` da lista pedida, então o `on conflict`
  não a tocou; provavelmente um teste manual anterior feito direto pela
  tela `AdminProblemasSaude.tsx`). Não foi removida — a tarefa autorizou
  inserir dados, não limpar a tabela, e não há como confirmar com certeza
  que é descartável sem confirmação do fundador.
- Não foi necessário alterar nenhum código React/Flutter:
  `AdminProblemasSaude.tsx` e `AnamneseRepository.buscarProblemasSaude()`
  (App Flutter) já liam a tabela ao vivo, sem cache — a lista aparece nos
  dois automaticamente.
