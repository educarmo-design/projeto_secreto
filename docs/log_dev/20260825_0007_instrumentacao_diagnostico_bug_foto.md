# RELATÓRIO 20260825_0007 — Etapa 1: instrumentação de diagnóstico (zero mudança de comportamento)

**Data:** 2026-08-25
**Pedido:** tarefa estruturada em 2 etapas (instrumentar → aguardar log real
do dispositivo → só então corrigir). Este relatório cobre **só a Etapa 1**.
Nenhuma lógica foi alterada — só `console.log`/`debugPrint` adicionados em
pontos específicos, e um `initState` novo em `ConfirmacaoPratoPage` (que não
tinha nenhum) só para poder logar ali.

## 1) Edge Function (`extract-metric-photo/index.ts`)

**a) Log de conclusão (duração total + status HTTP + tamanho do corpo).**
`createHandler` retornava diretamente a função `handleRequest` com toda a
lógica dentro dela. Para logar em QUALQUER um dos `return` internos (são
muitos, espalhados por auth/validação/extratores) sem duplicar lógica nem
arriscar mudar comportamento, a função foi **renomeada** para
`processarRequest` (corpo idêntico, nem uma linha mudou) e
`createHandler` passou a devolver um wrapper fino:

```ts
return async function handleRequest(req: Request): Promise<Response> {
  const inicioExecucao = Date.now();
  const resposta = await processarRequest(req);
  const duracaoMs = Date.now() - inicioExecucao;
  let tamanhoCorpo = 'desconhecido';
  try {
    tamanhoCorpo = String((await resposta.clone().text()).length);
  } catch { /* best-effort */ }
  console.log(`[extract-metric-photo] CONCLUSÃO: duracao=${duracaoMs}ms status=${resposta.status} tamanho_corpo=${tamanhoCorpo}bytes`);
  return resposta;
};
```
`resposta.clone()` é necessário porque um `Response` só deixa o corpo ser
lido uma vez — sem clonar, o corpo real devolvido ao cliente ficaria
consumido aqui dentro.

**b) Log entre casamento de medida e cálculo de macros**, dentro de
`processarPratoRefeicao`, logo após `calcularPrato` retornar:
```ts
const calculo = calcularPrato(extracao.itens, catalogo);
console.log(`[processarPratoRefeicao] calcularPrato concluído: ${calculo.itens.length} itens casados, ${calculo.itensNaoReconhecidos.length} não reconhecidos`);
```
Isso marca a fronteira exata: se um log real parar de aparecer DEPOIS desta
linha, o problema está na busca semântica condicional ou na montagem da
resposta (`jsonResponse`) — não no casamento em si (que já é logado item a
item por `encontrarMedida`, como no log que o fundador trouxe antes).

## 2) `camera_capture_controller.dart`

`debugPrint` assim que a resposta HTTP chega, **antes de qualquer
`jsonDecode`/parsing**:
```dart
debugPrint('DEBUG capturarEEnviar: resposta recebida — statusCode=${response.statusCode}, tamanho_corpo=${response.bodyBytes.length} bytes');
```
Colocado logo após o `.timeout(_uploadTimeout)` resolver, antes do
`if (response.statusCode != 200)`.

## 3) `camera_capture_view.dart`

`debugPrint` imediatamente antes do `pushReplacement`, com a quantidade de
itens do prato extraído e o estado de `mounted` naquele instante:
```dart
debugPrint('DEBUG _onStateChanged: prato extraído com ${prato.itens.length} itens — chamando pushReplacement (mounted=$mounted)');
```

## 4) `ConfirmacaoPratoPage` e `ConfirmacaoPratoController`

- `ConfirmacaoPratoPage` **não tinha `initState` nenhum antes** — adicionado
  só para logar (`super.initState()` primeiro, depois o print).
- `debugPrint` também na primeira linha de `build`.
- `ConfirmacaoPratoController` **não é um widget** (é um `ValueNotifier`
  puro) — não existe `initState`/`build` nele. O equivalente mais próximo é
  o construtor, que ganhou um corpo só para logar (antes não tinha corpo
  nenhum, só a lista de inicialização).

### Todo ponto de `Navigator.pop`/`maybePop`/retorno antecipado em `confirmacao_prato_page.dart`

Nenhum `maybePop` existe no arquivo. Lista completa dos demais:

| Linha (aprox.) | Método | Tipo | Condição exata |
|---|---|---|---|
| `_salvarComoFavorita`, início | early return | `if (resultado == null \|\| !mounted) return;` — usuário cancelou o diálogo de nome/tipo OU a tela já foi desmontada |
| `_salvarComoFavorita`, fim | early return | `if (!mounted) return;` — tela desmontada depois do `_favoritasRepository.salvar(...)` assíncrono |
| `_confirmar`, início | early return | `if (!mounted \|\| !sucesso) return;` — tela desmontada OU `_controller.confirmar()` retornou `false` |
| `_confirmar`, fim | **`Navigator.of(context).pop(true)`** | só depois de mostrar o SnackBar de sucesso + esperar 900ms — **é o ÚNICO pop de página inteira no arquivo**, e só acontece depois do usuário apertar "Confirmar" e o backend confirmar sucesso |
| `_mostrarDialogoEditarPeso`, botão Cancelar | `Navigator.of(context).pop` | fecha só o diálogo de editar peso (não a página) |
| `_mostrarDialogoEditarPeso`, botão Salvar | `Navigator.of(context).pop()` | idem, depois de aplicar o novo peso |

**Conclusão direta desta tabela:** `ConfirmacaoPratoPage` nunca fecha
sozinha por conta própria — o único `pop` de página inteira exige o usuário
ter apertado "Confirmar" e o servidor ter confirmado sucesso. Isso **não
bate** com o sintoma relatado (a tela nunca chega a aparecer pro usuário
interagir com ela). Reforça que, se o bug for confirmado pelo log real, ele
está ANTES desta tela existir — mais provavelmente em `CameraCaptureView`
(ver Etapa 2), não dentro dela.

## 5) Testes — `confirmacao_prato_page_test.dart`

A tarefa mencionava 11 testes; a suíte hoje tem **19**. Rodados exatamente
como pedido, sem corrigir nada:

```
00:02 +18: All tests passed!
```

**19/19 passaram, zero falha.** Nada para colar — não há mensagem de falha
nenhuma. Os `debugPrint` novos aparecem corretamente no output de cada
teste (confirmando que a instrumentação em si funciona), por exemplo:
```
DEBUG ConfirmacaoPratoPage.initState: 1 itens recebidos
DEBUG ConfirmacaoPratoPage.build: rodando
DEBUG ConfirmacaoPratoController: construído com 1 itens
```

## Verificação

`deno check` limpo. Deno: 100/100 (inalterado — a instrumentação não toca
nenhuma lógica testada). `flutter analyze` nos 4 arquivos tocados: só os 2
avisos pré-existentes de `prefer_const_constructors` (linha deslocada pelas
minhas adições, mesmo achado de sempre, não relacionado). Edge Function
**deployada** com a instrumentação — necessário para o próximo log real do
dispositivo já vir com as novas linhas.

## Como testar e verificar no aparelho (pré-requisito da Etapa 2)

1. **Recompilar e reinstalar o app** — as mudanças em `camera_capture_controller.dart`,
   `camera_capture_view.dart`, `confirmacao_prato_page.dart` e
   `confirmacao_prato_controller.dart` são do lado do cliente, só entram em
   vigor com rebuild (a Edge Function já está deployada, essa parte não
   precisa de rebuild).
2. Rodar `adb logcat` filtrando pelo app **durante** a tentativa de foto que
   reproduzir o bug — os `DEBUG capturarEEnviar:`/`DEBUG _onStateChanged:`/
   `DEBUG ConfirmacaoPratoPage...`/`DEBUG ConfirmacaoPratoController:`
   devem aparecer no logcat (mesmo em build release, `debugPrint` ainda
   escreve no log do sistema, só não aparece NA TELA).
3. Em paralelo, no painel da Supabase (ou via API), pegar o log da mesma
   execução na Edge Function — agora com a linha `[extract-metric-photo]
   CONCLUSÃO: duracao=...ms status=... tamanho_corpo=...bytes` no final, e
   `[processarPratoRefeicao] calcularPrato concluído: ...` no meio.
4. Trazer os dois logs (dispositivo + Edge Function) da MESMA tentativa
   (mesmo horário) — é isso que a Etapa 2 está esperando antes de qualquer
   correção.

Nenhuma correção foi aplicada nesta tarefa — só instrumentação, como pedido.
Aguardando o log reproduzido para a Etapa 2.
