# RELATÓRIO 20260825_0003 — Corrige timeout do registro de refeição por foto + performance dos 3 métodos de IA

**Data:** 2026-08-25
**Pedido:** fundador testou os 4 métodos de registro de refeição pela
primeira vez. Texto e áudio funcionaram, mas "lentos" (áudio mais que
texto). Foto deu `TimeoutException` — mesma classe de erro já registrada
em `docs/bugs/`, imagem nova salva no mesmo caminho.

## Achado 1 — a screenshot anexada é de ANTES do fix de 24/08

A imagem em `docs/bugs/` mostra `TimeoutException after 0:00:30.000000`.
O timeout do cliente (`CameraCaptureController._uploadTimeout`) já tinha
sido aumentado pra **45s** no RELATÓRIO 20260824_0001 — se essa mensagem
viesse do build atual, diria "0:00:45", não "0:00:30". Os metadados do
arquivo no disco confirmam: `LastWriteTime`/`CreationTime` = 24/08, não
25/08. Ou seja, essa screenshot específica é do dia anterior — mas isso
**não invalida o relato de hoje**: o fundador reportou o mesmo timeout
acontecendo de novo em teste ao vivo, só que sem gerar screenshot nova.
Investigação seguiu pra achar a causa raiz de verdade, não descartar o
relato por causa de uma imagem desatualizada.

## Achado 2 — causa raiz real: o fallback de modelo só cobria cota, nunca 5xx esgotado

`processarPratoRefeicao` já roda a chamada ao Gemini e a leitura do
catálogo em paralelo (`Promise.all`, sem custo serial) — não era o
gargalo. O gargalo real estava em `criarChamadorGeminiComFallback`
(RELATÓRIO 20260824_0002): o modelo CORE (foto, `pratoRefeicao` — o único
que precisa de raciocínio de cena visual) só trocava pro LITE quando a
falha era **cota (429)**. Um 503 "high demand" (a MESMA instabilidade já
documentada duas vezes esta semana — curadoria de 23/08, teste de 24/08)
fazia o CORE bater as **3 tentativas inteiras contra SI MESMO** — cada uma
uma chamada de visão completa, não instantânea — mais o backoff entre
elas, ANTES de desistir de vez, sem nunca tentar o LITE. Isso sozinho
podia se aproximar ou passar dos 45s do cliente, e cada tentativa
consumida contra o CORE ainda queima cota própria — que no free tier é só
**20 requisições/DIA** (achado do RELATÓRIO 20260824_0002): uma única foto
que precisasse retentar já gastava até 3 dessas 20 vagas.

## Correção (`extract-metric-photo/index.ts`)

Duas mudanças em `criarChamadorGeminiComFallback`, mesmo espírito de
"degradação graciosa" já usado pra busca semântica
(`resolverComBuscaSemantica`: uma falha nunca derruba a função inteira):

1. **Fallback dispara em QUALQUER falha do primário** (não só cota) —
   `ErroHttp` genérico agora, não só `ErroCotaGemini`. Um 503 esgotado no
   CORE agora cai pro LITE automaticamente, igual já acontecia pra 429.
2. **O primário ganha só 1 tentativa quando existe fallback configurado**
   — não faz mais sentido retentar 3x contra o mesmo modelo restrito
   antes de tentar o substituto; o orçamento de retry cheio
   (`MAX_TENTATIVAS_VISAO`, 3 tentativas) agora vai pro modelo que
   **sobra** — o fallback, sem mais ninguém pra tentar depois dele (ou o
   próprio primário, nos tipos sem fallback configurado — texto/áudio,
   já no nível LITE mais barato).

Efeito líquido pra foto: falha mais rápido no CORE (1 tentativa em vez de
3), gasta 1/3 da cota que gastava antes por tentativa malsucedida, e cai
pro LITE (mais barato e tipicamente mais rápido) muito antes.

**Backoff reduzido** de 1.5s/3s pra 1s/2s em todas as chamadas desta
função — é uma requisição síncrona de usuário esperando na tela, não o
script de curadoria em lote que originalmente justificou o valor mais
lento (aquele nunca usou este código, é um script Node separado).

**`criarChamadorGeminiReal` ganhou `opcoes` opcionais**
(`maxTentativas`/`backoffBaseMs`, default = comportamento de sempre) —
`criarChamadorGeminiComFallback` é quem decide o orçamento por chamada
agora; nenhum chamador existente (incluindo os testes que usam a
assinatura de 2 argumentos) muda de comportamento.

**Cache do catálogo: 5min → 30min.** Achado ao investigar "texto/áudio
lentos": esse cache é por ISOLATE Deno, não compartilhado entre
instâncias — qualquer novo isolate (escala horizontal, ou cold start após
ociosidade) paga o round-trip inteiro de novo (~1,5s/~310KB) mesmo que
outro isolate tenha acabado de carregar o mesmo catálogo, e isso vale
igualmente pros 3 métodos (o catálogo é lido sempre, foto/texto/áudio).
5min era curto demais pra realmente "esquentar" o cache antes de expirar
de novo em uso não-intenso. 30min é uma troca melhor (edição no Admin
demora até 30min pra valer numa foto nova — aceitável, dado de curadoria
não muda a cada segundo).

## Cliente Flutter

`CameraCaptureController._uploadTimeout`: 45s → **60s**. Mesmo com o
CORE falhando rápido agora (1 tentativa), o pior caso genuíno continua
sendo "CORE falha uma vez + LITE esgota as 3 tentativas dele" — 60s dá
folga real pra esse caso sem fingir que ele não existe.
`RegistroRefeicaoIaService._uploadTimeout` (texto/áudio) alinhado no mesmo
valor por simplicidade — o pior caso real ali é bem menor (LITE não tem
fallback pra tentar, e é o modelo mais barato/rápido), 60s nunca atrapalha
o caminho comum.

## Sobre "áudio mais lento que texto"

Não é bug — é esperado: upload de um payload binário maior (mesmo um
áudio curto em base64 pesa mais que uma frase de texto) processado por um
modelo que precisa **ouvir** antes de interpretar, contra um modelo que só
lê texto direto. As melhorias de backoff/cache acima beneficiam os dois
igualmente, mas a diferença relativa entre eles é física, não uma falha
de implementação.

## Verificação

`deno check` limpo. Deno: **99/99 passou** (4 testes de
`criarChamadorGeminiComFallback` reescritos/adicionados pra cobrir o novo
comportamento — fallback em 5xx esgotado, primário+fallback falhando
juntos, e o caso "sem fallback" preservando o orçamento cheio de retry —
substituindo o teste antigo que agora descreveria o comportamento
ERRADO). `flutter analyze`: 30 avisos, todos pré-existentes e sem relação
com esta tarefa (nenhum arquivo tocado aqui aparece na lista). Flutter:
17/17 nos arquivos afetados (`registro_refeicao_ia_service_test.dart`,
`registro_refeicao_ia_controller_test.dart`,
`gravar_refeicao_page_test.dart`, `descrever_refeicao_page_test.dart`) —
nenhum teste fixa o valor exato do timeout, então o bump de 45s→60s não
quebrou nada. Edge Function deployada
(`supabase functions deploy extract-metric-photo`).

Nada verificado em device físico ainda — recomendado o fundador testar os
3 métodos de novo (texto/áudio/foto) no próximo acesso.
