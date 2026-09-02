# RELATÓRIO 20260901_0003 — "Servidor Ocupado" fantasma, latência real do Gemini, badge g/ml

**Data:** 2026-09-01
**Branch:** `fix/performance-ux-registro` (a partir de `fix/hotfix-ui-matematica-n27`, ainda não mesclada — ver "Estado das branches", **dependência importante**)
**Pedido:** Teste físico detectou lentidão na rotação IA, erro intermitente "Servidor Ocupado" sem bater cota, e badge do alimento mostrando descrição em vez de g/ml.

## Achado 1 — o "Servidor Ocupado" era, na maior parte das vezes, uma mentira

Auditoria de `CameraCaptureController.capturarEEnviar` (foto) e
`RegistroRefeicaoIaService._chamar`/`RegistroRefeicaoIaController._executar`
(texto/áudio) encontrou a MESMA mensagem genérica (`"Servidor ocupado ou
falha na leitura. Tente novamente."`) disparando em **três situações bem
diferentes**, só uma delas de fato sendo "o servidor está ocupado":

1. **Qualquer HTTP ≥ 500** — incluindo os únicos status que
   `extract-metric-photo` de fato emite hoje (confirmado lendo o código:
   só `500`/`502`/`429`, **nunca 503 nem 504**). Pior: o backend já manda
   uma mensagem REAL no corpo (`{"error": "Falha ao analisar a
   imagem."}` num 502 do Gemini, por exemplo — `_extrairMensagemErroBackend`
   já sabia ler isso, mas só era chamada pros 4xx) e o cliente **jogava
   essa mensagem honesta fora** pra mostrar "ocupado" no lugar.
2. **`TimeoutException`** (o cliente desistiu de esperar) — não é a mesma
   coisa que "servidor ocupado": pode ser o Gemini lento, pode ser a rede
   do aparelho. O código afirmava saber a causa sem saber.
3. **`http.ClientException`** (falha de conexão — sem internet, DNS,
   conexão recusada) — o pedido **nem chegou a sair do aparelho**. Esta é
   a mentira mais grave das três: dizer "servidor ocupado" quando o
   problema é a própria rede do usuário.

**Correção** (`camera_capture_controller.dart` e
`registro_refeicao_ia_service.dart`/`_controller.dart`, mesmo padrão nos
dois): "Servidor ocupado" agora só aparece quando (a) não há mensagem do
backend E (b) o status é genuinamente `503`/`504`. Todo outro `5xx` sem
mensagem vira "Erro no servidor" (honesto, mas não finge saber a causa).
`TimeoutException` vira "Tempo esgotado aguardando o servidor".
`http.ClientException` vira "Falha de conexão. Verifique sua internet".
Nenhuma dessas mensagens expõe stack trace (Regra 0.15 — detalhe técnico
continua só em debug via `debugDetail`).

## Achado 2 — a latência é real, é o Gemini, e o timeout do cliente estava apertado demais

Não existe comando de logs no Supabase CLI usado neste projeto (`supabase
functions --help`/`inspect --help` confirmados sem nenhum subcomando de
log; Dashboard exige exportação manual). Em vez de af de log histórico,
medi a API do Gemini **de verdade, hoje**, com o modelo exato que
`pratoRefeicao` usa (`gemini-flash-lite-latest`, nível LITE — confirmado
em `NIVEL_POR_TIPO`) — 3 chamadas sequenciais, imagem TRIVIAL (1x1 pixel,
pra isolar variação do MODELO, não da imagem):

```
Chamada 1: 200 em 2.181ms
Chamada 2: 200 em 1.719ms
Chamada 3: 200 em 42.998ms
```

A terceira chamada — **sucesso** (200), não um erro — levou quase 43
SEGUNDOS numa imagem de 1 pixel. Isso é variação real e conhecida da API
do Gemini (não um bug do nosso código); uma foto de comida real, maior e
mais complexa, só piora essa cauda.

**O gargalo não é pgvector nem catálogo**: a busca semântica só roda
quando o casamento léxico falha (Missão F45), e o carregamento do
catálogo (637 alimentos) já é cacheado em memória por 30min desde
20260825_0003 — nenhum dos dois aparece no caminho comum de uma foto de
prato. **O gargalo é 100% a chamada ao Gemini.**

**O problema real**: com `MAX_TENTATIVAS_VISAO=3` do lado do servidor
(nível LITE não tem fallback de modelo — já é o mais barato, então recebe
o orçamento cheio de retry), uma ÚNICA tentativa já pode chegar perto ou
passar dos 60s que o cliente Flutter esperava
(`CameraCaptureController._uploadTimeout`/`RegistroRefeicaoIaService._uploadTimeout`).
Isso faz o CLIENTE desistir (`TimeoutException`) enquanto o SERVIDOR
ainda ia responder com sucesso — exatamente o "timeout mal configurado
no cliente HTTP" que a tarefa pediu pra identificar.

**Correção**: os dois timeouts (foto e texto/áudio) subiram de 60s pra
90s — folga real pra uma tentativa lenta isolada, sem virar uma espera
infinita (uma tela "carregando" pra sempre também é falha de UX). Não
mudei o orçamento de retry do servidor (`MAX_TENTATIVAS_VISAO`): a
chamada lenta medida foi um SUCESSO, não uma falha que precisasse de
retry — reduzir tentativas não teria evitado este sintoma específico,
só reduziria resiliência a falhas reais.

## Achado 3 — badge mostrava o nome da medida, não o peso

`_ItemPratoTile` (RELATÓRIO 20260901_0002, ainda não mesclado) mostrava
`original.medida` (ex.: "colher de sopa", "xícara") no badge do card —
não diz nada sobre quantos gramas/ml aquilo representa de verdade.
Trocado pra sempre mostrar peso calculado + grandeza base: `"150g"`,
`"200ml"`. A grandeza vem de `unidadeMedidaPadrao` (quando o alimento tem
categoria definida no catálogo) ou infere por `categoriaConsumo`
(líquidos); sem nenhum dos dois, assume `'g'` (caso mais comum, e a TACO
já reporta macros por 100g pra tudo). O nome da medida caseira continua
visível — só migrou pra linha de baixo, perto dos botões -/+ ("2 colher
de sopa"), como contexto de QUAL medida a IA leu.

## Decisões técnicas

| Decisão | Motivo |
|---|---|
| Prioridade da mensagem do backend em QUALQUER status, não só 4xx | O backend já é honesto (Regra 0.15) — o bug era o cliente jogar isso fora |
| "Servidor ocupado" reservado a 503/504 sem mensagem, não todo 5xx | Restrição explícita do pedido; hoje isso deixa a mensagem "adormecida" (a função nunca emite 503/504 por código próprio), mas fica pronta pra um 503 genuíno de infraestrutura (gateway do Supabase, não da nossa função) |
| Timeout do cliente 60s→90s, não redesenho do retry do servidor | A evidência medida foi uma chamada LENTA MAS BEM-SUCEDIDA — dar mais tempo ao cliente ataca a causa raiz observada; mexer no retry do servidor seria uma mudança não sustentada pela evidência coletada |
| `RegistroRefeicaoIaService._uploadTimeout` virou injetável (parâmetro de construtor) | Só assim dá pra testar o caminho de `TimeoutException` sem um teste de 90s reais |
| Badge mostra peso+unidade, nome da medida migra pra linha de baixo (não desaparece) | As duas informações são úteis e complementares — qual medida a IA leu, e quanto isso pesa de verdade |

## Infra/config

Nenhuma migration. Nenhum secret novo. Nenhum deploy de Edge Function
necessário nesta tarefa — **toda a correção do erro fantasma e do
timeout é client-side** (o backend já mandava as mensagens certas; só
precisava ser lido). O script de medição de latência (`scratchpad`, não
commitado) confirmou isso rodando contra a API real do Gemini, não
precisou tocar `extract-metric-photo`.

## Entidades novas

Nenhuma. 3 chaves i18n novas (`camera_server_error`,
`camera_timeout_error`, `camera_network_error`), não são entidades.

## Desvios de spec

Nenhum. A auditoria de latência não pôde usar logs históricos do
Supabase (sem tooling disponível nesta sessão para isso — documentado
acima); usei medição ao vivo da mesma API/modelo como evidência
equivalente, mais direta inclusive (prova o comportamento de HOJE, não
de uma data passada).

## Problemas encontrados

- As 3 situações do "erro fantasma" (achado 1) — corrigidas.
- Timeout do cliente apertado demais pro pior caso real do Gemini
  (achado 2) — corrigido (60s→90s nos dois pontos).
- Nenhum outro problema novo encontrado na auditoria.

## Riscos mapeados + mitigação

- **Risco residual, baixo:** a variação do Gemini (2s a 43s+ na mesma
  chamada, mesmo modelo, mesmo dia) é uma dependência externa — 90s
  reduz falsos timeouts mas não elimina a variação em si. Se a cauda
  piorar (ex.: chamadas de 90s+ virarem comuns), o próximo passo seria
  arquitetura assíncrona (já registrado como recomendação em
  20260825_0004 — fora do escopo de um hotfix).
- **Risco de dependência entre branches, novo:** esta branch parte de
  `fix/hotfix-ui-matematica-n27` (ainda não mesclada) porque o badge que
  o Achado 3 corrige foi criado lá. Mesclar esta branch sem mesclar a de
  baixo primeiro vai gerar conflito/perda de contexto. Ver "Estado das
  branches".
- Nenhum novo risco de segurança/dado — mudanças são só de mensagens de
  erro e valores de timeout/exibição, zero mudança de cálculo ou
  autorização.

## Como o fundador testa (ACEITE)

1. **Card exibe g/ml**: fotografar/descrever qualquer refeição — o badge
   do card deve mostrar peso + "g" ou "ml" (ex.: "150g"), não mais o nome
   da medida caseira.
2. **Timeout/falha mostram mensagem específica**: mais difícil de forçar
   deliberadamente (depende de rede/Gemini reais), mas se acontecer: sem
   internet deve mostrar "Falha de conexão..."; demora real deve mostrar
   "Tempo esgotado..."; nunca mais "Servidor ocupado" pra esses dois
   casos.
3. **Lentidão em si**: continua existindo (é o Gemini, não nosso código)
   — o que muda é o app não desistir prematuramente nem mentir sobre a
   causa quando isso acontece.

## Como a performance foi tratada

O timeout maior (90s) É a mudança de performance desta tarefa — dá mais
chance de uma chamada legitimamente lenta terminar com sucesso em vez de
o cliente abortar e o usuário ter que tentar de novo do zero (o que,
ironicamente, gastava MAIS tempo total e MAIS cota de IA do que só
esperar a primeira chamada terminar). Nenhuma mudança no volume de
chamadas de rede nem no processamento do lado do servidor.

## Verificação

- `flutter analyze`: mesmos avisos pré-existentes, nenhum novo (ver saída
  completa no commit).
- Flutter: suíte completa rodada após todos os ajustes — nutrition
  (160/160), suíte inteira sem regressão. Testes novos: 2 no card
  (badge g/ml — sólido, líquido, acompanha edição de quantidade — mais o
  ajuste do teste antigo de "filé"), 5 no serviço (502 sem/com mensagem,
  503/504 genuínos, timeout injetado, ClientException), 2 no controller
  (fallback defensivo de Timeout/ClientException direto), 2 testes
  antigos com string de mock desatualizada corrigidos (não testavam
  lógica real, só o "eco" da mensagem — atualizados por clareza).
- Nenhum arquivo Deno/Edge Function tocado — suíte Deno não re-executada
  (fora do escopo desta entrega, confirmado na investigação que a
  correção é 100% client-side).

## Estado das branches

**Importante:** `fix/performance-ux-registro` parte de
`fix/hotfix-ui-matematica-n27` (não de `main` diretamente), porque o
badge que o Achado 3 corrige foi criado lá e ainda não foi mesclado.
Nenhuma das duas está mesclada em `main` ainda.

**Instruções de PR:**

```
git push -u origin fix/performance-ux-registro
# Abrir PR contra fix/hotfix-ui-matematica-n27 (não contra main),
# já que esta branch depende diretamente daquela:
gh pr create --base fix/hotfix-ui-matematica-n27 --head fix/performance-ux-registro \
  --title "fix: erro 'Servidor Ocupado' fantasma + timeout de rede + badge g/ml" \
  --body "Ver docs/log_dev/20260901_0003_performance_ux_registro_erro_fantasma.md — depende de fix/hotfix-ui-matematica-n27"
```

**Sugestão de merge:** mesclar `fix/hotfix-ui-matematica-n27` em `main`
primeiro (já tem relatório e PR próprios), depois mesclar esta em cima —
ou pedir pra eu mesclar as duas juntas na ordem certa quando autorizado.
Não mesclar esta branch isolada em `main` sem a de baixo: o badge que ela
modifica não existiria em `main` ainda, e o merge ficaria confuso.
