# 20260928_0003 — Fix: `health 13.3.2` quebra o build real (erro Kotlin), revertido

**Branch:** `fix/health-13.3.2-kotlin-compile-error` (a partir de `main`, pós-merge do
RELATÓRIO 20260928_0002).
**Contexto:** fundador rodou um build real (`assembleDebug`) depois do merge e reportou a
falha — a mensagem de aviso de KGP continuava aparecendo (agora só pra `health` e
`workmanager_android`, sinal de que `device_info_plus`/`file_picker` de fato pararam de
aplicar KGP direto com o bump), mas o build falhou de verdade com um erro fatal de
compilação Kotlin, não um aviso.

## Causa raiz

`:health:compileDebugKotlin` falhou com uma quantidade grande de `Unresolved reference`
apontando pra classes que deveriam existir dentro do próprio módulo Android do plugin
(`HealthConstants`, `HealthDataReader`, `HealthDataOperations`, `HealthDataConverter`,
`HealthDataChanges`) — confirmei que os arquivos `.kt` dessas classes de fato existem no
pacote baixado (`HealthConstants.kt` etc., todos presentes em
`android/src/main/kotlin/cachet/plugins/health/`), então não é um pacote incompleto.
Combinado com erros de tipo genuínos e independentes no mesmo build
(`Argument type mismatch: actual type is 'MatchGroup', but 'Int' was expected` em
`HealthDataWriter.kt:320`/`:414`/`:671`), a leitura mais provável é que `health 13.3.2`
tem um bug real de compatibilidade com a versão do compilador Kotlin deste toolchain —
`HealthConstants.kt` (ou outro arquivo "raiz" da cadeia) provavelmente falha primeiro por
um erro de tipo genuíno, e isso cascateia como "unresolved reference" pra tudo que
depende dele.

Busquei o changelog do `health` até a versão mais recente disponível (ainda `13.3.2` no
momento desta investigação) e não há nenhuma versão mais nova corrigindo isso. Busquei
também o rastreador de issues do plugin sem achar um relato equivalente já registrado.

**Isto é exatamente o tipo de risco que eu já tinha sinalizado como não verificável neste
ambiente** (RELATÓRIO 20260928_0002, seção "Risco residual"): `flutter analyze` e
`flutter test` nunca invocam o compilador Kotlin/Gradle real — só um build nativo de
verdade (`assembleDebug`, que só o fundador consegue rodar aqui) pega esse tipo de
quebra. Ele apareceu na primeira vez que isso foi testado de verdade.

## Efeito em cascata

`health >=13.3.2` era a ÚNICA faixa de versão que liberava `device_info_plus` 13.x (que
por sua vez era o que permitia `file_picker >=13.0.0` resolver, via compatibilidade de
`win32`) — ver a cadeia completa no RELATÓRIO 20260928_0002. Revertendo `health` pra
`13.3.1`, os outros 2 tiveram que voltar junto:

- `health: ^13.3.2` → `^13.3.1`.
- `device_info_plus: ^13.2.0` → `^12.4.0`.
- `file_picker: ^13.1.0` → `^11.0.2`.
- `lib/features/gamification/presentation/pages/missoes_exames_page.dart`: migração de
  API revertida (`pickFile()`/`readAsBytes()` → `pickFiles(..., withData: true)` +
  `.files.first`/`.bytes`, igual ao estado anterior ao RELATÓRIO 20260928_0002).
- `test/features/gamification/presentation/pages/missoes_exames_page_test.dart`: dublê
  `_PlatformFileFalso` removido, volta ao construtor literal `PlatformFile(name:, size:,
  bytes:)` (válido de novo na API 11.x, onde a classe não é `abstract`).
- `cross_file` removido de `dev_dependencies` (só existia pra sustentar o dublê acima).

**Não afetado, permanece como no RELATÓRIO 20260928_0002**: `flutter_secure_storage
^10.2.0`, `workmanager ^0.10.10`, e a remoção das dependências mortas
(`freezed`/`freezed_annotation`/`json_serializable`/`build_runner`/`json_annotation`) —
nenhum desses tem relação com o bug do `health`, e o mesmo `crypto_storage_penetration_test.dart`
(7 cenários) e o resto da suíte continuam cobrindo essas mudanças.

## Verificação

- `flutter pub get`: resolve limpo, `win32` volta pra `5.15.0` (compatível com as
  versões antigas de `device_info_plus`/`file_picker`).
- `flutter analyze`: **30 issues** — linha de base exata, zero novo.
- `flutter test`: **512/512 passando**, zero regressão.

## O que continua em aberto

O aviso de KGP volta a aparecer pra `device_info_plus`/`file_picker` (como estava depois
do RELATÓRIO 20260928_0001), além de `health`/`workmanager_android` (esses dois nunca
saíram do aviso — só o bug de compilação do `health` que forçou este revert). Sem uma
versão do `health` que resolva a quebra de Kotlin, não há como reter o avanço deste
pacote — reavaliar quando uma versão mais nova for lançada.

**Lição pra próxima vez**: bumps que só passam por `flutter analyze`/`flutter test`
(verificação Dart-only) não são prova suficiente de segurança pra plugins com código
nativo Android/iOS — só um build real (`assembleDebug`/`build ios`) pega esse tipo de
quebra, e este ambiente não tem essa capacidade. Fica registrado como limitação
conhecida do processo de verificação usado nesta sessão.

Branch `fix/health-13.3.2-kotlin-compile-error`, a partir de `main`, aguardando
autorização explícita do fundador para merge.
