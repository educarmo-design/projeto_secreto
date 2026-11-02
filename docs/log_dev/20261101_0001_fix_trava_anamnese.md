# Trava de "1x a cada 30 dias" bloqueava quem já estava com anamnese vencida

**Tipo:** Bug real, confirmado no device físico (jornada de Time Travel —
fundador forçou `anamneses.data_validade` pro passado via SQL, ver
RELATÓRIO anterior). Dashboard reagiu corretamente ("Anamnese vencida"),
mas `AnamneseSelfServicePage` recusava reabrir o formulário.

## Caça ao bug

Busca pelas strings exatas da mensagem ("Anamnesse ja preenchida
recentemente", "1x a cada 30 dias") encontra as chaves i18n
`nutricao.anamnese_carencia_titulo`/`anamnese_carencia_mensagem`, usadas em
exatamente um lugar: `AnamneseSelfServicePage._carregar()`
(`lib/features/nutricao/presentation/pages/anamnese_self_service_page.dart`).

**Não há nenhuma RPC/trava server-side equivalente** — confirmado por busca
em todas as migrations: a policy `anamneses_insert_own` é uma RLS comum
(`auth.uid() = usuario_id`, sem nenhuma restrição de tempo), e
`anamneses_trg_versionar` só marca a anamnese anterior como `historico` no
INSERT — nunca bloqueia um INSERT novo por recência. A trava era **100%
client-side**, Flutter puro.

## A divergência de regras, exatamente como a tarefa hipotetizou

```dart
const _carenciaDias = 30;
...
if (anamneseAtiva != null) {
  final liberaEm = anamneseAtiva.dataPreenchimento.add(const Duration(days: _carenciaDias));
  if (liberaEm.isAfter(DateTime.now())) { /* bloqueia */ }
}
```

Esta conta usa **só `dataPreenchimento`** — nunca olha
`anamneses.data_validade` nem o parâmetro `anamnese_dias_validade_padrao`
(`configuracoes_sistema`). Enquanto isso, o aviso "Anamnese vencida" do
Dashboard (`AnamneseValidadeBanner`) e o bloqueio severo de
`MetaBemEstarPage` (40+ dias) já usam uma régua PURA e compartilhada,
[`AnamneseValidadeStatus.calcular(dataValidade)`](../../lib/features/nutricao/domain/anamnese_validade_status.dart)
— duas réguas diferentes pra mesma pergunta ("esta anamnese ainda vale?").
Resultado real no device: o fundador zera `data_validade` via SQL, o
Dashboard (régua 1) já mostra "vencida", mas `AnamneseSelfServicePage`
(régua 2, baseada só em `dataPreenchimento`) continuava contando os 30
dias dela mesma e bloqueando.

## Correção — unificação, não invenção de regra nova

`AnamneseSelfServicePage._carregar()` passa a chamar
`AnamneseRepository.buscarDataValidadeAnamnese()` (método que já existia,
já usado por `MetaBemEstarPage`/`AnamneseValidadeBanner` — zero RPC nova) e
decidir com a MESMA `AnamneseValidadeStatus.calcular()`:

```dart
if (anamneseAtiva != null && dataValidade != null) {
  final statusValidade = AnamneseValidadeStatus.calcular(dataValidade);
  if (statusValidade.nivel == AnamneseValidadeNivel.ok) {
    // bloqueia — só enquanto ainda falta mais de 7 dias pra vencer
  }
}
```

- `const _carenciaDias = 30` e a conta antiga foram removidos — não existe
  mais nenhuma régua própria nesta tela.
- **Restrição "não quebrar quem preenche por 1ª vez"**: sem anamnese
  vigente, `anamneseAtiva == null` nem entra no `if` — comportamento
  idêntico ao de antes.
- **Defesa em profundidade (Regra 23)**: uma anamnese vigente de ANTES do
  RELATÓRIO 20260922_0001 (quando a coluna `data_validade` foi criada, sem
  backfill das linhas antigas) tem `dataValidade == null` mesmo com
  `anamneseAtiva != null` — `AnamneseValidadeStatus.calcular(null)`
  devolveria `ok` (seu contrato é "sem data, nada a bloquear" — pensado pra
  "ninguém logado ainda"), mas aqui já se sabe que HÁ anamnese. Em vez de
  confiar nesse `ok` pra travar sem nenhum dado real de validade, o `if`
  exige `dataValidade != null` explicitamente — nunca bloqueia sem saber a
  data, nunca pior do que a trava removida.
- `_dataProximaLiberacao` (usado na mensagem "disponível em {{data}}")
  passa a ser a própria `data_validade`, não mais uma conta derivada de
  `dataPreenchimento` — a mensagem de carência agora informa a data real
  de vencimento.

## O que NÃO foi tocado (e por quê)

Duas outras ocorrências de `_carenciaDias = 30` existem no código, e são
coisas DIFERENTES deste bug — não eram o mesmo problema disfarçado:

- `historico_anamneses_page.dart`: só texto informativo ("próxima revisão
  disponível em X"), nunca um bloqueio — tela 100% leitura, sem formulário
  pra travar. Fora do escopo.
- `meta_bem_estar_page.dart`: a carência de **1x por mês pra redefinir a
  META de calorias/macros** (N08/N11) — uma regra de negócio deliberada e
  completamente independente da validade da anamnese. Não é a mesma régua
  duplicada; é outra régua, de outro domínio, que continua correta.

## Verificação

- `test/features/nutricao/presentation/pages/anamnese_self_service_page_test.dart`:
  os 2 testes antigos da trava (baseados em "dias desde o preenchimento")
  foram substituídos por um novo grupo baseado em `data_validade`/
  `AnamneseValidadeStatus` — cobrindo exatamente o ACEITE da tarefa
  (`data_validade` no passado NÃO bloqueia, mesmo preenchida há poucos
  dias) + o caso defensivo de `data_validade` nula numa anamnese vigente.
- `flutter analyze`: 30 issues (linha de base, zero novo).
- `flutter test`: **556/556** (era 554/554, +2).

## Banco de dados

Nenhuma migration nova, nenhuma RPC nova — não havia trava server-side
nenhuma pra corrigir (confirmado na investigação). Toda a correção é
Flutter.

Branch `fix/trava-renovacao-anamnese`, a partir de `main`.
