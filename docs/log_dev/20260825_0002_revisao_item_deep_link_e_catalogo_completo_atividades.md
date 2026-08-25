# RELATÓRIO 20260825_0002 — Botão "Revisar item" na fila + catálogo completo de atividades físicas

**Data:** 2026-08-25
**Modo:** autônomo, enquanto o fundador fazia teste físico dos 4 métodos de registro de refeição (RELATÓRIO 20260824_0003).

## 1) Botão "Revisar item" na fila de revisão do catálogo

**Pedido:** os 2 cards de `AdminOverview` ("Alimentos em revisão"/"Medidas
caseiras em revisão") já abriam a fila (`AdminRevisaoCatalogo.tsx`), mas
faltava um botão em cada item da lista pra ir pra uma "tela de revisão do
item" — e, pra medida caseira, essa tela precisa mostrar o alimento dono
junto (nunca revisar a medida isolada do alimento).

**Decisão de design:** não duplicar UI — `AdminAlimentos.tsx` (RELATÓRIO
20260823_0004) já É a tela de revisão do item completa: mostra o alimento
(com observação, se `revisao_necessaria`) e as medidas caseiras dele logo
abaixo, exatamente o par "medida caseira com alimento" pedido. A fila só
precisava de um jeito de apontar pra lá, deep-linkado no item certo.

- `AdminAlimentos.tsx`: passa a ler `?id=` (via `useSearchParams`) e
  seleciona esse alimento direto ao carregar — sem depender dele estar
  entre os 50 primeiros da busca alfabética padrão. `&medida=` (só quando
  o item da fila é uma medida caseira) é repassado pro
  `MedidasCaseirasPanel`, que abre essa medida já em modo edição assim que
  a lista carrega — a observação aparece sem precisar clicar "Editar" de
  novo.
- `AdminRevisaoCatalogo.tsx`: cada `FilaItem` ganhou um link "Revisar item
  →" — pra alimento, `/admin/alimentos?id=<id>`; pra medida,
  `/admin/alimentos?id=<alimentoId>&medida=<medidaId>`. O toggle
  marcar/desmarcar rápido que já existia na fila continua funcionando do
  jeito que estava — as duas formas de resolver convivem.

`tsc -b` limpo.

## 2) Investigação completa + catálogo de atividades físicas

**Pedido:** o fix do treino de força (RELATÓRIO 20260820_0002 — código
nativo do wearable ausente do dicionário `tipos_atividades_fisicas`
rejeita a FK, `catch` best-effort engole o erro sem rastro) foi só uma
correção pontual (4 códigos). Pedido: investigar TODAS as atividades que
podem sofrer o mesmo bug e corrigir, sem nada hardcoded — configurável via
banco mesmo que precise de migration.

**Investigação:** enumerado programaticamente (não por leitura visual —
risco real de erro de contagem, como aconteceu comigo na primeira
tentativa desta própria tarefa) o `HealthWorkoutActivityType` completo do
pacote `health` 13.3.1 (`lib/src/heath_data_types.dart`, instalado em
`~/.pub-cache`): **99 códigos no total** — 43 "Both" (comuns Android+iOS,
inclui `BIKING`), 35 "iOS only", 20 "Android only", + `OTHER` (catch-all
fora de seção). Cruzando com o catálogo real do banco (consulta direta,
service role): só **47 cadastrados** (as 43 "Both" + os 4 de força da
correção anterior) — **52 códigos plataforma-específicos ausentes**, cada
um capaz de reproduzir o mesmo bug silencioso assim que o usuário certo
registrasse aquele treino específico no wearable certo.

**Por que a correção é uma migration, não código:** `tipos_atividades_
fisicas.nome_codigo` espelha `HealthWorkoutActivityType.name` 1:1 por
desenho desde a criação da tabela (`20260811160000`, comentário original:
"sem camada de tradução no meio") — o dicionário É a allowlist da FK.
"Não pode ser hardcode" nesta arquitetura significa cadastrar os códigos
que faltam no banco (editável em runtime pelo Admin), não escrever um
`switch`/mapa de tradução no Dart.

**Migration `20260825100000`:**
- Cadastra os 52 códigos faltantes (33 iOS-only + 18 Android-only +
  `OTHER`), com `nome_exibicao` em português.
- Achado documentado (sem ação de código): o pacote já resolve sozinho o
  par BIKING(Android)/"cycling"(iOS) — emite o mesmo código `BIKING` nas
  duas plataformas, não existe uma entrada `CYCLING` separada. Já
  `ROCK_CLIMBING`(Android)/`CLIMBING`(iOS) e `RUNNING_TREADMILL`(Android)/
  `RUNNING`(iOS, já cadastrado) SÃO códigos distintos de verdade — cada um
  ganhou a própria linha (a FK é por código exato), com o MESMO
  `nome_exibicao` entre os pares comentados no enum como "a mesma coisa"
  (ex.: `ROCK_CLIMBING`/`CLIMBING` = "Escalada"), só pra ficar visível no
  Admin que são a mesma atividade do ponto de vista do usuário.
- Coluna nova `plataforma` (`'ambas' | 'android' | 'ios'`, default
  `'ambas'`) — só documentação (a FK continua usando `nome_codigo`), mas
  garante que uma auditoria futura ("que códigos daquela plataforma
  faltam?") nunca mais dependa de conferir o enum inteiro na mão de novo,
  caso o pacote `health` ganhe mais tipos. Backfill correto nas 47 linhas
  pré-existentes.

**Verificação de integridade** (script ad-hoc, não faz parte do repo):
comparação programática do enum completo (99 códigos, extraídos
linha-a-linha do arquivo real do pacote) contra a união de tudo que as 3
migrations semeiam (`20260811160000` + `20260820100000` +
`20260825100000`) — **zero código faltando, zero típo/código inventado,
zero duplicata**. Migration aplicada no banco remoto (`supabase db push`)
e reconferida com uma consulta direta: **99 linhas, 99 códigos únicos**,
44 `ambas` / 35 `ios` / 20 `android` — bate exatamente.

`AdminAtividadesFisicas.tsx` ganhou a coluna "Plataforma" (badge,
somente-leitura) pra essa metadata ficar visível na mesma tela onde o
dicionário já é gerenciado. `database.ts` atualizado. `tsc -b` limpo.

## Verificação

`tsc -b` e `npm run lint` limpos no painel (os 2 warnings pré-existentes
de `scripts/seed_taco_completa.ts` não têm relação com esta tarefa —
nenhum arquivo deste relatório toca aquele script). Nenhum arquivo Dart
tocado — Flutter inalterado.

Nada verificado em device físico ainda para o botão "Revisar item" (o
fundador estava testando os 4 métodos de refeição, não o painel, durante
esta tarefa) — recomendado conferir visualmente no próximo acesso ao
painel.
