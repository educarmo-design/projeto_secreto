# RELATÓRIO 20260824_0003 — Registro de Refeição, 4 métodos num único ponto de entrada

**Data:** 2026-08-24
**Modo:** autônomo, com 3 decisões confirmadas com o fundador antes de começar (ver abaixo).

## Pedido original

Fundador confirmou que o bug da cota do Gemini (RELATÓRIO 20260824_0002) estava
resolvido e pediu a especificação completa de uma tela nova: um botão ao lado do
de hidratação na AppBar abre uma tela única com 4 ícones, um por método de
registrar uma refeição:

1. **Descritivo** — usuário digita a refeição em texto livre (ex.: "arroz 2
   colheres, feijão 50 gramas..."), o sistema interpreta e mostra uma tela de
   revisão (editar alimento/quantidade, favoritar) antes de salvar.
2. **Áudio** — mesma ideia, falado. Áudio nunca é armazenado.
3. **Favoritos** — escolher entre refeições favoritas já salvas, também passando
   por revisão antes de salvar.
4. **Foto** — o método já existente (câmera), sem mudança de comportamento.

## Decisões confirmadas antes de implementar

Perguntadas via 3 opções, todas resolvidas com a recomendada:

1. **Interpretação de áudio**: uma chamada só ao Gemini (áudio → lista de itens
   direto), mais barato de cota do que transcrever e depois interpretar em duas
   chamadas.
2. **"Usar favorita"**: sempre abre a tela de revisão antes de salvar — sem
   atalho de 1 toque — consistente com os outros 3 métodos.
3. Começar a implementar imediatamente, em modo autônomo.

## Backend (`extract-metric-photo/index.ts`)

Generalização do pipeline "IA traduz, backend calcula" (já usado pra foto) pra
também aceitar texto e áudio como fonte, **reaproveitando 100% do casamento
determinístico e cálculo de calorias já existentes** — o Gemini nunca calcula
nada, só devolve `{itens: [{nome, medida, quantidade, confianca}]}` a partir do
que quer que tenha sido a entrada.

- `ChamadorGemini` ganhou `base64`/`mimeType` opcionais — chamada de texto não
  manda `inlineData` nenhum, só o prompt.
- Dois tipos novos (`pratoRefeicaoTexto`/`pratoRefeicaoAudio`), cada um com seu
  próprio system prompt, ambos no nível **LITE** (mais barato de cota — não
  precisam de visão, só interpretação de linguagem).
- `montarChamadaGeminiPrato`/`processarPratoRefeicao` (novo, com `fonte: 'foto'
  | 'texto' | 'audio'`) decidem só a MONTAGEM da chamada ao Gemini; tudo
  depois (casamento léxico/semântico, cálculo, resposta) é o mesmo código que
  já existia pra foto — zero duplicação da lógica de negócio.
- Handler: lê o corpo como texto puro (UTF-8) quando `tipo=pratoRefeicaoTexto`,
  ou como áudio (`mimeType` normalizado pra `audio/*`) quando
  `tipo=pratoRefeicaoAudio`.
- 7 testes novos em `index_test.ts` (texto reconhecido, corpo vazio → 400,
  nunca manda `inlineData`, usa o modelo LITE; áudio reconhecido, manda
  `inlineData`; nível LITE confirmado pros dois tipos).

## Flutter — os 4 métodos

- **`RegistroRefeicaoIaService`** (novo) — HTTP pro mesmo endpoint, dois
  métodos (`interpretarTexto`/`interpretarAudio`), 45s de timeout.
- **`RegistroRefeicaoIaController`** (novo) — `ValueNotifier` com os 4 estados
  (idle/processando/sucesso/erro), mesmo espírito de outros controllers do
  projeto.
- **`DescreverRefeicaoPage`** (novo) — campo de texto + botão "Interpretar" →
  `ConfirmacaoPratoPage` (mesma tela de revisão da foto, zero código a mais).
- **`GravarRefeicaoPage`** (novo) — grava com o pacote `record` (só sabe gravar
  pra arquivo, não existe modo "só memória" na API dele), corte automático em
  90s, apaga o arquivo temporário **imediatamente depois de ler os bytes pra
  RAM**, antes mesmo da resposta do servidor chegar — mesma garantia Zero
  Storage do `XFile` da câmera (`CameraCaptureController`). O áudio em si só
  vai pro Gemini (que também não o guarda, F10 Passo 1) e nunca é persistido
  em tabela nenhuma.
- **`EscolherMetodoRefeicaoPage`** (novo) — o widget único pedido: grade 2x2,
  um ícone por método, é a porta de entrada tanto do botão novo na AppBar
  quanto do card novo do dashboard.
- **`FavoritasPage._usarFavorita`** (reescrito) — antes gravava direto com 1
  toque; agora sempre abre `ConfirmacaoPratoPage` pra revisão, decisão #2
  acima.
- Dashboard: 10º widget configurável (`DashboardWidgetId.metodosRegistroRefeicao`
  / `MetodosRegistroRefeicaoCard`) reaproveitando a Fábrica de Widgets já
  existente; botão novo na AppBar (`Icons.restaurant_menu`), ao lado do de
  hidratação.
- Permissões: `RECORD_AUDIO` (Android), `NSMicrophoneUsageDescription` (iOS).
- i18n pt/en/es completo pros 3 namespaces novos.

## Achados de teste (a maior parte do esforço desta tarefa)

Um teste (`gravar_refeicao_page_test.dart`, "gravar, parar e enviar com
sucesso") travou os 10 minutos inteiros de timeout padrão do `flutter_test`,
mesmo depois de 3 causas plausíveis já corrigidas (`pumpAndSettle()` direto
com spinner indeterminado na tela, `path_provider` sem plugin registrado em
teste, `Supabase.instance` não inicializado). Instrumentado com `debugPrint`
numerado em cada `await` de `_pararEEnviar` pra achar o ponto exato — achado
real, uma camada mais funda do que as 3 anteriores:

- **`testWidgets` roda o corpo inteiro dentro de uma zona `FakeAsync`** (é
  assim que `pump()`/`pumpAndSettle()` controlam o tempo sem esperar de
  verdade). Operações de I/O REAIS do `dart:io` (aqui, `File.writeAsBytes` no
  setup do teste e `File.readAsBytes`/`File.delete` dentro do próprio
  `_pararEEnviar`) dependem do loop de eventos de verdade
  (`dart:isolate _RawReceivePort._handleMessage`, confirmado no stack trace do
  hang) e por isso **nunca completam** dentro da zona fake — travam pra
  sempre, não importa quantos `pump()` sejam chamados depois. Correção:
  `tester.runAsync()`, que roda o callback numa zona real.
- Mesmo dentro de `runAsync()`, ainda não dá pra chamar `pumpAndSettle()`
  direto: enquanto a cadeia real (I/O → controller mockado → `Navigator.push`)
  não termina, a tela mostra `CircularProgressIndicator` indeterminado, que
  nunca "assenta" sozinho.
- E o detalhe mais sutil: **`tester.pump(duration)` só avança um relógio
  FAKE — não bloqueia tempo de verdade nenhum**, então uma sequência de
  `pump(100ms)` repetida não dá nenhuma chance real pro I/O (que está rodando
  fora do controle desse relógio) progredir. A correção final foi um loop
  sondando `find.text('Confirmar Refeição')` com `Future.delayed` **de
  verdade** entre cada `pump()`, só chamando `pumpAndSettle()` depois que a
  navegação já tinha acontecido (2 tentativas de 100ms bastaram na prática).

Achado menor, mesmo arquivo de testes de escolha de método
(`escolher_metodo_refeicao_page_test.dart`): a grade 2x2 (tiles quadrados, sem
`childAspectRatio`) não cabe inteira na altura padrão de teste (800x600) — o
tile "Fotografar" (2ª linha) ficava fora da viewport e o tap caía fora da área
visível. Corrigido com `tester.ensureVisible()` antes do tap.

## Verificação

`flutter analyze` limpo. Suíte completa:

- **Flutter: 427/427**, zero falhas, zero regressão.
- **Deno (`extract-metric-photo`): 91/95** — as mesmas 4 falhas pré-existentes
  já registradas em relatórios anteriores desta semana (não relacionadas a
  este trabalho: `encontrarMedida`/`calcularPrato`/`resolverComBuscaSemantica`/
  handler, todas em torno de medida-não-cadastrada).

Nada verificado em device físico ainda — recomendado testar os 4 métodos de
ponta a ponta (especialmente o de áudio, que depende de permissão de
microfone real) no próximo teste real do fundador.
