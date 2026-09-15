# RELATÓRIO 20260915_0001 — UI de Câmera Unificada (Seletor de Modo Prato/Rótulo)

**Data**: 2026-09-15
**Branch**: `feat/ui-camera-unificada` (a partir de `main`)
**Referências**: Documento Mestre v8.0, Regra 4 (UX prevalece) e Regra 21 (Performance).

## Contexto

O fundador aprovou uma interface de câmera única com seletor de modo (estilo câmera nativa: "Prato" | "Rótulo") para substituir o fluxo atual, onde fotografar um prato e fotografar um rótulo nutricional exigiam dois pontos de entrada separados no dashboard, cada um abrindo a câmera já travada num modo fixo, sem forma de trocar depois de aberta.

## Como a UI foi montada

### Achado inicial: o roteamento de IA já existia

Antes de qualquer código, investiguei o backend (`extract-metric-photo/index.ts`) e o cliente (`CameraCaptureController`). O contrato pedido pela tarefa ("o Flutter deve enviar um parâmetro indicando se a imagem é um prato ou um rótulo... modelo Flash pra pratos, Core/Pro pra rótulos") **já estava implementado e funcionando** desde tarefas anteriores desta sessão:
- O cliente já envia `X-Tipo-Aparelho: <TipoAparelho.name>` em toda chamada (`capturarEEnviar`).
- O servidor já lê esse header e decide o nível de modelo via `NIVEL_POR_TIPO` (`TIPO_ROTULO` → `'core'`; `pratoRefeicao` → `'lite'`, desde o RELATÓRIO 20260825_0005).

Não havia nada a corrigir nessa ponta — o trabalho real desta tarefa é 100% de UI: dar ao usuário controle sobre QUAL `TipoAparelho` vai nesse header, ao invés de fixá-lo antes de abrir a câmera.

### Arquitetura escolhida: um só widget, modo mutável em vez de fixo

`CameraCaptureView` já era o único componente compartilhado por 5 `TipoAparelho` (glicosímetro/pressão/balança/prato/rótulo) — "única tela de câmera" já era verdade estruturalmente. O que faltava: `widget.tipoAparelho` era tratado como o modo de captura em si, imutável durante a vida da tela.

Mudança: `widget.tipoAparelho` virou só o **modo inicial**; um novo campo de estado `_tipoAtual` (mutável, `late TipoAparelho _tipoAtual = widget.tipoAparelho`) é o modo **em uso de verdade** — é ele que vai no header HTTP e decide como a resposta é interpretada, não mais `widget.tipoAparelho`. Todos os pontos que antes liam `widget.tipoAparelho` para decidir comportamento (inicialização da câmera, disparo, retry de erro, retry do resultado cru de rótulo, título da AppBar) passaram a ler `_tipoAtual`.

O seletor só aparece quando o modo INICIAL é Prato ou Rótulo (`_modoDuplo`) — os 3 fluxos de aparelho clínico (glicosímetro/pressão/balança) nunca mostram o seletor, tela idêntica a antes, zero risco de regressão nesses 3 fluxos.

### Seletor de modo: pill de 2 segmentos, estilo câmera nativa

Widget novo (`_buildSeletorModo`/`_buildSegmentoModo`), posicionado num `Column` junto com o botão de disparo (dentro do mesmo `Align(bottomCenter)` já existente) — "logo acima do botão", como pedido. Visual: pill arredondada (`Colors.black54`) com 2 segmentos ("Prato"/"Rótulo", ícone + texto), o segmento ativo destacado em `AppColors.primaryGold` (a cor de destaque já usada em outros pontos do app, ex. `escolher_metodo_refeicao_page.dart`) com `AnimatedContainer` de 200ms para a troca de fundo não "piscar" (Regra 4). Optei por um widget Material customizado em vez de `CupertinoSlidingSegmentedControl` — o app inteiro é Material, sem nenhum uso de Cupertino em lugar nenhum do código; importar um widget iOS-nativo destoaria do resto do produto. "Inspiração no app nativo" foi seguida no COMPORTAMENTO (pill com 2 opções, troca instantânea) e não na biblioteca de widgets.

Tocar num segmento chama `_mudarModo(TipoAparelho)` — **puramente `setState`**, nenhuma chamada ao controller, nenhuma reinicialização de câmera. Desabilitado (opacidade 50%, mesmo tratamento visual do botão de disparo) enquanto `state.isBusy` — nunca é possível trocar de modo no meio de uma captura/upload.

### A decisão de resolução (achado/trade-off, registrado para avaliação do fundador)

Antes desta tarefa, a resolução da câmera variava por tipo: `TipoAparelho.pratoRefeicao` usava `ResolutionPreset.low` (Adendo v5.1 A.4 — "comida é barata", ~512px, token mais barato); os outros 4 tipos (incluindo rótulo) já usavam `ResolutionPreset.medium` (OCR não pode perder nitidez).

Com o seletor dentro da MESMA tela, a resolução precisa ser decidida na inicialização da câmera — antes de saber com qual modo o usuário vai efetivamente disparar — e o pacote `camera` não permite trocar o preset de um `CameraController` já inicializado sem descartá-lo e recriar (o que quebraria a exigência explícita da tarefa: troca "instantânea, mudando apenas a variável de estado"). Reinicializar a cada troca de modo causaria um flash/delay perceptível, incompatível com "instantâneo" e com "design clean".

**Decisão**: `CameraCaptureController.initializeCamera` agora sempre usa `ResolutionPreset.medium`, para qualquer `TipoAparelho`. Prioriza nunca perder nitidez do rótulo (onde perder qualidade quebra a função — falha real, não só custo) sobre manter a otimização de custo/token que só existia para prato. Os 3 fluxos de aparelho clínico não são afetados (já eram `medium`, continuam `medium`).

**Custo real, medido — não presumido**: lido o código-fonte do plugin instalado (`camera_android_camerax` 0.7.4+4) para confirmar as dimensões reais de cada preset (`low` → bound 320×240; `medium` → bound 720×480, os valores-alvo que o CameraX usa para escolher a resolução mais próxima disponível no device), gerei imagens JPEG nessas dimensões exatas e medi via `countTokens` da API do Gemini (`gemini-flash-lite-latest`, o mesmo modelo LITE usado em produção para prato):

| Preset | Dimensão | Tokens de imagem |
|---|---|---|
| `low` (usado antes só p/ prato) | 320×240 | 1.064 |
| `medium` (usado agora, prato e rótulo) | 720×480 | 1.080 |

**Delta real: +16 tokens (~1,5%)** — confirmado que a contagem depende só da dimensão em pixels, não do peso/conteúdo do arquivo (uma segunda imagem 320×240 com conteúdo totalmente diferente, 46KB vs 7,9KB, deu o mesmo resultado, 1.064). Na prática, esse aumento é irrelevante para custo/cota do Gemini. O que de fato cresce um pouco é o tamanho do JPEG capturado (720×480 tem ~2,25× mais pixels que 320×240 — upload HTTP do device um pouco maior), mas continua um arquivo pequeno em termos absolutos, sem impacto de banda perceptível. Troca deliberada e documentada no código-fonte (`initializeCamera`) e aqui — o trade-off real é muito menor do que a primeira versão deste relatório presumia sem medir.

### i18n

3 chaves novas (`dashboard.camera_modo_prato`/`dashboard.camera_modo_rotulo`) nos 3 idiomas — rótulos curtos para o segmento ("Prato"/"Rótulo" em pt, "Meal"/"Label" em en, "Plato"/"Etiqueta" em es), distintos das chaves já existentes e mais longas usadas no título da AppBar (`camera_option_prato_refeicao`/`camera_option_rotulo`, que continuam intactas e agora reagem a `_tipoAtual`).

### O que NÃO foi feito (dentro do próprio escopo permitido pela tarefa)

- **Overlay de grade para rótulos**: a tarefa deixava explicitamente opcional ("se aplicável e fácil de fazer, senão apenas o seletor"). Não implementado — mantém a mudança mínima e de baixo risco; puramente o seletor, como o "senão" da tarefa permite.
- **Consolidação dos 2 cards do dashboard** ("Fotografar Comida"/"Fotografar Etiqueta Nutricional" continuam existindo separadamente na grade configurável): fora do escopo desta tarefa (que é sobre a tela de câmera em si, não sobre a composição do dashboard). Os dois cards continuam abrindo a MESMA tela unificada — só mudam o modo INICIAL (`widget.tipoAparelho`); o usuário é livre pra trocar assim que a câmera abrir, de qualquer um dos dois cards. Se o fundador quiser reduzir os 2 cards a 1 só, é uma decisão de IA de produto separada, não implementada aqui sem autorização explícita.
- **`EscolherMetodoRefeicaoPage` (Método 4, "Fotografar")**: continua abrindo só com `TipoAparelho.pratoRefeicao` como modo inicial — mas agora, como qualquer outra entrada, o usuário pode trocar pra "Rótulo" assim que a câmera abrir (o Método 4 nunca teve uma opção "Rótulo" dedicada; agora ganha uma de graça, via o seletor).

## Feedback de 15s (RESTRIÇÃO da tarefa)

O timer de aviso de demora (RELATÓRIO 20260902_0001) e o `AnimatedSwitcher` do texto do overlay nunca dependeram de `TipoAparelho` — operam só sobre `CameraCaptureStatus` (`uploading`). Nenhuma mudança necessária; funciona identicamente para os dois modos, herdado sem nenhum ajuste.

## Verificação

`flutter analyze` nos 2 arquivos tocados (`camera_capture_view.dart`, `camera_capture_controller.dart`): **limpo**. `flutter analyze lib/features/dashboard` completo: 11 avisos, todos pré-existentes em arquivos não tocados (`dynamic_widget_factory.dart`, `background_sync_manager.dart`). `flutter test test/features/dashboard`: **196/196**, zero regressão.

**Gap de teste registrado, não escondido**: `CameraCaptureView`/`CameraCaptureController` continuam sem nenhum teste widget automatizado — gap pré-existente desde antes desta tarefa (mockar `CameraController` do pacote `camera` não é trivial, achado já registrado no RELATÓRIO 20260827_0001 e reafirmado no RELATÓRIO 20260902_0001 para este mesmo arquivo). O seletor de modo novo (`_mudarModo`/`_modoDuplo`/`_buildSeletorModo`) segue o mesmo gap — verificado só por `flutter analyze` + revisão de código, não por teste automatizado.

## Análise e sugestão de merge

Mudança de baixo risco estrutural: nenhum call site de `CameraCaptureView(tipoAparelho: ...)` precisou mudar (a API pública do widget é idêntica); os 3 fluxos de aparelho clínico são estruturalmente inalcançáveis pelo código novo (`_modoDuplo` sempre falso pra eles). O efeito colateral do aumento de resolução do prato (`low` → `medium`), medido acima em +16 tokens de imagem (~1,5%), é desprezível — não é mais um trade-off de custo relevante o bastante pra travar o merge. Recomendo mesclar assim que autorizado — **não mesclado ainda** (Regra 18).
