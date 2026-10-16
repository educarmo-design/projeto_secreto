# RCA + Fix — 2 bugs críticos no registro alimentar (líquidos em gramas + câmera de rótulo)

**Tipo:** RCA + correção. Fundador reportou 2 bugs em fase de testes reais.

## Bug 1 — "copo de suco de manga/abacaxi" não registra em ml

### Sintomas reportados
- "Copo de suco de manga" vai para a tela de resolução manual e não
  oferece a opção "ml".
- "Copo de suco de abacaxi" passa direto (sem perguntar nada) e registra
  a dosagem em **gramas**.

### Causa raiz (confirmada consultando o catálogo real de produção)

```
nome_taco                        | aliases                                  | categoria_consumo | unidade
Manga, polpa, congelada          | ..., "suco de manga congelado", ...      | peso_livre         | g
Abacaxi, cru                     | abacaxi, abacaxi fresco, ...             | peso_livre         | g
Abacaxi, polpa, congelada        | ..., sem nenhum alias de "suco"          | peso_livre         | g
```

**Não existe nenhuma entrada de suco dedicada para manga ou abacaxi** em
`alimentos_referencia` (confirmado por `SELECT` read-only no banco de
produção). O casamento (léxico ou semântico) cai na fruta crua/polpa
congelada mais parecida:

- **"suco de manga"** casa (via substring) com "Manga, polpa, congelada"
  — essa linha **já tem o alias "suco de manga congelado"**, mas está
  classificada `categoria_consumo: peso_livre` mesmo assim. Como
  `_unidadeParaItemNaoReconhecido` (Flutter) só promove a "ml" quando
  `categoriaConsumo` já é `liquido_frio`/`liquido_quente`, o item cai no
  input genérico em gramas.
- **"suco de abacaxi"** não casa léxico com nada (achado real e
  **intencional** de uma investigação anterior, RELATÓRIO
  `20260908_0001` — "suco de abacaxi" → `null` por design, pra não deixar
  um alias genérico demais "sequestrar" a busca). Cai na busca
  **semântica**, que acha "Abacaxi, cru" por similaridade — e o backend
  **calculava direto** (sem perguntar nada) usando as macros da fruta
  **sólida** para uma dose de **líquido**, com a dosagem rotulada em
  gramas.

Isto NÃO é um bug novo — é a continuação de uma saga já bem documentada
(RELATÓRIOS `20260902_0002`, `20260908_0001`): uma investigação anterior
já tinha **encontrado e sinalizado exatamente este caso** ("achado extra,
NÃO corrigido aqui... manga/abacaxi... cálculo nutricional errado sem
aviso nenhum, pior que medida não encontrada") como fora do escopo pedido
à época, documentado para decisão futura do fundador. Esta tarefa é essa
decisão.

**Achado de arquitetura importante**: um commit anterior (`d6608e3`)
removeu DE PROPÓSITO um detector de líquido hardcoded
(`ehAlimentoLiquido()`/`ALIMENTOS_LIQUIDOS`) em favor de 100% DB-driven
(`categoria_consumo`). Essa decisão foi correta (fonte da verdade única,
menos hardcode) — mas deixou o sistema **sem rede de segurança** quando o
catálogo tem uma linha mal classificada ou uma fruta sem entrada de suco
dedicada, que é exatamente o que os dois sintomas reproduzem.

### Correção

`supabase/functions/extract-metric-photo/index.ts` — **2 mecanismos
novos, nunca sobrescrevendo o catálogo, só agindo quando ele já falhou**:

1. **`categoriaIncompativel(alimento, nomeDescrito)`** — Regra 23 (N27,
   "falhar visível, nunca arbitrar"): quando o texto descrito pelo
   usuário/IA contém um termo de líquido (`suco`, `leite`, `água`,
   `refrigerante`, `café`, `chá`, `smoothie`, `achocolatado`, `cerveja`,
   `vinho`, ...) mas o alimento CASADO não é classificado como líquido
   pelo catálogo, o item **nunca é calculado** com as macros do sólido —
   vira `itensNaoReconhecidos` com `motivo: 'categoria_incompativel'`
   **antes** de sequer tentar achar uma medida cadastrada (mesmo que
   "copo" estivesse cadastrado para a fruta sólida). Aplicado nos 2
   caminhos de casamento (léxico em `calcularPrato`, semântico em
   `resolverComBuscaSemantica`).
2. **`categoriaEfetiva(alimento, nomeDescrito)`** — promove a
   `liquido_frio`/`ml` quando o texto descrito OU os **aliases do próprio
   alimento casado** mencionam um termo de líquido (cobre o caso "Manga,
   polpa, congelada" ter "suco de manga congelado" como alias próprio).
   Usado nos itens que já iam para `itensNaoReconhecidos` por outro
   motivo (`medida_nao_encontrada`/`quantidade_nao_informada`) — nunca
   rebaixa um alimento já classificado como líquido pelo catálogo.
3. Para itens `categoria_incompativel`, **nenhuma `medidasDisponiveis`/
   `medidaPadraoNome`/`medidaPadraoQtd` é enviada** — essas medidas são
   calibradas pro alimento SÓLIDO casado (ex.: "copo" de pedaços de
   abacaxi, 165g); oferecê-las deixaria o usuário escolher um botão
   pronto e reproduzir o mesmo cálculo errado que esta correção existe
   pra evitar. Só a entrada manual em ml fica disponível.

**Decisão explícita, documentada em código**: termos de recipiente
("copo", "taça", "xícara") **não** entram na lista de termos de líquido —
sozinhos eles não distinguem "copo de suco" de "xícara de arroz"/"copo de
farinha" (medidas sólidas reais). Só o nome/descrição do **alimento**
decide — respeita a restrição explícita de não quebrar medidas sólidas.

**Fora do escopo desta correção, recomendado como follow-up**: a causa
raiz mais profunda é uma lacuna de CATÁLOGO (sem entradas de suco
dedicadas para manga/abacaxi, com macros por 100ml reais de suco — a
correção acima usa as macros da fruta sólida como aproximação, a melhor
disponível sem uma entrada de catálogo nova). Curar o catálogo
(`alimentos_referencia`) com entradas de suco dedicadas resolveria com
precisão nutricional real, em vez de uma aproximação; esta correção
resolve o sintoma visível (unidade errada, cálculo silencioso) sem
depender disso.

## Bug 2 — foto do rótulo "sai branca", OCR não extrai nada

### Investigação — a hipótese original (File/Path) não se aplica a este código

Antes de corrigir, confirmei que a premissa do prompt (perda de
`File`/`image_picker`) **não existe neste fluxo**:
- `image_picker` não é nem dependência do projeto (`pubspec.yaml`).
- **Zero** uso de `Image.file`/`Image.memory` em todo o `lib/` — não
  existe NENHUMA tela que mostre uma foto estática capturada, em nenhum
  fluxo de câmera do app.
- O fluxo de câmera (`CameraCaptureController`/`CameraCaptureView`,
  compartilhado por glicosímetro/pressão/balança/prato/rótulo) é
  **100% câmera ao vivo** (`camera` plugin), documentado explicitamente
  como antifraude: "there is deliberately no gallery entry point...
  never image_picker". O frame capturado é só bytes em memória, enviado
  direto pro servidor, e o arquivo temporário é apagado no `finally`
  (Zero Storage Pipeline) — nunca existiu um `File`/`path` persistente
  pra perder.

### Causa raiz real (confirmada no código-fonte do pacote `camera`)

`CameraValue.uninitialized` (pacote `camera` 0.12.0+1, instalado) nasce
com **`flashMode: FlashMode.auto`** — e `CameraCaptureController.
initializeCamera()` nunca mudava isso. Fotografar um rótulo nutricional
(embalagem glossy/reflexiva) de perto, em ambiente levemente escuro
(cozinha, despensa), aciona o flash automático e **estoura a imagem em
glare/reflexo** — o preview em tempo real E a foto capturada saem
genuinamente **brancas/lavadas**. Um frame assim também explica
"não extrai as informações": a IA de OCR não lê texto/números numa
imagem estourada de branco.

Isto é consistente com o próprio vocabulário do projeto: o campo
`possivel_foto_de_tela` (antifraude) já existe especificamente por causa
de "moiré, pixel grid, **glare** de monitor" — glare em superfícies
reflexivas já era um risco conhecido, só nunca tinha sido endereçado pro
flash do próprio celular.

### Correção

`lib/features/dashboard/presentation/controllers/camera_capture_controller.dart`
— `initializeCamera()` agora chama `controller.setFlashMode(FlashMode.off)`
logo após `controller.initialize()`, best-effort (um `try/catch` que só
loga — numa falha, a câmera continua funcionando normalmente, só sem a
garantia de flash desligado nesse device específico). Aplicado a TODOS
os tipos de captura (glicosímetro/pressão/balança/prato/rótulo) — glare é
um risco tanto em telas de aparelho quanto em embalagens, mesma causa.

### Verificação

- Sem teste automatizado possível para esta mudança — limitação
  **pré-existente e já documentada** no próprio código
  (`CameraCaptureView`, doc da classe): "o `CameraController` do pacote
  `camera` não é mockável". Nenhuma tela de câmera deste app tem
  cobertura de teste hoje, antes ou depois desta correção.
- Não verificado em device físico real nesta tarefa (ambiente sem acesso
  a device) — recomendação ao fundador: fotografar um rótulo glossy numa
  cozinha com luz ambiente normal (não escura) e confirmar que o flash
  não dispara mais / que o preview não estoura em branco.

## Verificação (Bug 1)

- **7 testes novos** em `index_test.ts` (Deno): "suco de manga" via
  léxico (alias do próprio alimento), "suco de abacaxi fresco" via léxico
  substring, "suco de abacaxi" via busca semântica, controle negativo
  (alimento já líquido calcula normal), controle negativo (sólido sem
  termo de líquido continua em gramas — restrição explícita), promoção
  de categoria em `medida_nao_encontrada`, e confirmação de que
  `medidasDisponiveis` nunca é enviada para `categoria_incompativel`.
- `deno check`: limpo.
- `deno test`: **130/130** (era 124/124 antes desta tarefa, +6 novos —
  nota: 1 teste precisou de ajuste de fixture durante a escrita, descrito
  no próprio código: "suco de abacaxi" sozinho não casa léxico, por
  design — coberto pelo caminho semântico, não pelo léxico).
- `flutter analyze`: 30 issues (linha de base do projeto, zero novo).
- `flutter test`: **518/518**, zero regressão (nenhum teste novo do lado
  Flutter — a correção em si é só no backend + no fluxo de câmera sem
  cobertura possível).

Branch `fix/bugs-registro-alimentar`, a partir de `main`.
