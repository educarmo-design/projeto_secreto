# 20260813_0014_fix_regression_telemetria — Auditoria de regressão: peso/gordura

Log de Máquina (Regra 10.3 — append-only). Investigação do sintoma
reportado: "após a correção do IMC (20260812_0011_fix_imc), a
sincronização de peso e percentual de gordura da balança smart parou de
funcionar".

## Veredicto: não houve regressão de código causada pela correção do IMC

Conferido o diff completo dos 2 commits da correção de IMC
(`7ee0c0d`/`5326686`) contra `main` — os únicos arquivos de produção
tocados foram `perfil_usuario_repository.dart` (troca de `.update()` por
`.upsert()` em `perfis_usuarios`) e `perfil_usuario_page.dart` (IMC ao
vivo). **`health_sync_service.dart` — o único arquivo que lê do wearable e
escreve `peso_kg`/`percentual_gordura`/`massa_magra_kg` em
`metricas_saude_diarias` — não foi tocado em nenhuma linha** por essa
correção. `PerfilUsuarioRepository.buscarUltimoPesoKg()` (novo método
daquela tarefa) só faz `SELECT` — não escreve nada, não pode ter quebrado
uma escrita.

## Auditoria de código (ponto a ponto, per TAREFA)

- **`HealthDataType.WEIGHT`/`BODY_FAT_PERCENTAGE` ainda pedidos?** Sim —
  confirmado em `todosOsTipos` (linhas 329/332), inalterados.
- **Exceção silenciosa engolindo o `.upsert()` de `metricas_saude_diarias`?**
  Não — `_enviarLinhas` já captura `PostgrestException` e loga com
  `debugPrint` antes de devolver `DeltaSyncOutcome.erro`; nenhuma mudança
  necessária ali.
- **Trigger do sync rodando?** Sim — `MainNavigationPage.initState` ainda
  dispara `SyncUiController.forcarSincronizacaoAtleta()` sem alteração;
  `background_sync_manager.dart` (job noturno via WorkManager) também
  intacto.
- **Filtro de fuso cortando "hoje"?** Não — a janela usa
  `DateTime(inicioBruto.year, ...)` alinhada à meia-noite LOCAL (correção
  de uma tarefa anterior, RELATÓRIO 20260811), sem relação com a tarefa do
  IMC e sem mudança nesta auditoria.

## Achado real (pré-existente, não causado pela tarefa do IMC, mas corrigido agora)

`_lerComPermissao` — o método central de leitura, usado por TODO sync
(delta diário e carga inicial) — tinha um `catch (_) { return
HealthSyncResult.denied(...); }` que engolia **qualquer** exceção (rede,
parsing de um `HealthDataPoint` malformado, erro de plugin nativo) sem
nenhum log, nem sequer o `debugPrint` que o resto do arquivo usa
consistentemente em todo catch best-effort. Quando isso dispara, o
chamador (`_lerEGravar`) trata como "permissão negada" e aborta o lote
inteiro — nenhuma coluna é gravada naquele ciclo, sem nenhum rastro no
console pra investigar a causa real. **Corrigido**: o `catch` agora
recebe `(e, stackTrace)` e loga com `debugPrint` antes de devolver o mesmo
resultado de antes (comportamento best-effort preservado, só ganhou
observabilidade).

## Por que a auditoria de banco não mostra evidência de regressão

Consulta real em `metricas_saude_diarias` para `atleta1000@teste.com`
(últimos 20 dias): a última pesagem registrada é **2026-08-10**
(peso 80,60kg, percentual 15,50%, massa magra 68,11kg, IMC 25,2 — os 3
campos consistentes entre si, confirmando que `_aplicarInferenciasCruzadas`
segue derivando massa magra ↔ percentual de gordura normalmente). Pesagens
anteriores (07-29, 07-28, 08-01) mostram o mesmo padrão saudável:
esparsas, algumas vezes por semana — o comportamento ESPERADO de uma
balança smart (só gera um ponto quando alguém sobe nela), documentado no
próprio código (`lerPesoRecente`: "a balança Fitdays só produz um ponto
por pesagem, tipicamente alguns por semana, nunca contínuo"). **`passos`
está presente normalmente em TODOS os dias sem pesagem** (10.828 em
08-13, 14.029 em 08-12, 3.734 em 08-11) — se `_lerComPermissao` estivesse
lançando exceção nesses dias, o lote inteiro (passos incluído) teria
ficado de fora, o que não é o caso. Isso descarta o achado acima como
causa raiz do sintoma relatado.

**Conclusão**: não há dado "sumindo" — o usuário de teste simplesmente não
pesou de novo desde 2026-08-10. Não é uma regressão de sincronização.

## Verificação

- `flutter analyze lib/features/dashboard`: 5 issues, baseline mantida.
- `flutter test test/features/dashboard/data/services/health_sync_service_test.dart`:
  74 testes passando (73 pré-existentes + 1 novo, cobrindo o `catch`
  corrigido: uma exceção simulada na leitura ainda vira `permissaoNegada`
  — comportamento preservado — e agora aparece no log capturado).
- `flutter test test/features/dashboard/`: 148 testes passando, sem
  regressão em nenhuma tela/serviço.
- `flutter build apk --debug`: build completo, `.apk` verificado em disco.

## Não resolvido (fora do alcance de código)

Se o fundador pesou de fato depois de 2026-08-10 e o app não sincronizou,
a próxima etapa é reproduzir com o app aberto no aparelho físico e olhar o
log agora visível de `_lerComPermissao` (antes invisível) — o achado desta
tarefa deixa essa investigação possível pela primeira vez, mas não havia
como reproduzir a falha sem um device real neste ambiente.
