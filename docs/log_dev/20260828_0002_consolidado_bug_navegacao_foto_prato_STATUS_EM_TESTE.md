# RELATÓRIO 20260828_0002 — Consolidado: bug de navegação no registro de refeição por foto

**Data:** 2026-08-28
**STATUS: 🟡 EM TESTE — NÃO FECHADO.** O fix está deployado e funcionou nas
verificações feitas até agora, mas o fundador decidiu explicitamente manter
o item em aberto até rodar mais testes reais no aparelho antes de considerar
resolvido de vez. Este relatório existe pra consolidar o processo inteiro
num lugar só — os detalhes completos de cada etapa estão nos relatórios
individuais citados (`docs/log_dev/`), este é o resumo narrativo.

## O sintoma original

Testando o Método 4 (foto) do Registro de Refeição: a tela às vezes
mostrava "Analisando com IA..." e **fechava sozinha, sem erro nenhum**,
voltando pra tela anterior. Outras vezes mostrava um `TimeoutException`
explícito. Nenhum padrão óbvio — não era sempre na mesma tentativa, não
tinha relação clara com 1ª ou 2ª tentativa.

## Fase 1 — Hipótese do modelo/performance (20260825_0003)

Primeira leitura: o modelo CORE (`gemini-flash-latest`) usado na foto podia
bater 3 tentativas inteiras contra si mesmo antes de tentar o fallback pro
LITE, cada tentativa uma chamada de visão inteira (não instantânea) — e
cada retry ainda queimava cota própria (free tier, só 20 requisições/dia).
Corrigido: fallback dispara em qualquer falha do primário (não só cota),
primário ganha só 1 tentativa quando existe fallback, backoff reduzido,
cache do catálogo esticado de 5 pra 30 minutos, timeout do cliente subiu
pra 60s. Deployado.

**Não resolveu.** Fundador testou de novo e o bug continuou.

## Fase 2 — Investigação profunda sem alterar código (20260825_0004)

Fundador pediu investigação a fundo, "relate não altere", depois de perder
confiança na correção anterior. Chamando o Gemini **de verdade**, direto,
com a chave real do projeto (mesma técnica que já tinha achado a causa raiz
da cota num relatório anterior):

- CORE (`gemini-flash-latest`): variou de 200 OK em <2s até **503 "high
  demand" levando 45-59 SEGUNDOS só pra devolver o erro**.
- Uma chamada real de foto pela Edge Function de produção levou **141,7
  segundos** até responder (sucesso, mas lentíssimo).
- Uma chamada de áudio levou **150,8 segundos até a própria Supabase matar
  a função** com `WORKER_RESOURCE_LIMIT` — não é erro do Gemini, é o teto
  de execução da própria plataforma serverless sendo estourado.

Descartada nesta fase: rotação de secrets da Supabase (achada no caminho,
mas confirmada não-relacionada — "favoritos", que não usa Gemini, sempre
funcionou).

## Fase 3 — Troca de modelo, decisão de arquitetura (20260825_0005)

Perguntado como arquiteto sênior, de baixo custo, "será mesmo o modelo?":
sim — Flash-Lite nunca falhou em nenhum teste ao vivo do dia (inclusive com
imagem real), enquanto Flash oscilava entre normal e quase 2,5 minutos.
Fundador aprovou explicitamente: **"vamos então trocar o modelo de flash
para flash lite"**. `NIVEL_POR_TIPO[pratoRefeicao]`: `core`→`lite`.
Confirmado ao vivo contra produção: 2 fotos reais, sucesso em 72,9s e
11,7s — melhora real, mas reportado sem inflar (não instantâneo, Gemini
como um todo mostrou alguma variação naquele dia).

**Ainda não resolveu totalmente.** Fundador testou de novo: foto ainda
falhava às vezes, texto continuava "lento", áudio deu "servidor ocupado".

## Fase 4 — Descartando o modelo de vez (20260825_0006)

Fundador verificou **diretamente no Google AI Studio**: sem instabilidade,
sem cota estourada, naquele momento. Também descartou rede (mesmo sintoma
em Wi-Fi e dados móveis, testado por ele) e descartou o padrão "1ª vs 2ª
tentativa" (o erro já tinha ocorrido na 1ª tentativa também). Pediu um
relatório completo pra avaliação por um segundo agente de IA.

**Auditoria de código do APP** (não mais do servidor — primeira vez nesta
série): achado estrutural real, comparando os 3 fluxos de IA lado a lado —
só o de **foto** (`CameraCaptureView`) não tinha nenhuma checagem
`if (!mounted) return` antes de navegar depois da chamada de rede longa.
Texto e áudio (`gravar_refeicao_page.dart`) tinham em todos os pontos.
Hipótese, ainda não confirmada: Android suspendendo/recriando a tela
durante a espera longa.

## Fase 5 — Diagnóstico instrumentado, 2 etapas (20260825_0007 → 20260827_0001)

Tarefa estruturada (com apoio de outro agente de IA, seguindo o relatório
da Fase 4): **Etapa 1** só instrumenta (`console.log`/`debugPrint` em
pontos-chave do servidor e do cliente — chegada da resposta HTTP, ponto
exato antes de navegar, `initState`/`build` da tela de destino), **zero
mudança de comportamento**, e catalogação de todo `Navigator.pop`/retorno
antecipado da tela de confirmação. Nenhuma correção aplicada até um log
real reproduzido chegar.

Fundador trouxe o log da Edge Function de uma execução onde o bug
aconteceu: servidor rápido e saudável (3,3s, depois 8,7s numa segunda
reprodução), zero erro — **confirmando que o servidor nunca foi o
problema**.

**A evidência decisiva**, pareando o log do dispositivo (`adb logcat`) com
o da Edge Function da MESMA execução: do lado do device só apareceram 2
linhas — resposta HTTP 200 recebida, e "prato extraído com 8 itens —
chamando pushReplacement (**mounted=true**)" — e nada depois. Nenhum log
da tela de destino (`ConfirmacaoPratoController`/`ConfirmacaoPratoPage`,
instrumentados na Etapa 1) apareceu. **Prova concreta**: `mounted` já era
`true` no instante exato da chamada — a hipótese de Android desmontando a
árvore durante a espera fica descartada por evidência, não confirmada.
`pushReplacement` foi chamado, mas a tela de destino nunca rodou
`initState`. Nenhuma exceção em lugar nenhum.

## Fase 6 — A correção (20260827_0001)

Com o log real em mãos (condição que a Etapa 2 exigia), aplicadas as 3
ações já pré-combinadas:

1. Checagem de `mounted` em `_onStateChanged` — higiene, mesmo padrão do
   texto/áudio (não é a causa raiz confirmada, já que `mounted` provou
   estar `true`, mas fecha uma lacuna real pra outros cenários).
2. **`pushReplacement` → `push`** — a tela da câmera passa a ficar na
   pilha em vez de ser substituída imediatamente; se a rota nova falhar
   de novo, a câmera continua visível (não some sozinha). Confirmar grava
   e fecha as duas telas; cancelar reinicializa a câmera pra tentar de
   novo.
3. `Future` de `_capturar()` tratado com `.catchError` de verdade (antes
   era descartado no `onPressed`, silenciando qualquer exceção
   assíncrona).

`flutter analyze` limpo, Flutter 427/427. Deployado.

## Fase 7 — Confirmação real, mesmo dia

Fundador recompilou e testou de novo. **Pela primeira vez em toda a
investigação, o rastro completo apareceu**: resposta recebida → push
chamado → builder do `ConfirmacaoPratoPage` executando → `initState` →
`build` → controller construído. A tela de confirmação abriu de verdade.

## Por que isto continua "EM TESTE", não "RESOLVIDO"

Decisão explícita do fundador (28/08): **"vamos deixar o bug em aberto,
para mais teste"** — mesmo com os testes indo bem. Justificativa
implícita, e correta: o bug sempre foi intermitente, nunca falhou 100% das
vezes mesmo no código antigo — alguns sucessos seguidos não são prova
estatística suficiente. Também é honesto reconhecer que **a causa raiz
exata do "por que pushReplacement nunca rodava initState" não tem
confirmação mecanicista completa** — sabe-se ONDE ela morava (nessa janela
exata), o fix mudou o comportamento de um jeito que resolveu a reprodução
observada, mas não há certeza absoluta de que TODO caminho possível pra
esse sintoma foi eliminado.

**Enquanto o item estiver aberto:**
- Os `debugPrint`/`console.log` de diagnóstico continuam ativos de
  propósito no código (client + Edge Function) — não remover.
- Se o bug reaparecer, o método que já funcionou é pedir o log pareado
  (device `adb logcat` + Edge Function, mesma `execution_id`/horário) —
  não voltar a teorizar sobre modelo/rede/cota, já descartados com
  evidência real nesta investigação.
- Fechamento definitivo (e limpeza da instrumentação) só depois do
  fundador confirmar, após mais rodadas de teste.

## Índice de relatórios desta investigação

| Relatório | O que fez |
|---|---|
| 20260825_0003 | 1ª correção (performance/retry) — não resolveu |
| 20260825_0004 | Investigação sem alterar código — achou o Gemini genuinamente instável naquele dia |
| 20260825_0005 | Troca Flash→Flash-Lite, aprovada pelo fundador — melhorou mas não resolveu tudo |
| 20260825_0006 | Descartado o modelo (AI Studio, rede, padrão de tentativa) — achado: falta `mounted` só na foto |
| 20260825_0007 | Etapa 1 — instrumentação, zero mudança de comportamento |
| 20260827_0001 | Etapa 2 — a correção real (`push` em vez de `pushReplacement`), confirmada no mesmo dia |
| 20260828_0001 | (não relacionado ao bug — limpeza de branches obsoletas do repositório) |
| **20260828_0002** | **Este relatório — consolidação, status EM TESTE** |
