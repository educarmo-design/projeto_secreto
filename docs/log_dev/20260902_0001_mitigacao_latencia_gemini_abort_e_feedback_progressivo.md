# RELATÓRIO 20260902_0001 — Mitigação de Latência do Gemini: Timeout por Tentativa (AbortController) + Feedback Progressivo (Flutter)

**Data**: 2026-09-02
**Branch**: `fix/gemini-timeout-progress` (parte de `fix/performance-ux-registro`, que parte de `fix/hotfix-ui-matematica-n27` — nenhuma das três mesclada ainda; cadeia completa abaixo)
**Referências**: Documento Mestre v8.0, Regra 4 (UX prevalece) e Regra 21 (Performance). Continuação direta do RELATÓRIO 20260901_0003 (que mediu o Gemini variando de ~2s a 43s+ na mesma chamada, mesmo dia, mesmo modelo LITE, e corrigiu a mensagem "Servidor Ocupado" fantasma).

## Contexto

O RELATÓRIO 20260901_0003 diagnosticou o gargalo (Gemini lento, não a implementação) e ajustou o timeout do CLIENTE (60s→90s) pra dar folga a uma chamada lenta que ainda ia suceder. Ficou uma pergunta em aberto, discutida informalmente com o fundador: dava pra cortar requisições travadas no SERVIDOR (Edge Function) antes delas consumirem o orçamento inteiro de retry, e melhorar a percepção de espera de quem está olhando o spinner? O fundador autorizou implementar as duas mitigações, e ampliou o escopo em seguida: o `AbortController` do servidor devia cobrir também a geração de embeddings (não só a chamada de visão), e o feedback de 15s no Flutter devia cobrir os 4 fluxos de registro (foto, rótulo, texto, áudio), não só a foto do prato.

## O que foi construído

### 1. Timeout por tentativa no servidor (`AbortController`, 3 pontos de chamada)

Nenhuma chamada `fetch()` ao Gemini tinha timeout próprio — uma tentativa podia ficar pendurada indefinidamente (o RELATÓRIO 20260901_0003 mediu uma chamada de 42998ms que ainda assim foi sucesso; nada impedia uma pior, real ou por instabilidade do lado do Gemini, de nunca resolver). Sem timeout próprio, uma única tentativa morta consumia sozinha o timeout inteiro do cliente, sem sobrar chance pro retry/fallback já existentes agirem.

Adicionado `AbortController` com timeout configurável em **3 pontos**, todos seguindo o mesmo padrão: criar o controller, `setTimeout(() => abortController.abort(), ms)`, passar `signal` pro `fetch`, capturar `DOMException`/`AbortError` e converter em `ErroHttp(504, ...)` — tratado pelo retry/backoff já existente exatamente como um 5xx —, e `clearTimeout` sempre num `finally` (Regra 21, sem vazar timer):

- **`extract-metric-photo/criarChamadorGeminiReal`** (chamada de visão, foto/rótulo/OCR): **22,5s** por tentativa (meio-termo da faixa 20-25s pedida). Cada uma das até 3 tentativas do retry existente agora aborta e passa pra próxima independentemente, em vez de arriscar travar no meio de uma só.
- **`extract-metric-photo/criarChamadorEmbeddingReal`** (fallback semântico quando o casamento por nome falha): **15s**.
- **`search-food/criarChamadorEmbeddingReal`** (busca manual de alimentos, `ManualFoodSearchPage`/`CriarFavoritaPage`): **15s**, mesmo padrão.

Os dois `criarChamadorEmbeddingReal` ganharam um segundo parâmetro opcional (`timeoutMs`, com o valor de produção como default) — testável sem esperar 15s de verdade.

Um 504 gerado por timeout já cai automaticamente na mensagem amigável correta ("O Gemini demorou demais para responder. Tente novamente.") — a mesma trilha de mapeamento de erro do RELATÓRIO 20260901_0003, que reservou "servidor ocupado" pra 503/504 genuínos. Antes deste relatório essa trilha nunca era alcançada de verdade (a função nunca emitia 503/504); agora um timeout de verdade produz exatamente esse status, honestamente.

### 2. Feedback progressivo no Flutter (15s, 4 fluxos)

Depois de 15s no estado de espera, o texto do spinner troca pra um aviso de demora, com um crossfade de 300ms (`AnimatedSwitcher`) — nunca troca de uma vez, nunca reinicia o spinner em si (que fica sempre como widget `const` separado, isolado da troca de texto). O timer arma só na TRANSIÇÃO pro estado de espera (nunca reinicia enquanto já está esperando) e desarma assim que sai dele (sucesso, erro, ou nova tentativa do zero) — sempre cancelado em `dispose()`.

Implementado nos 3 pontos que cobrem os 4 fluxos pedidos:

- **`CameraCaptureView`** (foto + rótulo — é o MESMO componente compartilhado por `TipoAparelho.pratoRefeicao`/`rotulo`/glicosímetro/balança/pressão; corrigir aqui já cobre foto E rótulo sem código duplicado): timer ligado ao `_controller.addListener` já existente (`_onStateChanged`), armado quando `status == uploading`.
- **`DescreverRefeicaoPage`** (texto): novo listener dedicado no `RegistroRefeicaoIaController` (`initState`), armado quando `isProcessando == true`.
- **`GravarRefeicaoPage`** (áudio): esta tela usa um enum de estado local (`_EstadoGravacao`), não escuta o controller diretamente pra renderizar — o timer arma/desarma direto nos pontos de transição pro/do estado `enviando` dentro de `_pararEEnviar` (arma ao entrar, desarma nos 2 pontos de saída: erro e sucesso).

Chave i18n nova em pt/en/es, mesma frase-base do "quick win" discutido informalmente:
- `descrever_refeicao.interpretando_demora` / `gravar_refeicao.interpretando_demora`: "Ainda analisando, pode levar um pouco mais..." (pt) / "Still analyzing, this may take a bit longer..." (en) / "Todavía analizando, puede tardar un poco más..." (es).
- `dashboard.camera_uploading_demora`: mesma frase, já existia a chave irmã `camera_uploading` usada por `CameraCaptureView`.

## Testes

**Deno** (comportamento de timeout, tempo simulado via `timeoutMs` injetável — nenhum teste espera 15-22,5s de verdade):
- Novo `stubFetchQueSoResolveComAbort()` em `extract-metric-photo/index_test.ts`: só rejeita quando o `AbortSignal` recebido pela produção dispara `abort` de verdade (não um gatilho manual solto) — fiel ao comportamento real do `fetch`.
- 3 testes novos: timeout na 1ª tentativa retenta e sucede na 2ª; timeout em TODAS as tentativas vira `ErroHttp 504` (não 502); `criarChamadorEmbeddingReal` com timeout vira 504 em vez de travar esperando.
- 1 teste novo equivalente em `search-food/index_test.ts` pro embedding.
- `extract-metric-photo`: **119/119** (+3). `search-food`: **16/16** (+1). `deno check` limpo nas duas.

**Flutter**:
- 1 teste novo em `descrever_refeicao_page_test.dart`: usa `Completer` (não `thenAnswer` direto) pra controlar quando a resposta chega, avança o relógio FAKE do teste (`tester.pump`) até passar dos 15s, confirma a troca de mensagem, resolve, confirma que navega normalmente — determinístico e rápido (sem esperar 15s de verdade).
- `camera_capture_view.dart` e `gravar_refeicao_page.dart`: **sem teste automatizado novo pro timer de 15s** — gap registrado, não escondido. Motivo: `CameraCaptureView` já não tinha NENHUM teste antes desta tarefa (gap pré-existente, mockar `CameraController` do pacote `camera` não é trivial — mesmo achado do RELATÓRIO 20260827_0001); e o fluxo de áudio (`gravar_refeicao_page_test.dart`) faz I/O real (`File.readAsBytes`/`delete`) dentro de `tester.runAsync()`, que roda numa zona REAL (não a `FakeAsync` do teste) — um `Timer` criado ali dentro precisaria de 15s de espera DE VERDADE pra disparar, o que tornaria a suíte lenta/fräil só pra este teste. Verificado por leitura de código + `flutter analyze` limpo nos dois arquivos.
- `flutter analyze` (arquivo por arquivo tocado + suite completa): **limpo** nos 3 arquivos alterados; os 30 avisos/infos da suíte completa são todos pré-existentes, em arquivos não tocados por esta tarefa.
- `flutter test test/features/nutrition test/features/dashboard`: **357/357**, zero regressão.

## Cadeia de branches

`main` → `fix/hotfix-ui-matematica-n27` (RELATÓRIO 20260901_0002) → `fix/performance-ux-registro` (RELATÓRIO 20260901_0003) → **`fix/gemini-timeout-progress`** (esta tarefa). As 3 branches seguem sem merge — cada uma depende da anterior; mesclar esta sem as outras duas quebraria a base.

## Análise e sugestão de merge

O AbortController do servidor é aditivo e defensivo: nunca piora um caso que já funcionava (o timeout de 22,5s/15s dá folga confortável acima do que já foi medido como sucesso — 42998ms foi o pior caso observado até agora só pra visão, e continua coberto pelas 3 tentativas de retry, cada uma com seu próprio orçamento de 22,5s). O feedback progressivo é puramente cosmético (não muda nenhum fluxo de dados). Nenhuma migration, nenhuma mudança de contrato HTTP. Recomendo mesclar as 3 branches em sequência (`fix/hotfix-ui-matematica-n27` → `fix/performance-ux-registro` → `fix/gemini-timeout-progress`) assim que o fundador autorizar — não mesclado ainda (Regra 18). Depois do merge, lembrar de rodar `supabase functions deploy extract-metric-photo` e `supabase functions deploy search-food` (sem CI/CD no repo — achado registrado desde 20260901_0002 — merge em `main` não deploya nada sozinho).
