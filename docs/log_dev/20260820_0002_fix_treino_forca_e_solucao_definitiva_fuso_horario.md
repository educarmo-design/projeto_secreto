# 20260820_0002_fix_treino_forca_e_solucao_definitiva_fuso_horario — Treino de força corrigido + solução definitiva pro bug de fuso horário (histórico de fuso próprio do app)

Log de Máquina (Regra 10.3 — append-only). Modo autônomo, sem device
(fundador viajou pra Lima em 17/08 e está usando o celular). Continuação
direta dos RELATÓRIOS 20260819_0020/0021/20260820_0001: fundador reportou
resultado de teste real comparando "sistema" vs. app do Garmin dia a dia.

## 1. Treino de força — corrigido

Fundador reportou: corrida e Pilates aparecem certos; treino de força
(13/08, 04/08, 30/07, "em resumo todos") nunca aparece na tela nem grava.

Causa raiz: `tipos_atividades_fisicas`
(`20260811160000_atividades_fisicas_calorias_granulares.sql`) foi semeado
só com os tipos da seção **"Both"** do enum `HealthWorkoutActivityType`
do pacote `health` (comuns a Android E iOS). Treino de força **nunca foi
"Both"**: confirmado lendo o enum completo
(`lib/src/heath_data_types.dart`) — `STRENGTH_TRAINING`/`WEIGHTLIFTING`
são **Android-only**, `FUNCTIONAL_STRENGTH_TRAINING`/
`TRADITIONAL_STRENGTH_TRAINING` são **iOS-only**. Ficou de fora dos dois
lados por construção. A FK
`atividades_fisicas_treinos.tipo_atividade_codigo references
tipos_atividades_fisicas(nome_codigo)` rejeita qualquer código ausente —
o `catch` best-effort do loop de `_processarTreinos` engole a
`PostgrestException` e segue pros próximos treinos, sem rastro visível.

Corrigido: migration `20260820100000_tipos_atividades_treino_forca.sql`
adiciona os 4 códigos (decisão do fundador: os 4, não só os 2 do Android
— cobre iOS também de uma vez). **Aplicada no banco remoto**, confirmada
via consulta.

## 2. Distância/calorias erradas em 13-17/08 — investigação com correção de rumo pública

### 2.1 Primeira hipótese (incompleta, corrigida pelo fundador em tempo real)

Achado inicial: os 5 dias com problema (13-17/08) formam uma janela
contígua. Hipótese inicial errada: "a semana toda foi afetada pela
viagem". O fundador corrigiu corretamente: ele viajou só no dia 17/08 —
dias ANTES da viagem não podem ser afetados por uma viagem que ainda não
aconteceu.

### 2.2 Causa raiz real (evidência direta, não suposição)

Revisitando os próprios logs desta conversa: `adb shell date` capturado
às 17:53 do dia 19/08 devolveu `-05` (fuso de Lima), não `-03`
(Brasília). Nesse EXATO horário rodou uma recarga completa de 30 dias
("FORÇAR CARGA 30 DIAS", RELATÓRIO 20260819_0020) que relê e regrava a
janela inteira de uma vez — não incremental. Essa janela cobre 20/07 a
19/08, **incluindo 13-16/08** (gravados originalmente em Brasília, bem
antes da viagem). Mecanismo: `DateTime.fromMillisecondsSinceEpoch`
(usado pelo pacote `health` para `dateFrom`/`dateTo`) reinterpreta
qualquer instante histórico pelo fuso ATUAL do aparelho no momento da
CONVERSÃO — não da gravação. Aquela recarga específica, rodada sob o
relógio em Lima, reprocessou o histórico inteiro sob o fuso errado —
não foi a viagem que corrompeu os dias 13-16, foi aquela sincronização
específica ter rodado com o relógio ainda errado.

Fundador pediu certeza, não suposição — reconhecido explicitamente que
a segunda versão também era só evidência forte, não prova completa
(sem acesso a device pra reconfirmar com dado fresco).

### 2.3 20/08 (calorias 2312 vs. 2428 no app do Garmin)

Não é bug: 20/08 é HOJE (data corrente desta sessão). O app do Garmin
mostra o total ATUALIZANDO ao vivo; nosso sync é uma fotografia de um
momento específico do dia — mesmo fenômeno já documentado no RELATÓRIO
20260819_0021 pra passos (15/08, 16/08 vs. app do Garmin). Reforçado por
19/08 e 18/08 (dias já fechados) baterem exatamente com o Garmin
(2946=2946, 2380=2380) — nenhuma discrepância quando o dia não está mais
em andamento.

## 3. Solução DEFINITIVA implementada (decisão do fundador: "é um produto, qualquer usuário que viajar vai viver isso, precisa de solução no código")

Não corrige retroativamente 13-17/08 (impossível sem o fuso original por
ponto, que o Health Connect não expõe pro pacote `health` — confirmado
lendo `HealthDataConverter.kt`), mas **elimina a classe inteira do bug
dali pra frente, permanentemente, pra qualquer usuário**.

### Mecanismo

O app passa a manter seu **próprio histórico de transições de fuso**
(`perfis_usuarios`... não — fica em secure storage local, por
dispositivo, chave `AppConfig.storageKeyTimezoneHistory`: JSON, lista de
`{"t": epochMs, "o": offsetMinutos}`, uma entrada por TROCA real de
fuso, não uma por sincronização).

- `HealthSyncService._registrarFusoAtualSeMudou`: roda no início de toda
  sincronização (`_lerEGravar`). Só grava uma entrada nova quando o fuso
  atual difere da última registrada (lista de transições, não um log
  de toda chamada). Best-effort, nunca derruba o sync principal.
- `HealthSyncService._offsetParaInstante(instanteMs, historico)`: função
  pura — acha a última transição registrada ANTES ou NO instante
  pedido. Sem transição anterior (dado mais antigo que todo o histórico
  rastreado — ex.: a primeiríssima Carga de 30 dias de um usuário novo),
  cai pro fuso ATUAL como melhor estimativa disponível — mesmo
  comportamento de antes desta tarefa, não regressão; só deixa de ser o
  ÚNICO comportamento.
- `_dataOnly`/`_dataDoSonoLocal` agora recebem o offset explícito, em
  vez de confiar na conversão "local" automática do Dart (que sempre
  usa o fuso de AGORA). `.toUtc()` preserva o instante absoluto exato
  (Dart guarda isso internamente independente da flag local/UTC — só
  muda como ano/mês/dia são exibidos); somar o offset manualmente e ler
  os componentes do resultado reproduz o que um relógio de parede
  naquele fuso mostraria, sem depender do fuso do sistema operacional
  em nenhum momento.
- `_mesclarPorDia`/`_preencherDistanciaFaltante` resolvem o offset POR
  PONTO (`payload.dateFrom`), não um offset só pra sincronização
  inteira — um lote de 30 dias que atravessa uma troca de fuso no meio
  bucketiza cada ponto corretamente, mesmo dentro do mesmo lote.
- Diagnóstico (`_logRaioX`/`_logDiagnosticoProfundo`, RELATÓRIO
  20260813_0015/0016) mantido com o fuso ATUAL de propósito — é só
  debugPrint pra leitura humana, nunca grava no banco; documentado
  explicitamente como exceção consciente, não esquecimento.

### O que isso resolve e o que não resolve

- **Resolve pra sempre**: qualquer sincronização a partir de agora,
  mesmo atravessando trocas de fuso no meio do lote — a bucketização
  usa o fuso REAL de cada ponto, não o fuso de quando o app rodou a
  conversão.
- **Não resolve retroativamente**: dado já sincronizado ANTES desta
  tarefa existir (não tínhamos histórico de fuso de antes de hoje) —
  mesmo caso do 13-17/08 do fundador, já removido do banco (ver seção
  4).

## 4. Dados removidos do banco (`atleta1000@teste.com`)

`metricas_saude_diarias`, 5 linhas apagadas (service role, escopadas só
a este usuário de teste): 2026-08-13, 08-14, 08-15, 08-16, 08-17.
Confirmados os valores exatos batendo com o relato do fundador antes de
apagar (13214/2913,58; 14696,31/4310,34; 3154/2142; 1949,3/751,67;
11845,7/3312,33 — passos/distância/calorias). Ficam em branco até uma
recarga futura rodar já com o histórico de fuso ativo — o fundador está
atualmente em Lima, então uma recarga AGORA reprocessaria esses dias
(gravados em Brasília) sob o fuso de Lima de novo; melhor deixar em
branco (honesto) do que reescrever errado de novo. Recarga desses dias
específicos só faz sentido quando o aparelho voltar a um fuso
equivalente ao de quando foram gravados.

## Verificação

- `flutter analyze`: limpo (0 erros/warnings novos).
- `flutter test test/features/dashboard/data/services/health_sync_service_test.dart`:
  105 testes passando (98 + 2 do treino de força + 5 do histórico de
  fuso: bucketiza pelo fuso histórico não o do sistema de testes, mesmo
  instante com offset diferente cai em dia calendário diferente, sem
  histórico não quebra, histórico passa a existir após 1ª sincronização,
  offset repetido não grava transição duplicada).
- `flutter test` (suíte inteira): 348 testes passando, mesmas 11 falhas
  pré-existentes e não relacionadas de `confirmacao_prato_page_test.dart`
  (já registradas nos relatórios anteriores) — nenhuma falha nova.
- Migration `20260820100000_tipos_atividades_treino_forca.sql`: aplicada
  e confirmada via consulta direta (os 4 códigos existem na tabela).

## Não resolvido / próximo passo

Nada verificado em device físico ainda (fundador em viagem). Pendente,
pra quando o aparelho estiver disponível: confirmar que treino de força
aparece na tela depois de um novo sync; confirmar que dias sincronizados
DAQUI PRA FRENTE (mesmo atravessando a volta de Lima pra Brasília) saem
corretos — esse é o teste real da solução definitiva desta tarefa.
