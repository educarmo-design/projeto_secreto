# Rework — bugs de registro alimentar persistindo após o fix anterior (20261015_0003)

**Tipo:** RCA (2ª rodada) + correção. Fundador testou no device físico com a
`main` atualizada (PR #6 mesclado) e os 2 bugs persistiram — mas com uma
pista nova e decisiva: o flash não acionou mais (prova que o fix anterior
RODOU no app), mas a imagem continua branca e "copo" continua travando.

## Bug 2 — "copo de suco de manga" ainda trava: causa raiz real é DEPLOY, não lógica

### Achado decisivo

A Edge Function `extract-metric-photo` (que contém TODO o fix do
`20261015_0003` — `categoriaIncompativel`/`categoriaEfetiva`) estava, em
produção, na **versão 47, última atualização confirmada em 2026-09-14**
(`supabase functions list`, campo `updated_at`) — **mais de um mês antes**
do commit que implementou aquele fix (`f8cb2b1`, 2026-10-15, mesclado via
PR #6 em 2026-10-16). **Não existe nenhuma automação de deploy neste
projeto** (`.github/` não tem nenhum workflow) — mesclar no Git nunca
implanta a Edge Function sozinho; isso sempre exigiu (e continua exigindo)
um `supabase functions deploy` manual, separado do `git merge`.

**Ou seja: o fix de Bug 1 (líquidos) do relatório anterior estava 100%
correto e nunca chegou a rodar em produção.** O comportamento relatado
("não tem copo cadastrado") é exatamente o comportamento ANTIGO
(`medida_nao_encontrada`), porque o código antigo (sem `categoriaIncompativel`)
é o que de fato está servindo as requisições até este momento.

### Correção complementar (além de garantir o deploy)

A tarefa também pediu explicitamente para o dicionário de medidas parar de
"rejeitar" recipientes comuns. Investigando `encontrarMedida`, confirmei
que não existe uma lista global de "unidades aceitas" rejeitando palavras —
cada alimento tem suas PRÓPRIAS medidas cadastradas (`alimentos_medidas_caseiras`,
corretamente específicas: uma "xícara" de arroz não pesa o mesmo que uma
de feijão). O que faltava: quando o alimento já é **confirmadamente
líquido** (`categoria_consumo`) mas não tem *aquele* recipiente específico
cadastrado (ex.: tem "copo" mas não "garrafa"/"taça"/"caneca"), a função
devolvia `medida_nao_encontrada` em vez de usar uma equivalência genérica
em ml — razoável, pela mesma aproximação de densidade~1 que o app já usa
em outros lugares (badge "150g"/"200ml" no Flutter).

Novo mapa `FATORES_RECIPIENTE_LIQUIDO_ML` (`copo`: 200ml, `taça`: 200ml,
`xícara`: 200ml, `caneca`: 300ml, `garrafa`: 500ml, `lata`: 350ml), usado em
`encontrarMedida` **só como último recurso** — depois do match exato/
substring pelas medidas reais do alimento, e **só quando
`categoria_consumo` já é líquido** (nunca para inferir isso — essa
inferência continua sendo papel exclusivo de `categoriaIncompativel`/
`categoriaEfetiva`, que agem ANTES, resolvendo casos como "suco de manga"
onde o alimento casado é sólido). **Nunca se aplica a alimentos sólidos**
— "garrafa de manga congelada" continua corretamente `medida_nao_encontrada`,
testado explicitamente (restrição da tarefa, não quebrar sólidos).

## Bug 1 — foto do rótulo continua branca mesmo com o flash desligado

### A hipótese do glare estava incompleta, não errada — e a nova pista aponta pro real culpado

Reconfirmado primeiro (igual ao RCA anterior): **zero** uso de
`Image.file`/`Image.memory`/`image_picker` em todo o projeto — a tela
nunca mostra uma foto estática, é câmera 100% ao vivo. O flash desligado
(confirmado pelo fundador) descarta glare como causa ÚNICA, mas não
invalida que o problema seja de captura/estado da câmera, como a tarefa
já suspeitava.

**Causa raiz real, confirmada no próprio README do pacote `camera`
instalado** (`camera-0.12.0+1`, seção "Handling Lifecycle states"):

> "As of version 0.5.0 of the camera plugin, lifecycle changes are no
> longer handled by the plugin. This means developers are now
> responsible to control camera resources when the lifecycle state is
> updated. **Failure to do so might lead to unexpected behavior**"

`CameraCaptureView` **nunca implementava isso** — nenhum
`WidgetsBindingObserver`, `didChangeAppLifecycleState` nunca existiu nesta
tela, em nenhuma versão até agora (confirmado lendo o histórico do
arquivo). Em device físico real, a Activity pode ser pausada/retomada sem
o usuário perceber claramente — o diálogo de permissão de câmera (comum na
1ª vez que "Rótulo" é usado), uma notificação, o próprio Android liberando
a câmera por um instante para outro app — e sem o tratamento oficial, o
`CameraController` nativo fica "preso" num estado inválido: a prévia (e
qualquer foto tirada a partir dela) sai branca/sem dados reais, porque a
câmera de verdade parou de entregar frames novos e o Flutter não tem como
saber. Isto explica o bug persistir **mesmo com o flash certo** — a causa
nunca foi (só) exposição/glare, foi a câmera nativa ficando órfã depois de
uma transição de lifecycle que a tela nunca tratava.

### Correção

- `CameraCaptureController.pausarCamera()` (novo método): libera só o
  `CameraController` nativo (nunca o `httpClient` nem o estado da tela) —
  chamado pela View em `inactive`/`paused`.
- `_CameraCaptureViewState` agora usa `with WidgetsBindingObserver`,
  registra/remove o observer em `initState`/`dispose`, e implementa
  `didChangeAppLifecycleState` seguindo literalmente o padrão oficial do
  README: `inactive`/`paused` → `pausarCamera()`; `resumed` → chama
  `initializeCamera` de novo — só reinicializa se foi ELE MESMO quem
  pausou antes (flag `_cameraPausadaPeloLifecycle`), nunca num `resumed`
  solto que não seguiu uma pausa real.
- Guarda explícita: nunca pausa a câmera no meio de uma captura/upload em
  voo (`_controller.value.isBusy`) — pausar o `CameraController` enquanto
  `takePicture()` ainda o usa derrubaria a operação com um erro pior.

## Verificação

- **Backend**: `deno check` limpo; `deno test` **132/132** (era 130/130,
  +2 novos: recipiente genérico resolvendo "garrafa" pra um líquido sem
  essa medida cadastrada; confirmação de que o mesmo recipiente NUNCA se
  aplica a um alimento sólido). Teste anterior que usava "garrafa" como
  medida ausente foi ajustado pra usar "jarra" (fora até do fallback
  genérico) — a mudança de comportamento era esperada e correta (ver
  commentário no próprio teste).
- **Flutter**: `flutter analyze` 30 issues (linha de base, zero novo);
  `flutter test` 519/519, zero regressão. **Sem teste novo** pro fix de
  lifecycle da câmera — limitação pré-existente e já documentada
  (`CameraController` do pacote `camera` não é mockável; nenhuma tela de
  câmera deste app tem cobertura de teste).

## Ação pendente, fora do alcance de um commit: DEPLOY da Edge Function

Esta tarefa (e a anterior, `20261015_0003`) corrigem o código-fonte, mas
**nenhum merge no GitHub implanta a Edge Function sozinho**. Pra o Bug 2
de fato parar de acontecer no app do fundador, alguém com acesso ao
projeto Supabase precisa rodar:

```
supabase functions deploy extract-metric-photo
```

depois que esta PR for mesclada — isto não é código de Flutter nem pode
ser resolvido só com `git merge`. Recomendo fortemente considerar
automatizar isso (GitHub Action no merge de `main` tocando
`supabase/functions/**`) numa tarefa futura, pra este exato tipo de "fix
correto que nunca chega a rodar" não se repetir.

Branch `fix/rework-bugs-alimentares`, a partir de `main`.
