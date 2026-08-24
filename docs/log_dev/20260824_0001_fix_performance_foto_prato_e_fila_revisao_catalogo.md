# 20260824_0001_fix_performance_foto_prato_e_fila_revisao_catalogo — Corrige lentidão/502 ao fotografar prato + fila de revisão do catálogo

Log de Máquina (Regra 10.3 — append-only). Continuação do RELATÓRIO
20260823_0004 (fundador confirmou catálogo populado, reportou 2 achados
reais em device físico).

## 1. Fila de revisão do catálogo — discoverabilidade

**Achado do fundador**: o campo de revisão existe na tabela, mas o
filtro que eu tinha colocado dentro de `AdminAlimentos.tsx` (checkbox
"Mostrar só alimentos que precisam de revisão") ficava escondido —
só aparece pra quem já está na tela e nota o checkbox.

**Entregue** (pedido explícito, spec já veio pronta):
- 2 novos cards no dashboard admin (`AdminOverview.tsx`): "Alimentos em
  revisão" e "Medidas caseiras em revisão", cada um com a contagem real
  (`count: 'exact', head: true`, `eq('revisao_necessaria', true)`) e um
  link.
- Nova tela `AdminRevisaoCatalogo.tsx` (2 rotas: `/admin/revisao/
  alimentos` e `/admin/revisao/medidas-caseiras`) — fila dedicada, cada
  item já mostra a observação de revisão DIRETO na lista (sem precisar
  abrir nada), com checkbox "precisa de revisão" + textarea de
  observação editáveis inline e botão salvar por item. Desmarcar e
  salvar tira o item da fila na hora (a lista É o filtro). A fila de
  medidas caseiras mostra também o NOME do alimento associado (join do
  lado do cliente — 2 queries simples, mais barato que declarar a
  `Relationship` no `database.ts` só pra uma tela pequena).
- Ambas as telas reaproveitam o CRUD completo já existente em
  `AdminAlimentos.tsx`/`MedidasCaseirasPanel` pra quem quiser editar
  mais do que a observação (link "Ir para o catálogo completo").

## 2. Lentidão/erro ao fotografar prato — causa raiz confirmada

**Evidência**: 3 screenshots do fundador testando em device real
(salvos em `docs/bugs/`, commitados como evidência):
- `TimeoutException` no cliente Flutter após 30s.
- 2x `HTTP 502` — corpo `{"error":"Falha ao analisar a imagem."}`.

### Causa raiz #1 — zero retry no Gemini (achado, não suposição)

`criarChamadorGeminiReal` (a chamada de visão que identifica os itens
do prato, modelo CORE `gemini-flash-latest` — ver `NIVEL_POR_TIPO`)
não tinha NENHUM retry: qualquer 429/5xx do Gemini virava 502
definitivo na hora. **O mesmo modelo CORE bateu HTTP 503 "high demand"
durante a curadoria em massa do catálogo na véspera** (RELATÓRIO
20260823_0004, log da corrida) — evidência direta de que esse erro
transitório é real e recorrente nesta conta/modelo, não hipotético.

Corrigido: retry com backoff curto (2 tentativas extras, 1.5s/3s —
orçamento pequeno de propósito, é uma requisição síncrona de usuário
com timeout no cliente, não um script de carga em lote que pode
esperar minutos). Só retenta 429/5xx; 404 (modelo errado) continua
falhando na hora, como antes.

### Causa raiz #2 — leitura completa do catálogo em TODA foto

`criarCatalogoAlimentosReal` lê `alimentos_referencia` INTEIRA (com
`alimentos_medidas_caseiras` aninhada) do zero em TODA foto de prato —
sempre foi assim, mas depois da curadoria em massa (270→1.056 linhas
de medida) esse round-trip ficou bem mais pesado. **Medido nesta
tarefa**: ~1,5s e ~310KB por chamada, sempre, mesmo o catálogo mudando
raramente (só quando um admin edita).

Corrigido: cache em memória no escopo do módulo (nível de isolate
Deno), TTL de 5 minutos. Correto mesmo compartilhado entre usuários
diferentes — o dado é público do produto (RLS `using (true)`), o
resultado da query é idêntico não importa de quem for o JWT. Elimina o
round-trip pra praticamente toda foto enquanto a instância ficar
"quente"; zera sozinho a cada cold start ou a cada 5 minutos.

### Ajuste complementar no cliente

`CameraCaptureController._uploadTimeout`: 30s → 45s — o retry do
servidor agora pode levar até ~4,5s a mais em caso de erro
transitório; o cliente precisa de folga pra não desistir antes do
servidor terminar de tentar.

### Achados técnicos extras (ao rodar `deno check` limpo, RELATÓRIO
20260823_0004 já tinha corrigido 2 gaps parecidos nesta mesma função —
esta tarefa não achou novos, só confirma que continua limpo depois das
mudanças de hoje).

## Verificação (feita ao final)

- **Deno**: `deno check` limpo. `deno test`: **82/84 passando** (+2
  testes novos cobrindo o retry: 503 seguido de sucesso na 2ª
  tentativa, e 429 esgotando as tentativas lança erro) — as mesmas 4
  falhas pré-existentes já documentadas no RELATÓRIO 20260823_0004
  (não relacionadas, `encontrarMedida`/fallback, confirmadas antes via
  worktree isolado).
- **Flutter**: `flutter analyze` limpo. `flutter test`: **407/407**,
  sem regressão.
- **Painel React**: `tsc -b` e `eslint` limpos nos arquivos tocados.
- Deploy: `supabase functions deploy extract-metric-photo` (retry +
  cache já em produção).

## Não resolvido / próximo passo

- Não testado em device físico ainda (trabalho local). Recomendo o
  fundador refazer o teste de fotografar um prato — se o 502
  "Falha ao analisar a imagem" persistir mesmo com retry, é sinal de
  que o Gemini está indisponível por mais de ~4,5s seguidos (fora do
  que um retry curto resolve) e vale investigar se o modelo CORE
  precisa ser trocado por um mais estável nesta conta (mesma decisão
  já tomada ad-hoc na curadoria de ontem, que usou `gemini-flash-lite-
  latest` em vez do CORE por causa do mesmo erro).
- O cache de 5 minutos significa que uma edição feita agora mesmo em
  `AdminAlimentos.tsx`/fila de revisão pode demorar até 5min pra
  valer na próxima foto — aceitável pra dado de curadoria, mas vale o
  fundador saber que não é instantâneo.
