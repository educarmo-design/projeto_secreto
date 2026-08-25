# RELATÓRIO 20260825_0004 — Investigação profunda do timeout persistente (SEM alteração de código)

**Data:** 2026-08-25
**Pedido explícito do fundador:** "Relate não altere" — depois do fix do
RELATÓRIO 20260825_0003 não ter resolvido nada em teste real (foto ainda
timeout, texto ainda lento, áudio agora com "servidor ocupado"), pediu
investigação a fundo sem nenhuma mudança de código, porque perdeu
confiança nos diagnósticos anteriores ("anteriormente isso estava
funcionando normalmente").

**Este relatório não mudou nenhum arquivo de produção** — só leitura de
código/config já existente e chamadas reais de diagnóstico (ao Gemini
direto e à própria Edge Function já deployada), com limpeza do usuário de
teste descartável criado só pra autenticar essas chamadas.

## Metodologia

Em vez de teorizar sobre timing, chamei os sistemas de verdade e medi:

1. Gemini `generateContent` direto (`gemini-flash-latest` e
   `gemini-flash-lite-latest`), mesma técnica já usada com sucesso no
   RELATÓRIO 20260824_0002 pra achar a causa raiz real da cota.
2. A Edge Function `extract-metric-photo` JÁ DEPLOYADA (commit `cac9393`,
   RELATÓRIO 20260825_0003), com um usuário de teste descartável criado
   via Admin API só pra ter um JWT válido (deletado ao final) — pros 3
   tipos: texto, foto, áudio.

## Achado 1 — o fix de 20260825_0003 partiu de uma premissa errada

Aquele fix assumiu que um 503 do Gemini volta RÁPIDO (por isso reduzir
tentativas/backoff pareceria suficiente). **Não é o que acontece agora**:

| Chamada | Resultado | Tempo |
|---|---|---|
| Gemini `gemini-flash-latest` direto (CORE) | 503 "high demand" | **44,9s** |
| Gemini `gemini-flash-latest` direto (CORE), de novo | 503 "high demand" | **58,9s** |
| Gemini `gemini-flash-lite-latest` direto (LITE) | 200 OK | 571ms |
| Gemini `gemini-flash-lite-latest` direto (LITE), de novo | 200 OK | 715ms |

O modelo CORE não está falhando rápido — está **demorando quase 1 minuto
só pra DEVOLVER O ERRO**. Reduzir de 3 tentativas pra 1 (o fix de
20260825_0003) não ajuda quando a ÚNICA tentativa já consome sozinha
quase todo o orçamento de tempo que existia.

## Achado 2 — a Edge Function real confirma isso, e revela algo pior

Chamando a função já deployada (não simulação — o endpoint de produção):

| Tipo | Status | Tempo total |
|---|---|---|
| Texto (LITE, sem imagem) | 200 OK | 3,2s — normal |
| **Foto (CORE)** | 200 OK (mas 0 itens — a imagem de teste era só 1 pixel) | **141,7s** |
| **Áudio (LITE, com dado binário)** | **546 `WORKER_RESOURCE_LIMIT`** | **150,8s** |

O caso do áudio é o achado mais importante: **546 não é um erro do
Gemini** — é o próprio runtime da Supabase (Deno Deploy por baixo) matando
a função por estourar o limite de execução da plataforma (~150s, não
configurado por nós — não existe `max_duration` em `config.toml`, é o
teto padrão do serviço). Ou seja: o Gemini está tão lento hoje que nem a
NOSSA função consegue esperar o tempo todo — a própria infraestrutura
serverless desiste primeiro.

## Por que "antes funcionava normalmente" — e por que isso não contradiz o achado

Faz sentido, e não é incompatível com a causa raiz encontrada. O aviso do
próprio Gemini já diz "Spikes in demand are usually temporary" — é a
SEGUNDA vez em 3 dias que esse exato sintoma aparece (RELATÓRIO
20260823_0004 documentou o mesmo 503 "high demand" durante a curadoria em
massa, que também se resolveu sozinho depois). O padrão dos dois modelos
(`gemini-flash-latest`/`gemini-flash-lite-latest`) sendo usados no **free
tier** (já confirmado no RELATÓRIO 20260824_0002 — 20 requisições/dia só
no CORE) significa que este projeto compartilha capacidade com todo mundo
no plano gratuito, sem prioridade de fila — exatamente o cenário onde
picos de demanda global do Google afetam a gente sem ter mudado nada do
nosso lado.

## O que este relatório DESCARTA como causa

- **Rotação de secrets da Supabase** (`SUPABASE_ANON_KEY`/`SERVICE_ROLE_KEY`/etc.,
  todos com `updated_at` de hoje às 12:35 UTC, achado ao investigar):
  confirmado como não relacionado — o trace do CLI local não registra
  nenhum `secrets set` nesta sessão (só o `secrets list` desta própria
  investigação), a chamada de teste autenticou normalmente com um JWT
  novo, e "favoritos" (que não usa Gemini, só Supabase direto) o fundador
  confirmou que funcionou — se a chave estivesse quebrada, favoritos
  também teria falhado.
- **Bug de lógica no fix de 20260825_0003**: o comportamento observado
  bate exatamente com o que o código deveria fazer (CORE com 1 tentativa,
  LITE com o orçamento cheio) — só que a PREMISSA de quanto tempo cada
  tentativa levaria estava errada, não a lógica em si.
- **Cache do catálogo**: não é gargalo — texto (que também lê o mesmo
  catálogo) respondeu em 3,2s normalmente.

## Recomendação (sem implementar — pedido do fundador)

1. **Confirmar se é mesmo transitório**: testar de novo em algumas horas —
   se seguir o mesmo padrão do incidente de 23/08 (curadoria em massa),
   deve se resolver sozinho.
2. **Decisão estratégica já registrada no RELATÓRIO 20260824_0002 continua
   de pé e ficou mais urgente**: enquanto `GEMINI_API_KEY` estiver no free
   tier, o produto está sujeito a essa instabilidade de terceiro sem
   nenhum código nosso poder evitar — habilitar billing tira o
   compartilhamento de capacidade do free tier.
3. Se billing não for opção agora, a mudança arquitetural que realmente
   resolveria (não é fix pontual, é redesenho) seria trocar a chamada
   síncrona bloqueante por um padrão assíncrono (enviar + notificar/
   consultar depois) — assim uma resposta lenta-mas-eventualmente-boa do
   Gemini nunca "estoura" nem o timeout do cliente nem o teto de execução
   da Supabase. Fica registrado como opção, não implementado.
