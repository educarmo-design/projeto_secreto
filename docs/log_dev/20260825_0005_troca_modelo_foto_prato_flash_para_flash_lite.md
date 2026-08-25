# RELATÓRIO 20260825_0005 — Foto do prato migra de Flash (CORE) para Flash-Lite

**Data:** 2026-08-25
**Pedido:** depois da investigação profunda do RELATÓRIO 20260825_0004
(sem alteração de código), o fundador perguntou qual modelo estava sendo
usado na foto, se era mesmo o modelo, e pediu recomendação como
arquiteto sênior de baixo custo. A resposta apontou o Flash-Lite (nunca
falhou em nenhum teste do dia, inclusive com imagem real) como a troca
mais barata e imediata. Fundador aprovou: "vamos então trocar o modelo
de flash para flash lite".

## Mudança

`NIVEL_POR_TIPO[TIPO_PRATO_REFEICAO]`: `'core'` → `'lite'`
(`extract-metric-photo/index.ts`). Método 4 (foto) passa a usar
`gemini-flash-lite-latest`, o mesmo modelo já usado pelos Métodos 1/2
(texto/áudio) desde o RELATÓRIO 20260824_0003.

`TIPO_ROTULO` (OCR de rótulo nutricional) **não foi tocado** — continua em
CORE, decisão deliberada: dígito de macro impresso errado importa mais do
que "não reconheceu um item no prato", e não fez parte do pedido desta
tarefa.

Como CORE deixa de ser o nível de `pratoRefeicao`, o mecanismo de
fallback automático (`criarChamadorGeminiComFallback`, RELATÓRIO
20260824_0002/20260825_0003) passa a não configurar fallback pra foto
(`nivel === 'core' ? ... : null` — mesmo comportamento que texto/áudio já
tinham) — não tem pra onde degradar quando já se está no nível mais
barato, mesma lógica de sempre.

## Por que essa troca (recapitulando a investigação anterior)

RELATÓRIO 20260825_0004 mediu ao vivo: CORE variou de 200 OK em <2s até
503 "high demand" levando 45-59s só pra devolver o ERRO, e uma vez
estourou o teto de execução da própria Supabase (`WORKER_RESOURCE_LIMIT`,
~150s). LITE, testado em paralelo com imagem real, nunca falhou. Fixar
numa versão mais antiga do Flash pra fugir da fila foi investigado e
descartado nesta mesma conversa — Google desativa versões antigas
(`gemini-2.5-flash`/`gemini-2.0-flash` já são 404 "no longer available"),
então não existe "versão menos concorrida" pra escolher: todo mundo no
free tier acaba no mesmo "-latest".

## Verificação

`deno check` limpo. Testes atualizados pra refletir o novo roteamento
(3 alterados/divididos): `resolverModeloParaTipo` de "prato/rótulo usa
CORE" virou 2 testes separados (prato→LITE, rótulo→CORE); o teste do
override `GEMINI_MODEL_CORE` trocou de testar via `pratoRefeicao` pra
`rotulo` (único tipo em CORE agora). Deno: **100/100 passou**. Edge
Function deployada.

**Confirmação ao vivo pós-deploy** (mesmo usuário de teste descartável do
RELATÓRIO 20260825_0004, criado e apagado só pra isso): 2 chamadas reais
de foto pelo endpoint de produção — **200 OK em 72,9s e depois 11,7s**
(as duas com sucesso, nenhuma falha). Comparado ao CORE (141,7s até
sucesso, ou 150,8s até a Supabase matar a função), é uma melhora real e
substancial, mas **não é instantâneo nem 100% estável** — o Gemini como
um todo (não só o Flash) mostrou alguma variação hoje; o Flash-Lite só é
MUITO mais confiável, não imune a qualquer lentidão. Reportado sem
inflar: a troca reduz drasticamente o risco de timeout/falha, não é uma
garantia absoluta enquanto o projeto estiver no free tier compartilhado.

Nada verificado em device físico ainda — recomendado o fundador testar de
novo.
