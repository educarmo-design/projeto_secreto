# Prévia da foto na tela de resultado do Rótulo Nutricional

**Tipo:** Feature de UX — reverte uma decisão explícita anterior do fundador.

## Contexto: isto muda uma decisão já tomada nesta mesma saga

No RCA anterior (`20261016_0004_hotfix_ocr_rotulos.md`), ao investigar o
"quadrado branco" na tela de resultado, confirmei que esta tela **nunca
teve nenhum widget de imagem** — pipeline Zero Storage, câmera 100% ao vivo,
sem `Image.file`/`Image.memory` em lugar nenhum. Perguntei explicitamente ao
fundador se, mesmo assim, valeria adicionar uma prévia real da foto — a
resposta então foi **não**, preservar o design Zero Storage usado em todos
os tipos de captura do app.

Esta tarefa chega com a mesma pergunta, agora respondida ao contrário:
"em termos de UX, é inaceitável que o usuário tire uma foto e não veja o
preview do que acabou de capturar". Tratado como decisão nova e válida do
fundador, não como contradição a corrigir — implementada como pedida,
registrando aqui a reversão para o histórico ficar rastreável.

## O que de fato muda na pipeline Zero Storage

Nada na gravação em disco. `CameraCaptureController.capturarEEnviar` já lia
os bytes da foto em memória (`capturedFile.readAsBytes()`) ANTES de montar o
corpo do upload — isso nunca mudou. O que muda: esses MESMOS bytes (nunca
uma 2ª leitura do arquivo) agora também ficam guardados em
`CameraCaptureState.capturedImageBytes`, só para `TipoAparelho.rotulo`, até
o usuário confirmar/tentar de novo/sair da tela (quando o estado é
substituído e a referência é liberada pelo Dart). O arquivo temporário do
plugin `camera` continua sendo apagado do disco no `finally` de
`capturarEEnviar`, exatamente como antes — a garantia real de "nunca grava
nada permanentemente" não foi tocada, só a janela de vida dos bytes em RAM
foi esticada de "durante o upload" para "durante a revisão do resultado".

## Implementação

- `CameraCaptureController`/`CameraCaptureState`: novo campo
  `capturedImageBytes` (`Uint8List?`), preenchido só no branch de sucesso de
  `TipoAparelho.rotulo` — os outros 4 tipos de aparelho continuam sem
  nenhuma mudança de comportamento (campo permanece `null`).
- `CameraCaptureView._buildResultadoRotulo`: nova miniatura no topo da
  tela de resultado (acima do aviso de "possível foto de tela" e do Card de
  macros) — `ClipRRect` com `borderRadius: 12`, `Image.memory(fotoBytes,
  height: 200, width: double.infinity, fit: BoxFit.cover)`.
- `errorBuilder` no `Image.memory` — se os bytes não decodificarem (teórico,
  nunca reproduzido, mas a tarefa pediu defesa explícita), mostra um ícone
  cinza + "Imagem indisponível" (`dashboard.camera_rotulo_foto_indisponivel`,
  pt/en/es) em vez de quebrar a tela.
- **Zero alteração na lógica de envio** (Restrição da tarefa) — nenhuma
  linha de `capturarEEnviar` antes do `return` de sucesso do rótulo foi
  tocada; o único acréscimo é o novo campo no `CameraCaptureState` já
  construído ali.

## Verificação

- Novo teste `camera_capture_view_foto_preview_test.dart` (2 testes) —
  isola o mecanismo `Image.memory`/`errorBuilder` de verdade (PNG mínimo
  válido de 67 bytes decodifica e renderiza; bytes corrompidos acionam o
  fallback, sem exceção). `CameraCaptureView`/`CameraCaptureController`
  continuam sem teste próprio — limitação pré-existente (`CameraController`
  não é mockável).
- `flutter analyze`: 30 issues (linha de base, zero novo).
- `flutter test`: **544/544** (era 542/542, +2 novos).

## Banco de dados

Nenhuma alteração. Nenhuma Edge Function alterada — sem deploy pendente.

Branch `feat/ui-preview-foto-rotulo`, a partir de `main`.
