# RCA — Mapa cross-platform de "Meta" (App x Web x Banco)

**Tipo:** investigação pura (arquitetura/SSOT). Nenhuma linha de código de
produção foi alterada nesta tarefa — só leitura de schema/RPCs/código.

**Gatilho:** fundador detectou uma possível duplicidade de domínio — existe
um formulário de "Meta" na 2ª tela da Anamnese (`ConfirmarAnamnesePage`),
uma tela separada "Meta de Bem-Estar" no Perfil (Flutter), e a interface do
profissional no Painel Web (React) que também define metas — pediu um mapa
exato de onde "Meta" nasce e morre no sistema, antes de decidir unificar.

## Resumo executivo (ACEITE)

**Boa notícia, não totalmente esperada pelo fundador**: para a meta que
realmente importa clinicamente (**calorias/macros alvo**), o sistema **já
é centralizado numa única tabela (`objetivos_alimentares`) atrás de uma
única RPC com governança (`validar_e_salvar_meta`, "Motor de Exceções
N08")** — Flutter (atleta) e React (profissional) chamam literalmente a
mesma função, com um parâmetro (`p_is_profissional`) mudando o
comportamento. O risco específico que o fundador temia — "o paciente
sobrescrevendo a meta prescrita pelo profissional" — **já está bloqueado
em produção**, não é uma lacuna.

**O que de fato está fragmentado**: existe um **SEGUNDO conceito**,
genuinamente diferente, também chamado "Meta" na UI — os campos de
**composição corporal desejada** (`anamneses.meta_peso_desejado_kg` e
companhia), preenchidos tanto pelo atleta (self-service) quanto pelo
profissional, DENTRO do registro de Anamnese, sem nenhuma validação/
governança, e **nunca lidos** por nenhum cálculo de calorias/macros. É
fragmentação de **nomenclatura/UX** (2 coisas diferentes chamadas "Meta"
em telas diferentes), não de **dado duplicado perigoso** (não há 2 cópias
da mesma informação competindo — são informações genuinamente distintas).

## 1. Mapeamento do banco (SSOT)

### 1.1 `objetivos_alimentares` — a meta calórica/macros REAL (SSOT)

Migration `20260812110000_n08_motor_excecoes_n10_n11_objetivos_alimentares.sql`.

```sql
create table objetivos_alimentares (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users (id) on delete cascade,
  profissional_id uuid references auth.users (id) on delete set null, -- NULL = self-service
  tipo_dia text not null default 'PADRAO',       -- permite metas distintas por dia (TREINO/DESCANSO/...)
  calorias_alvo int not null,
  proteina_g int,
  carbo_g int,
  gordura_g int,
  data_criacao timestamptz not null default now(),
  vencimento_em timestamptz,                      -- só N10 (profissional) usa
  status_vigencia text not null default 'ativo' check (status_vigencia in ('ativo', 'historico'))
);
```

- **RLS**: `select` para dono e para profissional com vínculo ATIVO. **Zero
  policy de INSERT/UPDATE/DELETE para `authenticated`** — a única porta de
  escrita é a RPC abaixo (`security definer`).
- **Versionamento automático** (trigger): no máximo 1 linha `'ativo'` por
  `(usuario_id, tipo_dia)` — a anterior vira `'historico'` sozinha a cada
  INSERT novo.

### 1.2 `validar_e_salvar_meta(p_payload jsonb, p_is_profissional boolean)` — o único portão de escrita

RPC `security definer`, dupla via **numa função só** (nunca duas
implementações da mesma regra clínica):

| | `p_is_profissional = false` (atleta, N11) | `p_is_profissional = true` (profissional, N10) |
|---|---|---|
| `usuario_id` | SEMPRE `auth.uid()` (nunca lido do payload — não dá pra criar meta pra outra pessoa) | Lido do payload; exige vínculo ATIVO com o paciente |
| Violação clínica (gordura < 0,6g/kg; calorias < TMB; calorias > 2,5×TMB) | **Hard Block** — `raise exception 'N08_TRAVA_CLINICA...'`, nunca insere | Só `WARNING` no retorno — nunca bloqueia (profissional decide, vê o aviso na tela) |
| Meta ativa já prescrita por profissional (`profissional_id is not null`) | **Bloqueado** — `N08_PRIORIDADE_PROFISSIONAL`: **o atleta não pode sobrescrever** | N/A (é o próprio profissional escrevendo) |
| Carência | 1x/30 dias, só conta metas self-service (`profissional_id is null`) | Sem carência |

Isto **é** a resposta à pergunta "há risco de sobrescrita?" — **não, para
calorias/macros**: a trava `N08_PRIORIDADE_PROFISSIONAL` existe
especificamente para isso, há mais de um mês em produção (RELATÓRIO
`20260812_0010`).

### 1.3 `sugestao_meta` — histórico do que o Motor CALCULOU, nunca a meta ativa

Migration `20260915120000`. Tabela separada, **nunca escrita por**
`validar_e_salvar_meta` **nem lida por ela** — é só o rastro de cada
rodada do Motor Metabólico (`gerar_sugestao_meta`, que internamente chama
`calcular_motor_metabolico` e grava TMB/TDEE/avisos/detalhe por dia da
semana). Virar a meta ATIVA exige uma chamada **separada e explícita** a
`validar_e_salvar_meta` — nunca automático.

### 1.4 `anamneses.meta_*` — o SEGUNDO conceito, genuinamente diferente

Migration `20260918100000` (Bloco 2). Colunas na própria tabela
`anamneses` (não uma tabela própria):

```
meta_peso_desejado_kg           numeric
meta_percentual_gordura_desejado numeric
meta_massa_desejada_kg           numeric
meta_prazo                       date
meta_outro_indicador             text
```

- São **composição corporal DESEJADA** (peso/%gordura/massa alvo + prazo)
  — não calorias/macros diárias.
- Gravadas via `INSERT` comum na própria anamnese (`salvarAnamnese`/
  `profissional_salvar_anamnese`) — **sem RPC própria, sem validação
  clínica, sem trava de prioridade, sem carência**. Qualquer um dos dois
  lados (atleta self-service OU profissional) pode preencher, cada
  preenchimento de anamnese é uma linha nova (anamnese é versionada por
  natureza), sem conceito de "ativo" por campo individual.
- **Confirmado, buscando em todo o backend do Motor**: nenhuma função
  (`calcular_motor_metabolico`, `calcular_motor_metabolico_v1`,
  `gerar_sugestao_meta`, `validar_e_salvar_meta`) lê nenhuma dessas 5
  colunas. Elas existem, são salvas, mas **não alimentam nenhum cálculo**
  — ficam só como contexto/registro no histórico da anamnese
  (`AnamneseHistoricoView` no Web, resumo da própria anamnese).

## 2. Flutter (App do paciente)

| Tela | Grava em | Mecanismo | Lê de |
|---|---|---|---|
| `AnamneseSelfServicePage` → `ConfirmarAnamnesePage` | `anamneses` (incluindo os 5 campos `meta_*` acima) | `AnamneseRepository.salvarAnamnese` → `INSERT` direto (sem RPC) | — |
| `ResultadoMotorMetabolicoPage` ("Salvar Minha Meta", mostrada **imediatamente depois** de confirmar a anamnese) | `objetivos_alimentares` | `MetaBemEstarRepository` → RPC `validar_e_salvar_meta(p_is_profissional: false)` | `calcular_motor_metabolico_v1` (simulação, não escreve nada) |
| `MetaBemEstarPage` (entrada **separada**, pelo menu/Perfil) | `objetivos_alimentares` | **A MESMA** `MetaBemEstarRepository`, mesma RPC | `objetivos_alimentares` (meta atual, pra exibir) + `anamneses` (só pra puxar peso/altura/sexo pro motor) |

**Achado importante**: `MetaBemEstarPage` e `ResultadoMotorMetabolicoPage`
são **2 pontos de entrada de UI diferentes**, mas **não são 2
implementações** — os dois usam a mesma classe `MetaBemEstarRepository`,
que só sabe falar com `validar_e_salvar_meta`. Não há caminho no Flutter
que grave `calorias_alvo`/macros fora dessa RPC.

## 3. React (Painel do profissional)

| Componente | Grava em | Mecanismo | Lê de |
|---|---|---|---|
| `AnamneseProfissionalView.tsx` | `anamneses` (incluindo os 5 campos `meta_*`) | RPC `profissional_salvar_anamnese` | — |
| `PrescricaoView.tsx` | `objetivos_alimentares` | RPC `validar_e_salvar_meta(p_is_profissional: true)` | `objetivos_alimentares` (meta atual do paciente, pra exibir) |
| `MotorMetabolicoCard.tsx` / `MotorMetabolicoV1Card.tsx` | — (só leitura) | `calcular_motor_metabolico`/`_v1` (simulação) | — |
| `InserirMedicaoModal.tsx` | `metricas_saude_diarias` (nova pesagem) | — | dispara recálculo do motor depois de salvar |

**Mesma conclusão do lado Flutter**: só `PrescricaoView.tsx` escreve meta
calórica/macros, e só via `validar_e_salvar_meta`. Nenhum componente do
Painel Web faz `.insert()`/`.update()` direto em `objetivos_alimentares`
(nem poderia — RLS não permite).

## 4. Mapa de calor — onde "Meta" nasce e onde morre

```
                    ┌─────────────────────────────┐
                    │   validar_e_salvar_meta()    │  ← ÚNICO portão de escrita
                    │   (Motor de Exceções N08)    │
                    └───────────────┬───────────────┘
                                    │
                    ┌───────────────▼───────────────┐
         escreve    │     objetivos_alimentares      │   calorias_alvo / proteina_g /
         ambos ──►  │   (SSOT real, 1 ativo por       │   carbo_g / gordura_g
                     │   usuario+tipo_dia, versionado) │
                     └───────────────▲────────────────┘
                                     │ lê (exibir meta atual)
        ┌────────────────────────────┼────────────────────────────┐
        │                            │                             │
┌───────┴────────┐          ┌────────┴────────┐          ┌─────────┴────────┐
│ MetaBemEstarPage│          │ResultadoMotorMeta-│          │ PrescricaoView.tsx│
│  (Flutter,      │          │bolicoPage (Flutter│          │  (React,          │
│  self-service)  │          │ pós-Anamnese)     │          │  profissional)    │
└─────────────────┘          └───────────────────┘          └───────────────────┘
      p_is_profissional=false  p_is_profissional=false        p_is_profissional=true


                    ┌─────────────────────────────┐
                    │   salvarAnamnese() /          │  ← portão SEM governança
                    │   profissional_salvar_anamnese│
                    └───────────────┬───────────────┘
                                    │
                    ┌───────────────▼───────────────┐
                    │   anamneses.meta_peso_desejado_kg │   NUNCA lido por nenhum
                    │   .meta_percentual_gordura_desejado│  cálculo de calorias/
                    │   .meta_massa_desejada_kg /_prazo /│  macros — fica isolado
                    │   .meta_outro_indicador            │
                    └───────────────▲────────────────┘
                                    │
                ┌───────────────────┼───────────────────┐
     ┌──────────┴─────────┐                   ┌──────────┴──────────────┐
     │AnamneseSelfService  │                   │AnamneseProfissionalView  │
     │  Page (Flutter)     │                   │      .tsx (React)        │
     └─────────────────────┘                   └──────────────────────────┘
```

## 5. Risco de sobrescrita — avaliação direta

- **Calorias/macros (`objetivos_alimentares`)**: **sem risco** — a trava
  `N08_PRIORIDADE_PROFISSIONAL` já impede o atleta de sobrescrever uma
  meta com `profissional_id` preenchido; o profissional sempre pode
  (autoridade clínica, correto). Testado/confirmado em produção desde o
  RELATÓRIO `20260812_0010`.
- **Composição corporal desejada (`anamneses.meta_*`)**: **sem risco de
  sobrescrita no sentido técnico** (cada preenchimento de anamnese é uma
  linha NOVA e versionada, nunca um UPDATE que apaga o anterior) — mas
  **com risco real de confusão/expectativa**: nada impede o atleta de
  preencher "quero pesar 70kg até dezembro" na Anamnese (campo opcional,
  sem aviso nenhum de que isso não afeta a meta calórica) e achar que
  isso JÁ é a meta que o app vai perseguir — quando, na prática, é só um
  dado de contexto registrado, e a meta calórica continua precisando ser
  definida separadamente em `MetaBemEstarPage`/`ResultadoMotorMetabolicoPage`.

## 6. Opções de solução (nenhuma implementada — decisão do fundador)

Premissa do Motor Metabólico já é exatamente a arquitetura atual de
`objetivos_alimentares`: "o app sugere (`sugestao_meta`/Motor), o humano
decide (`validar_e_salvar_meta`)" — **não precisa ser reconstruída**, só
precisa decidir o que fazer com o SEGUNDO conceito (`anamneses.meta_*`).

**Opção A — Deixar como está, só esclarecer a UX (menor risco/esforço)**:
renomear a seção da Anamnese de "Meta quantitativa" para algo como
"Objetivo de composição corporal (opcional, registro)" e adicionar uma
frase explícita — "isto não define sua meta de calorias; defina sua meta
diária em [tela de Meta de Bem-Estar]" — com um link/CTA direto pra lá.
Zero mudança de schema/RPC; só i18n + 1 parágrafo de UI.

**Opção B — Conectar os 2 conceitos como SUGESTÃO (preserva "app sugere,
humano decide")**: quando a Anamnese grava `meta_peso_desejado_kg`/
`meta_prazo`, oferecer (nunca aplicar automático) um atalho "Calcular
minha meta de calorias baseado nisso" que leva direto pro Motor/
`ResultadoMotorMetabolicoPage` pré-preenchido — o cálculo calórico
PERMANECE só saindo de `validar_e_salvar_meta`; a composição corporal
desejada passa a ALIMENTAR o motor como um insumo a mais (hoje ele só usa
peso ATUAL, nunca peso DESEJADO), sem fundir as tabelas.

**Opção C — Unificar de verdade num conceito só (maior esforço/risco,
mudança de schema)**: migrar `meta_peso_desejado_kg`/`_percentual_
gordura_desejado`/`_massa_desejada_kg`/`_prazo`/`_outro_indicador` de
`anamneses` para `objetivos_alimentares` (colunas novas, nullable) ou
para uma tabela de metas "física" paralela com o MESMO portão de escrita
(`validar_e_salvar_meta` ganharia esses campos opcionais) — exigiria
migration de dados existentes, atualizar os 2 formulários de Anamnese
(Flutter + React) para parar de gravar esses campos ali, e decidir se
composição corporal desejada também merece as mesmas travas clínicas
(provavelmente sim: "quero pesar 40kg" deveria acionar alguma trava,
igual já acontece com calorias).

**Recomendação (não vinculante)**: Opção A primeiro (baixíssimo risco,
resolve a confusão de nomenclatura que motivou a pergunta) — e avaliar B
depois, como uma melhoria de produto genuína (a Anamnese já pergunta
"quanto você quer pesar", seria natural o Motor usar isso). C só se o
fundador quiser que composição corporal desejada também passe pelas
mesmas travas clínicas que calorias/macros já têm — mudança estrutural
maior, melhor como tarefa própria depois de decidir A/B.

## Verificação técnica desta tarefa

Nenhum código alterado — investigação pura (schema via leitura de
migrations, RPCs via leitura de código SQL, Flutter/React via leitura de
código-fonte). Toda afirmação acima é rastreável para um arquivo/linha
específico citado no texto.
