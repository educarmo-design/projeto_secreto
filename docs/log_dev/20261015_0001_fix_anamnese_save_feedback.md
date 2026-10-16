# Fix — "falha silenciosa" no botão Salvar da Anamnese Nutricional

**Tipo:** RCA + correção (UI/UX e tratamento de erros, sem mudar regras de
negócio ou estrutura de banco — restrição explícita da tarefa).

**Gatilho:** fundador reportou, em fase de testes reais, que na tela de
Anamnese Nutricional (Flutter) o botão "Salvar" às vezes "não faz nada" —
sem indicar campos obrigatórios faltando nem erro de payload.

## Arquitetura real do fluxo (achado necessário antes de corrigir)

"Salvar" na Anamnese tem 2 telas, não 1:

1. **`AnamneseSelfServicePage`** (`lib/features/nutricao/presentation/pages/
   anamnese_self_service_page.dart`) — o formulário longo em si (20+ seções).
   O botão "Salvar" aqui **nunca grava no backend** — só valida, monta um
   `AnamneseRascunho` em memória e navega pra tela de confirmação (decisão
   de produto de RELATÓRIO 20260918_0001, "Confirme seus dados antes de
   enviar").
2. **`ConfirmarAnamnesePage`** (`confirmar_anamnese_page.dart`) — só-leitura,
   mostra o resumo. O botão "Confirmar e Enviar" aqui é quem de fato chama
   `AnamneseRepository.salvarAnamnese` (grava no Supabase).

O bug relatado — "clico em Salvar e nada acontece" — é quase certamente na
**primeira** tela (`AnamneseSelfServicePage`), onde a falha é de fato
silenciosa. A segunda tela já tinha a estrutura correta (try/catch, loading,
SnackBar), mas com uma falha menor própria (ver Achado 3).

## Achado 1 (causa raiz do "nada acontece") — `_irParaConfirmacao`

```dart
void _irParaConfirmacao() {
  if (!(_formKey.currentState?.validate() ?? false)) return;
  ...
```

`validate()` já pinta CADA campo inválido individualmente com o texto do
seu `validator` — isso nunca foi o problema em si. O problema real: **num
formulário com 20+ seções (Objetivo, Composição Corporal, Alimentação,
Rotina por Dia da Semana, Sono, Condições, Medicamentos...), o campo
inválido quase sempre está fora da área visível** perto do botão "Salvar"
(que fica no final da lista). O `return` silencioso não dava NENHUM sinal
de que algo precisava de atenção — pra quem está olhando o botão, "nada
aconteceu" é exatamente a experiência real, mesmo o Flutter tecnicamente
tendo mostrado um erro em algum lugar acima, fora da tela.

Confirmado também: **nenhum `AutovalidateMode` era passado ao `Form`**
(implicitamente `AutovalidateMode.disabled`, o padrão do Flutter) — os
campos só validam quando `validate()` é chamado manualmente, nunca
reagem em tempo real enquanto o usuário digita, mesmo depois de já ter
tentado salvar e falhado.

## Achado 2 — montagem do payload sem nenhuma proteção

Entre a validação e a navegação, `_irParaConfirmacao` monta
`DadosComplementaresAnamnese` e `AnamneseRascunho` inteiros (20+ campos,
parsing numérico de altura/peso/metas/composição corporal, blocos
condicionais Atleta/Idoso/Diabetes/Renal/Recomposição) **sem try/catch
nenhum**. Qualquer exceção nesse trecho (hoje improvável, já que os campos
numéricos obrigatórios — altura/peso — têm `validator` que já garante
`double.tryParse` não-nulo antes de chegar no `double.parse` cru; mas sem
nenhuma garantia formal disso se o form mudar no futuro) derrubaria o
método inteiro em silêncio, mesmo efeito prático do Achado 1.

## Achado 3 — `ConfirmarAnamnesePage` descartava a mensagem real do erro

```dart
} catch (_) {
  ...
  showSnackBar(SnackBar(content: Text(i18n.tr('nutricao.save_error')), ...));
}
```

Esta tela **já tinha** try/catch, loading (`_enviando`/
`CircularProgressIndicator`) e SnackBar — não era uma falha silenciosa.
Mas `catch (_)` descartava a exceção real e sempre mostrava o mesmo texto
genérico ("Erro ao salvar. Tente novamente."), mesmo quando o Postgrest
devolvia um motivo específico e útil (ex. `N09_PAYLOAD_INVALIDO: ...`,
violação de constraint). Ajustado para mostrar a mensagem real do
`PostgrestException` quando existir, com o texto genérico só como
fallback (erro de rede, timeout, etc. sem mensagem útil).

## O que mudou

`lib/features/nutricao/presentation/pages/anamnese_self_service_page.dart`:

- Novo campo `_autovalidarForm` (bool, começa `false`) + `Form(...,
  autovalidateMode: _autovalidarForm ? AutovalidateMode.onUserInteraction :
  AutovalidateMode.disabled)` — autovalidate começa desligado (não assusta
  o usuário pintando tudo de vermelho antes da 1ª tentativa) e liga
  permanentemente depois da 1ª tentativa de salvar que falhar.
- `_irParaConfirmacao`: quando `validate()` falha, agora **sempre** mostra
  um `SnackBar` (`"Por favor, preencha os campos obrigatórios em
  vermelho."`) além de ligar o autovalidate.
- Montagem do rascunho extraída pra um método próprio (`_montarRascunho`,
  mesmo código literal de antes, só isolado) e chamada dentro de um
  `try/catch` — qualquer exceção mostra um SnackBar
  (`"Não foi possível preparar sua anamnese..."`) em vez de falhar calada.
- Loading do botão "Salvar" (`_indoParaConfirmacao` +
  `CircularProgressIndicator`) **já existia e já estava correto** —
  nenhuma mudança necessária aqui.
- 3 chaves i18n novas (`nutricao.anamnese_validacao_pendente`,
  `nutricao.anamnese_erro_inesperado`) em `assets/i18n/{pt,en,es}.json` —
  paridade confirmada nos 3 idiomas.

`lib/features/nutricao/presentation/pages/confirmar_anamnese_page.dart`:

- `catch (_)` → `catch (e)`, com a mensagem do `PostgrestException`
  (`e.message`) exibida quando disponível, mantendo o texto genérico
  (`nutricao.save_error`) como fallback.

## Fora do escopo, por restrição explícita da tarefa

- Nenhuma regra de negócio ou validação nova foi adicionada (ex. nenhum
  campo passou a ser obrigatório que não era antes) — só feedback visual
  sobre validações que já existiam.
- Nenhuma mudança de schema/RPC no Supabase.
- `ConfirmarAnamnesePage` já cumpria loading + try/catch + SnackBar antes
  desta tarefa — só a QUALIDADE da mensagem de erro foi melhorada.

## Verificação

- **3 testes novos/estendidos**:
  1. `anamnese_self_service_page_test.dart`: teste existente de validação
     ampliado pra confirmar que o SnackBar
     `"Por favor, preencha os campos obrigatórios em vermelho."` aparece.
  2. `anamnese_self_service_page_test.dart`: teste novo confirmando que o
     autovalidate fica desligado antes da 1ª tentativa (digitar e apagar
     não mostra erro) e liga depois de uma tentativa falhar (digitar e
     apagar de novo já mostra erro, sem precisar tocar em "Salvar" outra
     vez).
  3. `confirmar_anamnese_page_test.dart`: teste novo com
     `PostgrestException(message: 'N09_PAYLOAD_INVALIDO: ...')` confirmando
     que a mensagem REAL aparece, não o texto genérico (teste pré-existente
     com `Exception` genérica continua passando, confirma o fallback).
- Não foi possível escrever um teste de UI pro `try/catch` da montagem do
  rascunho (Achado 2) — os validators atuais de altura/peso já garantem
  que `double.parse` nunca recebe texto inválido quando `validate()`
  passa, então não há caminho legítimo de input pra forçar a exceção hoje.
  O `try/catch` fica como proteção defensiva (pedido explícito da tarefa),
  documentado honestamente como não exercitado por teste automatizado.
- `flutter analyze`: 30 issues (linha de base do projeto, zero novo).
- `flutter test`: **514/514** (era 512/512 antes desta tarefa, +2 novos:
  1 na página do formulário, 1 na página de confirmação), zero regressão.

Branch `fix/anamnese-save-feedback`, a partir de `main`.
