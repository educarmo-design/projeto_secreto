# RELATÓRIO 20260827_0001 — Etapa 2: correção da navegação silenciosa no registro de refeição por foto

**Data:** 2026-08-27
**Continuação de:** RELATÓRIO 20260825_0007 (Etapa 1 — instrumentação, zero
mudança de comportamento). Esta tarefa só começou depois do fundador trazer
o log real reproduzido, pareando device (`adb logcat`) + Edge Function
(mesma execução) — exatamente a condição que a Etapa 2 exigia antes de
qualquer correção.

## O log que autorizou esta correção

**Lado do dispositivo** (única coisa que apareceu, e nada depois):
```
DEBUG capturarEEnviar: resposta recebida — statusCode=200, tamanho_corpo=2885 bytes
DEBUG _onStateChanged: prato extraído com 8 itens — chamando pushReplacement (mounted=true)
```

**Lado da Edge Function**, mesma execução: `booted` → 8 itens casados por
`encontrarMedida` → `calcularPrato concluído: 8 itens casados, 0 não
reconhecidos` → `CONCLUSÃO: duracao=8722ms status=200 tamanho_corpo=2869bytes`.
Servidor de novo saudável e rápido (8,7s) — mesma coisa que já tinha
acontecido numa execução anterior (3,3s, RELATÓRIO 20260825_0007) e nas
diagnósticos anteriores.

**A conclusão direta**: `mounted` era `true` no instante exato da chamada
(prova concreta, não suposição) — a hipótese de "Android desmontou a árvore
durante a espera" (RELATÓRIO 20260825_0006) está **descartada por
evidência**, não confirmada. `pushReplacement` foi chamado, mas nenhum dos
logs de `ConfirmacaoPratoPage`/`ConfirmacaoPratoController` (instrumentados
na Etapa 1) apareceu depois — a tela de destino nunca chegou a rodar
`initState`. Nenhuma exceção em lugar nenhum.

**Isto significa que a causa raiz exata continua sem 100% de certeza** — o
que se sabe agora é a janela EXATA onde ela mora (entre a chamada de
`pushReplacement` e `initState` da tela nova), não o mecanismo interno
completo. As 3 correções abaixo (já pré-combinadas na Etapa 1) atacam essa
janela por ângulos diferentes — a mais provável de fazer diferença de
verdade é a #2 (trocar `pushReplacement` por `push`), porque muda o
comportamento do Navigator de um jeito que, se o problema for uma
condição de corrida entre navegação/lifecycle, passa a deixar rastro
visível em vez de sumir.

## As 3 correções (pré-combinadas na Etapa 1, aplicadas agora)

**1. Checagem de `mounted` em `_onStateChanged`** — higiene, seguindo o
mesmo padrão já usado em `gravar_refeicao_page.dart`/`descrever_refeicao_page.dart`.
Não é a correção presumida da causa raiz (o log provou que `mounted` já
era `true` no caso reproduzido) — mas fecha uma lacuna real: o listener
pode disparar de novo entre notificações com o widget já desmontado (ex.:
usuário voltou enquanto o resultado de rótulo/glicosímetro ainda estava
chegando), e antes não tinha proteção nenhuma pra isso.

**2. `pushReplacement` → `push` no fluxo de foto.** Antes, a tela da
câmera era substituída imediatamente — se a rota nova falhasse em
construir por qualquer motivo, a câmera já tinha sumido, sem deixar
rastro. Agora a tela da câmera **fica na pilha**; `ConfirmacaoPratoPage` é
empilhada por cima. Confirmar lá faz `pop` das duas telas (mesmo padrão
de `GravarRefeicaoPage`); voltar sem confirmar reinicializa a câmera pra
tentar de novo (sem isso, o usuário ficaria olhando pro spinner do
estado `success` sem itens pra sempre — bug novo que eu mesmo teria
introduzido se não tratasse esse caso).

**3. `Future` de `_capturar()` tratado, não descartado.** O botão
chamava `_capturar` direto em `onPressed` (`VoidCallback?`) — Dart aceita
uma função que devolve `Future<void>` nesse lugar sem avisar, e o
`Future` retornado nunca era usado. `capturarEEnviar` já captura
essencialmente tudo internamente (não relança nada visto até agora), mas
isso era um buraco real: qualquer exceção que escapasse dali
desapareceria sem passar por nenhum `catch`. `_iniciarCaptura()` novo
(síncrono, wrapper de `_capturar()`) usa `.catchError` de verdade — não
só `unawaited()` (que só silencia o lint, não trata nada).

## Verificação

`flutter analyze` em `camera_capture_view.dart`: **limpo, zero avisos**.
Suíte completa: **427/427 passou** (nenhuma quebra em nenhum outro
arquivo). Nenhuma mudança no backend nesta tarefa — a instrumentação da
Edge Function da Etapa 1 continua deployada e ativa (útil pra confirmar
o fix no próximo teste real).

**Gap conhecido, não fechado nesta tarefa**: não existe teste automatizado
nenhum pra `CameraCaptureView`/`CameraCaptureController` (confirmado —
nenhum arquivo em `test/` referencia `CameraCaptureView`). É um gap
pré-existente, não introduzido aqui; testar essa classe exige mockar o
`CameraController` do pacote `camera`, não trivial, provavelmente tarefa
própria. A verificação desta correção específica ficou por `flutter
analyze` + a suíte completa (nada quebrou nos consumidores) + teste real
no aparelho (abaixo).

**Os `debugPrint` de diagnóstico da Etapa 1 foram mantidos de propósito**
— ainda são úteis pra confirmar que o fix funcionou (ver "Como testar"
abaixo). Remover depois de confirmado, numa limpeza futura.

## Como testar e verificar no aparelho

1. **Recompilar e reinstalar** — mudança é 100% client-side.
2. Repetir exatamente o teste que reproduziu o bug (foto de um prato).
3. **Se funcionou**: depois de "chamando push", devem aparecer
   `DEBUG _onStateChanged: builder de ConfirmacaoPratoPage executando`,
   `DEBUG ConfirmacaoPratoController: construído com N itens`,
   `DEBUG ConfirmacaoPratoPage.initState: N itens recebidos` e
   `DEBUG ConfirmacaoPratoPage.build: rodando`, nessa ordem, e a tela de
   confirmação deve aparecer de verdade na tela.
4. **Se AINDA falhar**: capture o `adb logcat` de novo, do mesmo jeito de
   antes — agora com um detalhe novo pra observar: se aparecer
   `DEBUG _onStateChanged: builder de ConfirmacaoPratoPage executando`
   mas os logs de `initState`/`build` não aparecerem depois, o problema
   está DENTRO da construção de `ConfirmacaoPratoPage` (mais fundo do que
   se pensava). Se nem esse log do builder aparecer, o problema está no
   próprio `Navigator`/`push` (ainda mais fundo, possivelmente fora do
   nosso controle direto). Qualquer um dos dois cenários é uma pista nova
   real, não obtida antes.
