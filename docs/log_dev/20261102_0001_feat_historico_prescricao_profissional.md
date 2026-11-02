# Histórico de Anamnese passa a exibir o Plano de Metas (Motor Metabólico x Prescrição Profissional)

**Tipo:** Feature nova, com auditoria de schema obrigatória (feita antes
de codar) sobre a relação entre `anamneses`, `objetivos_alimentares` e
identificação do profissional.

## Auditoria de Origem e Schema (item 1 da tarefa)

### `objetivos_alimentares` já suporta tudo que a tarefa pediu — sem precisar de coluna/RPC nova

- **Origem (IA vs Profissional)**: coluna `profissional_id` (nullable) —
  `null` = self-service/Motor Metabólico; preenchido = prescrição
  profissional. Já é assim desde `20260812110000` (N08/N10/N11).
- **Metas por dia da semana**: coluna `tipo_dia` (texto livre, default
  `'PADRAO'`) — múltiplas linhas `'ativo'` podem coexistir pro MESMO
  usuário com `tipo_dia` diferentes (ex. `TREINO`/`DESCANSO`, ou os 7
  dias: `SEGUNDA`...`DOMINGO`). Confirmado em
  `web_painel/.../PrescricaoView.tsx` — o profissional já tem, há tempos,
  um seletor "Meta única" vs "Meta por dia" que grava exatamente isso,
  com os 7 códigos de dia prontos (`DIAS_SEMANA`). **Nenhuma migration
  nova foi necessária — a funcionalidade já existia no banco e no Painel
  Web, só nunca tinha chegado ao Histórico de Anamnese do Flutter.**
- **Nome do profissional**: `perfis_usuarios.nome` é PII cifrada e NUNCA
  exposta a outro usuário (nem ao próprio paciente sobre o profissional)
  — a única identificação pública é `nickname` + `tipo_profissional`,
  via a view `perfis_profissionais_vinculados` (sem filtro de `status`,
  cobre vínculo ativo/em carência/encerrado — resolve mesmo um
  profissional que não acompanha mais o paciente hoje). Por isso a UI diz
  "Prescrição Clínica — [nickname] (Nutricionista)", não "Dr(a).
  [Nome]" como a tarefa sugeriu — mesma Restrição de privacidade já
  aplicada em toda a tela de Perfil/Vínculos deste app.

### O que NÃO existe: nenhuma FK entre `anamneses` e `objetivos_alimentares`

Confirmado por busca em todas as migrations: zero referência cruzada
entre as duas tabelas. A correlação "qual meta estava vigente nesta
anamnese" é inteiramente por **janela de tempo** — mesmo princípio de
versionamento que as duas tabelas já usam internamente (mais recente
substitui o anterior):

- Início da janela = `data_preenchimento` da própria anamnese.
- Fim da janela = `data_preenchimento` da PRÓXIMA anamnese do usuário, se
  existir; sem próxima, esta ainda é a vigente → sem limite superior.
- Toda meta (`objetivos_alimentares`, qualquer `profissional_id`/
  `tipo_dia`) com `data_criacao` dentro dessa janela é "a meta decidida
  nesta avaliação".

Isto é uma correlação honesta (não inventada) mas é uma HEURÍSTICA, não
uma garantia de integridade referencial — documentado aqui como
limitação conhecida: se o profissional prescrever uma meta dias DEPOIS
da consulta de anamnese mas ANTES da próxima, ela ainda aparece
corretamente associada (é exatamente o cenário clínico real: "revisei a
anamnese, mando a prescrição por escrito depois").

## GAP CONHECIDO, reafirmado (já documentado no cabeçalho de `HistoricoAnamnesesPage`)

TMB/GET (TDEE) **nunca aparecem** no Plano de Metas, mesmo quando a meta
veio do Motor Metabólico: `calcular_motor_metabolico_v1` é uma função
PURA que nunca persiste resultado (ME-005/ME-006) —
`objetivos_alimentares` só guarda o VET final (`calorias_alvo`) e os
macros, nunca o TMB/GET intermediário que o motor calculou pra chegar
lá. Mostrar só o que de fato foi persistido — nunca recalcular/inventar
um TMB histórico que o sistema não guardou.

## Implementação (item 2/3)

- `MetaResumo` (repositório de Metas): ganha `tipoDia` (default
  `'PADRAO'`) e `profissionalId` (nullable) + getter
  `prescritaPorProfissional`.
- `MetaBemEstarRepository.buscarMetasNoPeriodo({inicio, fim})`: busca
  QUALQUER meta (self-service ou profissional, qualquer `tipo_dia`) no
  intervalo — diferente de `buscarHistoricoMetas` (só self-service, só
  `PADRAO`), que continua intocado (usado só pela Tela de Metas).
- `AnamneseRepository.buscarDataProximaAnamnese(dataPreenchimento)`:
  calcula o fim da janela.
- `VinculosService.buscarNomesProfissionaisVinculados()`: resolve
  nickname/tipo de QUALQUER profissional já vinculado (sem filtro de
  status, ao contrário de `carregarVinculosAtivos`).
- `AnamneseDetalhesPage`: nova seção "Plano de Metas" logo abaixo do
  cabeçalho —
  - **Badge de origem**: "Calculado pelo Motor Metabólico" ou
    "Prescrição Clínica — [nickname] ([tipo])".
  - **Meta única** (1 só `tipo_dia` na janela): card consolidado
    (Calorias + P/C/G).
  - **Metas por dia** (vários `tipo_dia` distintos): lista expansível
    (`ExpansionTile`), uma por `tipo_dia`, cada uma com seu próprio card.
  - **Fallback**: "Sem prescrição/cálculo atrelado a este registro."
    quando a janela não tem nenhuma meta.
  - 100% leitura, reafirmado — nenhum botão/campo editável foi
    adicionado.

## Verificação

- `flutter analyze`: 30 issues (linha de base, zero novo).
- `flutter test`: testes novos cobrindo os 2 cenários pedidos pela
  tarefa — Motor Metabólico padrão (`anamnese_detalhes_page_test.dart`)
  e Prescrição Profissional com metas por dia (idem) — mais o fallback
  sem meta e a janela sem limite superior (anamnese ainda vigente).
  Cobertura de repositório também adicionada:
  `MetaBemEstarRepository.buscarMetasNoPeriodo` (3 testes) e
  `AnamneseRepository.buscarDataProximaAnamnese` (3 testes).

## Banco de dados

Nenhuma migration nova, nenhuma RPC nova — exatamente como a auditoria
previu: tudo que a tarefa pediu já existia no schema (`tipo_dia`,
`profissional_id`, a view de profissionais vinculados); só faltava o
Flutter correlacionar e exibir.

Branch `feat/historico-anamnese-prescricao-profissional`, a partir de
`main`.
