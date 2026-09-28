# 20260928_0002 — Aviso de KGP resolvido nos 4 pacotes + dependências mortas removidas

**Branch:** `chore/upgrade-kgp-plugins` (continuação do RELATÓRIO 20260928_0001).
**Contexto:** o fundador autorizou investigar o bump de `flutter_secure_storage` pra
10.2.0+, o bloqueador transitivo (`win32`) que tinha deixado `health`/`device_info_plus`/
`file_picker` de fora da rodada anterior. A investigação achou um segundo bloqueio, mais
fundo, e a resolução dele — não um upgrade de `freezed`, e sim a remoção de dependências
mortas — acabou destravando os 4 pacotes de uma vez.

## `flutter_secure_storage` 10.2.0 — testado isoladamente primeiro

Antes de mexer nos outros 3, subi só esse pra confirmar segurança:

- **Resolve limpo** (`flutter pub get`, "Changed 7 dependencies!", sem conflito).
- **Achado que reduz o risco original**: o projeto não tem pasta `windows/` (só
  `android`/`ios` existem) — a mudança de backend de storage no Windows (do sistema de
  credenciais pra arquivos criptografados) documentada no changelog da 10.0.0 nunca vai
  rodar de verdade neste app; era uma preocupação real só no papel.
- Único ajuste de código necessário: `AndroidOptions(encryptedSharedPreferences: true)`
  foi removido (parâmetro deprecado desde a reescrita da cifra em 10.0.0) —
  `lib/core/security/crypto_storage_service.dart` passou a usar `AndroidOptions()`
  (padrão), que já ativa a nova implementação de cifra própria do plugin com migração
  automática dos dados gravados na cifra antiga (`migrateOnAlgorithmChange: true`, ligado
  por padrão — documentado no código).
- `IOSOptions`/`MacOsOptions` foram unificados em `AppleOptions` na interface da
  plataforma — `test/support/fake_secure_storage.dart` (dublê usado por vários testes,
  não só o de segurança) precisou do mesmo ajuste de assinatura pra continuar um
  `@override` válido.
- **Verificação real, não só compilação**: a suíte dedicada
  `test/core/security/crypto_storage_penetration_test.dart` — que existe especificamente
  pra provar que o token de sessão biométrico nunca vaza, nunca cai num fallback
  inseguro e nunca fica em cache — passou os 7 cenários (dump de armazenamento, recusa
  do Keystore, bypass de biometria por recusa/exceção, controle positivo, limpeza no
  logout, ausência de cache em memória).

## Segundo bloqueio encontrado: `freezed` vs. `health`, via `json_annotation`

Com `flutter_secure_storage` resolvido, tentar subir os 4 pacotes juntos (`health
^13.3.2`, `device_info_plus ^13.2.0`, `file_picker ^13.1.0`, `workmanager ^0.10.10`) deu
um erro novo, sem relação com `win32`:

```
health >=13.3.2 depende de json_annotation ^4.12.0
freezed ^2.4.0 (via json_serializable/build) exige json_annotation <4.10.0
```

Ou seja: `health >=13.3.2` (a única faixa que libera `device_info_plus` 13.x) é
incompatível com `freezed ^2.4.0`. Bumpar `freezed` pra major 3.x resolveria — mas é uma
mudança bem maior e mais arriscada (sintaxe de classe muda, geraria a necessidade de
regerar qualquer `.freezed.dart` do projeto), então investiguei antes se `freezed` é
sequer usado.

**Achado**: busca em todo o repositório (`lib/` e `test/`) por `@freezed`,
`freezed_annotation`, `@JsonSerializable`, `import 'package:json_annotation`, `part
'*.g.dart'` e arquivos `.freezed.dart`/`.g.dart` — **zero resultado em qualquer um**.
`freezed`, `freezed_annotation`, `json_serializable`, `build_runner` (o gerador que os
rodaria) e até o `json_annotation` declarado direto no `dependencies` nunca tiveram uso
real neste código — são dependências mortas, provavelmente sobra do template inicial do
projeto.

**Decisão**: em vez de subir `freezed` pra 3.x (risco/esforço só pra manter algo que
ninguém usa), removi as 5 dependências mortas (`freezed`, `freezed_annotation`,
`json_serializable`, `build_runner`, `json_annotation`) do `pubspec.yaml`. Isso elimina a
restrição `build ^2.3.1` que colidia com `health`, e resolve os 4 pacotes de uma vez —
com MENOS risco do que uma migração de major version de algo não usado.

## O que foi entregue nesta rodada

- `flutter_secure_storage: ^9.0.0` → `^10.2.0`.
- `health: ^13.3.1` → `^13.3.2`.
- `device_info_plus: ^12.4.0` → `^13.2.0`.
- `file_picker: ^11.0.2` → `^13.1.0`.
- `freezed`/`freezed_annotation`/`json_serializable`/`build_runner`/`json_annotation`
  removidos (dependências mortas, zero uso real confirmado).
- `lib/core/security/crypto_storage_service.dart`: `AndroidOptions(encryptedSharedPreferences: true)`
  → `AndroidOptions()` (ver acima).
- `test/support/fake_secure_storage.dart`: `IOSOptions`/`MacOsOptions` → `AppleOptions`
  na assinatura dos overrides.
- `lib/features/gamification/presentation/pages/missoes_exames_page.dart` (único ponto
  de uso real do `file_picker`): `FilePicker.pickFiles(..., withData: true)` +
  `.files.first` → `FilePicker.pickFile(...)` (novo método de conveniência pra seleção
  única, já era o encaixe natural pro caso de uso deste arquivo — 1 PDF por vez);
  `arquivo?.bytes` → `await arquivo?.readAsBytes()` (API antiga removida em 13.0.0).
  Comentário de doc do "Zero Storage Pipeline" ajustado pra não citar o parâmetro
  removido.
- `test/features/gamification/presentation/pages/missoes_exames_page_test.dart`:
  `PlatformFile` virou `abstract base class` (backed por `XFile` do pacote `cross_file`)
  em `file_picker` 13.x — não dá mais pra construir um literal com `PlatformFile(name:,
  size:, bytes:)`. Novo dublê `_PlatformFileFalso extends PlatformFile` (precisa ser
  `base class` também, por causa da propagação do modificador `base` do Dart 3 pra fora
  da biblioteca de origem) implementando os 7 membros abstratos reais
  (`name`/`uri`/`xFile`/`lengthSync`/`length`/`readAsBytes`/`readAsByteStream`).
  `cross_file` (já resolvido transitivamente) declarado explícito em
  `dev_dependencies` por exigência do lint `depend_on_referenced_packages`.

## Verificação

- `flutter pub get`: resolve limpo em todas as etapas (testado isoladamente com só
  `flutter_secure_storage`, depois com os 4 juntos, depois com as dependências mortas
  removidas).
- `flutter analyze`: **30 issues** — linha de base exata de antes de toda a investigação
  (todos `info`, zero `error`/`warning` novo). Verificado em múltiplas rodadas
  intermediárias com erros reais capturados e corrigidos (3 erros de compilação no teste
  do `file_picker`, corrigidos com o dublê `_PlatformFileFalso`; 1 lint de dependência
  não declarada, corrigido declarando `cross_file`).
- `flutter test`: **512/512 passando**, incluindo os 7 cenários da suíte de pentest de
  `CryptoStorageService` — sem regressão em nenhum dos dois eixos (segurança do token de
  sessão e upload de exame em PDF).

## Risco residual, não verificável neste ambiente

Este ambiente não tem build-and-run nativo real em Android/iOS. A migração automática de
cifra do `flutter_secure_storage` 10.0.0 (dados gravados na cifra antiga migrados pra
`RSA_ECB_OAEPwithSHA_256andMGF1Padding`/`AES_GCM_NoPadding` na primeira leitura após o
update) é um comportamento documentado pelo próprio plugin, mas nunca foi observado de
fato rodando aqui — o teste de pentest usa um `FlutterSecureStorage` mockado/fake, não a
implementação nativa real. Recomendação: antes de ir pra produção, testar manualmente em
um device físico com uma sessão biométrica já salva de uma versão anterior do app,
confirmando que o login rápido continua funcionando após o update (não só um novo login).

## Fora do escopo desta entrega

`minSdk` do Android (26) e `IPHONEOS_DEPLOYMENT_TARGET` do iOS (13.0) já satisfazem os
mínimos exigidos pelas novas versões (23-24 e 12, respectivamente) — nenhuma mudança de
configuração nativa foi necessária. `AndroidManifest.xml`/`Info.plist` não tocados.

Branch `chore/upgrade-kgp-plugins`, a partir de `main`, aguardando autorização explícita
do fundador para merge — junto com o RELATÓRIO 20260928_0001 (workmanager), agora
superado em escopo por esta entrega (os 4 pacotes do aviso original resolvidos).
