# Fix — campos obrigatórios "mudos" na Anamnese Nutricional (sem borda/texto vermelho)

**Tipo:** correção de UI/UX (continuação do RELATÓRIO `20261015_0001`).
Nenhuma regra de negócio, schema ou RPC alterada — restrição explícita da
tarefa.

**Gatilho:** fundador testando no mundo real reportou que, embora o alerta
geral (`SnackBar`) ao salvar a Anamnese já funcione (corrigido no
`20261015_0001`), os campos obrigatórios faltantes **não ficam vermelhos
nem mostram texto de erro** — o usuário precisa adivinhar qual campo
corrigir.

## Varredura: quais campos são REALMENTE obrigatórios

Antes de adicionar qualquer `validator`, auditei o modelo de dados
(`AnamneseRascunho`/`DadosComplementaresAnamnese`,
`lib/features/nutricao/data/models/anamnese_models.dart`) pra não inventar
nenhuma regra de negócio nova (restrição explícita). `AnamneseRascunho` só
tem 4 campos verdadeiramente obrigatórios (não-anuláveis no construtor):

| Campo | Já tinha `validator`? | Ficava vermelho antes? |
|---|---|---|
| `alturaCm` (`TextFormField`) | Sim (`_validarAltura`) | **Sim** — já funcionava |
| `pesoKg` (`TextFormField`) | Sim (`_validarPeso`) | **Sim** — já funcionava |
| `sexoBiologico` (`RadioGroup` cru) | **Não** | **Não — "mudo"** |
| `objetivoCodigo` (`RadioGroup` cru) | **Não** | **Não — "mudo"** |

Os outros widgets citados como exemplo na tarefa (Sim/Não de "possui
condição de saúde", Seleção de Atividades, Alergias/Intolerâncias em
chips) foram auditados e confirmados **opcionais** no modelo atual
(`bool? possuiCondicaoSaude`, listas que aceitam vazio, sem `NOT NULL` no
schema nem checagem manual em `_irParaConfirmacao`). **Não foram
envolvidos em `FormField`/`validator`** — fazer isso inventaria uma
obrigatoriedade que não existe hoje, violando a restrição da tarefa.

## Causa raiz

`_sexoSelecionado`/`_objetivoSelecionado` eram checados manualmente **só
dentro de `_irParaConfirmacao`, depois de `validate()`** (ver RELATÓRIO
`20261015_0001`) — `validate()` nunca sabia que esses 2 campos existiam
(são `RadioGroup` cru, não `TextFormField`/`DropdownButtonFormField`, que
só ganham validação e borda vermelha de graça). O check manual só mostrava
um `SnackBar` com o motivo específico (ex. "Escolha um objetivo antes de
salvar"), nunca apontava o widget em si.

## O que mudou

`lib/features/nutricao/presentation/pages/anamnese_self_service_page.dart`:

1. **"Sexo Biológico" e "Objetivo" envolvidos em `FormField<String>`**
   (`_buildSecaoSexoBiologico`/`_buildSecaoObjetivo`) — `validator`
   reaproveita as mensagens que já existiam (`nutricao.sexo_obrigatorio`/
   `nutricao.objetivo_obrigatorio`), `onChanged` do `RadioGroup` chama
   `state.didChange(valor)` além do `setState` de sempre, pra o
   autovalidate (já ligado desde `20261015_0001`) revalidar e limpar o
   erro na hora quando o usuário escolhe uma opção.
2. **Novo helper `_caixaComErro`**: borda vermelha (`Border.all`) +
   `Text(state.errorText)` vermelho logo abaixo, mesmo princípio visual
   que um `TextFormField` já usa nativamente — reaproveitado pelos 2
   campos novos.
3. **Rolagem automática até o 1º erro** (`_rolarParaPrimeiroErro`, chamado
   via `addPostFrameCallback` sempre que `validate()` falha): 4 chaves
   (`GlobalKey`) na ordem em que aparecem na tela (Sexo → Altura → Peso →
   Objetivo — os 4 únicos campos obrigatórios), rola pro primeiro que
   estiver com erro via `Scrollable.ensureVisible`.

## Achado real adicional, durante a implementação do item 3

Escrevendo o teste de rolagem, descobri um problema mais sutil que a
tarefa não previu: **`ListView` (mesmo com `children:` fixo, não
`.builder`) ainda virtualiza** — um widget rolado além do `cacheExtent`
padrão (~250px) é **desmontado**. Um `FormField` desmontado simplesmente
não existe na árvore quando `Form.validate()` roda — não conta como
válido nem inválido, como se não existisse — e `validate()` pode devolver
`true` com "Objetivo" vazio escondido fora da tela (ex.: usuário pula
direto pro fim do formulário de 20+ seções). Sem proteção, isso faria
`_montarRascunho()` quebrar no `_objetivoSelecionado!`/`_sexoSelecionado!`
(capturado pelo try/catch do `20261015_0001`, mas mostrando o SnackBar
genérico de erro inesperado em vez do aviso específico certo).

**Corrigido em 2 camadas** (nunca confiar num mecanismo só, pro mesmo
princípio já usado em outros pontos do arquivo):

1. `scrollCacheExtent: const ScrollCacheExtent.pixels(10000)` no `ListView`
   — cobre o formulário inteiro, nenhum campo é desmontado, `validate()`
   sempre vê todos. Custo aceito de propósito: é um formulário preenchido
   1x, não uma lista infinita — construir tudo de uma vez não pesa como
   pesaria num feed.
2. As 2 checagens manuais de `_objetivoSelecionado`/`_sexoSelecionado`
   **voltaram** em `_irParaConfirmacao` como 2ª camada de defesa (não
   ficaram mortas como eu cheguei a assumir num rascunho inicial desta
   correção) — se `validate()` algum dia perder de vista um dos 2 de
   novo, isto ainda mostra o aviso certo e rola até o campo, em vez de
   deixar `_montarRascunho()` quebrar.

## Verificação

- **4 testes novos/estendidos** em `anamnese_self_service_page_test.dart`:
  1. Teste existente de validação ampliado — confirma que "Escolha o sexo
     biológico antes de salvar"/"Escolha um objetivo antes de salvar"
     aparecem como texto vermelho, não só o `SnackBar` genérico.
  2. Teste novo: autovalidate limpa o erro de Sexo/Objetivo na hora,
     assim que o usuário escolhe uma opção (mesmo comportamento que
     altura/peso já tinham).
  3. Teste novo: salvando com só "Objetivo" faltando, num viewport padrão
     onde ele fica fora da área visível ao alcançar o botão "Salvar", a
     tela rola de volta até ele automaticamente — a ausência do texto de
     erro ANTES de rolar (campo desmontado) e a presença DEPOIS prova que
     o `scrollCacheExtent`/scroll funcionaram juntos.
- `flutter analyze`: 30 issues (linha de base do projeto, zero novo).
- `flutter test`: **518/518** (era 516/516 antes desta tarefa, +2 novos),
  zero regressão.

Branch `fix/anamnese-validadores-visuais`, a partir de `main`.
