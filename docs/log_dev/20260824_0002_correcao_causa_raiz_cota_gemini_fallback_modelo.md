# 20260824_0002_correcao_causa_raiz_cota_gemini_fallback_modelo — Correção da correção: causa raiz real era cota diária do Gemini, não instabilidade transitória

Log de Máquina (Regra 10.3 — append-only). O fundador testou de novo
depois do RELATÓRIO 20260824_0001 e reportou: a 1ª foto do dia
funcionou, as seguintes falharam, e o tempo até falhar ficou **maior**
(não menor) — e foi explícito: "o problema não está no Gemini, está
na implementação". Estava certo. Esta tarefa é a correção da correção
anterior, que diagnosticou errado.

## Onde o RELATÓRIO 20260824_0001 errou

Vi um HTTP 503 "high demand" (instabilidade transitória real) durante
a curadoria em massa do catálogo na véspera e generalizei — assumi que
"Falha ao analisar a imagem" em produção seria o mesmo tipo de erro, e
corrigi com retry/backoff (2 tentativas extras, 1.5s/3s). Isso foi um
diagnóstico por analogia, não por evidência direta do erro de
produção — erro de metodologia que o padrão "1ª deu certo, resto não,
e demora mais" deveria ter me feito desconfiar antes.

## Investigação desta tarefa — evidência direta, não suposição

Chamei o Gemini de verdade com a chave do projeto (`GEMINI_API_KEY`),
repetidamente, pro modelo CORE (`gemini-flash-latest`):

```
HTTP 429 RESOURCE_EXHAUSTED
"Quota exceeded for metric: generativelanguage.googleapis.com/
generate_content_free_tier_requests, limit: 20, model: gemini-3.7-flash"
quotaId: "GenerateRequestsPerDayPerProjectPerModel-FreeTier"
```

**Causa raiz real**: a chave do projeto está no **free tier**, e o
alias `gemini-flash-latest` (usado pra `pratoRefeicao`/`rotulo`, nível
CORE) hoje resolve pro `gemini-3.7-flash` — um modelo bem mais novo do
que quando o alias foi escolhido, com uma cota gratuita de **20
requisições POR DIA**, já esgotada. Não é "alta demanda passageira do
Gemini" — é um teto diário fixo, batido pelo uso normal (curadoria de
ontem + testes + fotos reais).

Testei o modelo LITE (`gemini-flash-lite-latest`) com a mesma chave:
**HTTP 200 OK**, funcionando normalmente — é o mesmo modelo que a
curadoria em massa usou ontem (por isso funcionou sem problema).
`gemini-pro-latest`: `limit: 0` (zero requisições grátis, nível HEAVY
nunca é opção no free tier).

Isso explica os 3 sintomas relatados, com precisão:
- **"1ª deu certo, resto não"** — cota diária de 20 esgotando ao longo
  do uso normal do dia.
- **"tempo de tentativa maior"** — meu retry de ontem (1.5s + 3s de
  espera) rodava e MESMO ASSIM falhava, porque uma cota diária não se
  resolve esperando alguns segundos — só fazia o usuário esperar mais
  pra ver a mesma falha.
- **"não é do Gemini, é da implementação"** — o fundador estava certo:
  Gemini está se comportando exatamente como documentado (limitando o
  free tier); o problema real é a app usar um modelo CORE cuja cota
  gratuita é minúscula demais pro uso real, sem nenhum plano B.

## Correção real (não uma 3ª tentativa de retry)

`supabase/functions/extract-metric-photo/index.ts`:

1. **429 nunca é retentado no mesmo modelo.** Novo `ErroCotaGemini`
   (subclasse de `ErroHttp`, status 429) — lançado IMEDIATAMENTE, sem
   passar pelo laço de retry. Só 5xx (instabilidade transitória de
   verdade, como o 503 de ontem) continua retentando com backoff curto
   (`MAX_TENTATIVAS_VISAO = 3`, mantido do RELATÓRIO 20260824_0001 —
   esse pedaço da correção anterior estava certo, só não bastava
   sozinho).
2. **Fallback automático de modelo** — `criarChamadorGeminiComFallback
   (apiKey, modeloPrimario, modeloFallback)`: quando o modelo primário
   esgota cota (`ErroCotaGemini`), cai automaticamente pro fallback em
   vez de falhar pro usuário. Tipos no nível CORE (`pratoRefeicao`,
   `rotulo`) agora degradam pro nível LITE quando o CORE esgota;
   tipos já no nível LITE não têm pra onde degradar (`null`, mesmo
   comportamento de antes — já são o mais barato).
3. **Mensagem honesta pro usuário** (Regra 0.15) — 429 que chega até o
   handler (fallback TAMBÉM esgotado) agora mostra "Limite diário de
   análises por IA atingido. Tente novamente amanhã, ou digite a
   refeição manualmente." em vez do genérico "Falha ao analisar a
   imagem" com convite implícito a tentar de novo na hora (enganoso
   pra uma cota diária).
4. `ErroHttp` exportada (só pros testes conferirem `.status`
   diretamente).

## Achado estratégico — não é um bug que código resolve sozinho

O fundador pediu avaliação completa como "profissional sênior": o
fallback automático (CORE→LITE) é mitigação real e válida, mas **não
elimina o teto** — é um free tier com 20 requisições/dia pro modelo
CORE, e o LITE (agora usado tanto pelas capturas OCR simples quanto
como fallback do prato/rótulo, MAIS a curadoria/testes administrativos
que também consomem a mesma chave) tem uma cota folgada mas **não
infinita**. Qualquer app com uso real de fotografia de refeições vai
eventualmente bater no teto do LITE também, só que mais tarde.

**Não dá pra resolver isso só com engenharia de retry/fallback.** A
decisão real, que só o fundador pode tomar, é **habilitar billing
(tier pago) no projeto Google AI/Gemini** usado por
`GEMINI_API_KEY` — sem isso, o produto está estruturalmente limitado a
um teto diário de análises de IA, não importa quanto o código
degrade graciosamente.

## Sobre "além da população da tabela" (mencionado pelo fundador)

Confirmado que a leitura do catálogo (cache do RELATÓRIO 20260824_0001)
é INDEPENDENTE da chamada de visão do Gemini — o catálogo nunca é
enviado pro Gemini (a IA só recebe a foto + um prompt fixo; o
casamento contra `alimentos_referencia` acontece depois, só no
backend). A população da tabela não afeta a latência da chamada de
visão em si. O cache em memória da leitura do catálogo continua válido
como otimização, com uma ressalva honesta: numa função serverless de
baixo tráfego, a instância pode não ficar "quente" entre uma foto e
outra, então o cache nem sempre acerta — não é garantia, é
"melhor-esforço quando a instância está quente". Uma otimização mais
robusta (buscar só id/nome/aliases pra casar, e só depois os macros/
medidas do que efetivamente casou, em vez do catálogo inteiro sempre)
resolveria isso de vez, mas é uma mudança de arquitetura maior no
caminho de cálculo determinístico de calorias — não fiz agora
(disciplina de escopo: o bug relatado já tem causa raiz confirmada e
resolvida; essa otimização fica registrada como próximo passo, não
como parte desta correção).

## Verificação

- `deno check`: limpo.
- `deno test`: **85/88 passando** (+3 líquido: 1 teste antigo
  desatualizado sobre retry-em-429 corrigido, 3 testes novos de
  `criarChamadorGeminiComFallback`) — mesmas 4 falhas pré-existentes
  não relacionadas (`encontrarMedida`/fallback de medida, já
  documentadas desde o RELATÓRIO 20260823_0004).
- `flutter analyze`: limpo (nenhum arquivo Dart tocado nesta tarefa,
  suíte Flutter inalterada — 407/407 continua valendo).
- Deploy: `supabase functions deploy extract-metric-photo` — fallback
  em produção.

## Não resolvido / próximo passo

- **Decisão do fundador, não técnica**: habilitar billing no projeto
  Gemini/Google AI Studio usado por `GEMINI_API_KEY`. Sem isso, mesmo
  com o fallback, o app tem um teto diário de operações de IA (câmera
  de refeição, glicosímetro, balança, pressão, rótulo, busca
  semântica, curadoria administrativa — todos compartilham a MESMA
  chave/projeto hoje).
- Considerar separar a chave usada por scripts administrativos
  (curadoria em massa, testes manuais) da chave usada em produção —
  hoje as duas competem pela mesma cota, o que piora o problema pro
  usuário final sem ele ter feito nada de errado.
- Otimização de 2 fases no fetch do catálogo (id/nome/aliases pra
  casar; macros/medidas só do que casou) — registrada acima, não
  implementada nesta tarefa.
