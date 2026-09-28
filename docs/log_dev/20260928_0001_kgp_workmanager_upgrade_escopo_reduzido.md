# 20260928_0001 — Aviso de Kotlin Gradle Plugin (KGP): upgrade de `workmanager`, escopo reduzido

**Branch:** `chore/upgrade-kgp-plugins`
**Contexto:** o fundador reportou o aviso de build do Flutter listando 4 plugins que aplicam
Kotlin Gradle Plugin (KGP) diretamente em vez do Built-in Kotlin: `device_info_plus`,
`file_picker`, `health`, `workmanager_android`. Investigação em 2 rodadas, cada uma
encerrada com uma decisão explícita do fundador via pergunta direta.

## Rodada 1 — "só o patch seguro do health"

Tentativa de bump isolado `health: ^13.3.1` → `^13.3.2`. **Impossível em isolamento**:
`health ^13.3.2` força `device_info_plus ^13.2.0` como dependência própria (constraint do
próprio pacote, não coincidência de lockfile) — exatamente o bump que essa opção pretendia
evitar. Revertido, zero diff líquido, achado reportado.

## Rodada 2 — "sim, os 4 (recomendado)"

Pesquisa de impacto real (changelogs literais via fetch, não conhecimento geral) +
varredura de uso real no código para os 4 pacotes:

- `device_info_plus`: **zero usos diretos** no código — risco puramente transitivo.
- `file_picker`: 1 arquivo (`missoes_exames_page.dart`), API usada mudou bastante entre
  as versões (`pickFiles()` → `pickFile()`, `withData`/`.files.first` → `readAsBytes()`).
- `health`: leitura pura (comentário existente no código confirma: nenhuma chamada de
  escrita); mudanças de 13.3.1→13.3.2 são irrelevantes pro uso real deste app.
- `workmanager`: 1 arquivo (`background_sync_manager.dart`), única breaking real entre
  `0.9.0+3` e `0.10.10` é o mínimo de Flutter subir pra 3.38 (já satisfeito pela versão
  instalada, 3.44.5); `0.10.6` corrige exatamente o aviso de KGP ("build with AGP 9 and
  android.builtInKotlin=false").

Fundador autorizou os 4. Ao tentar aplicar todos, **novo conflito transitivo, mais
profundo, encontrado empiricamente via `flutter pub get`** (não visível só lendo
changelogs): `device_info_plus >=13.1.0` e `file_picker >=13.0.0` convergem em exigir
`win32 ^6.x`; isso é incompatível com `flutter_secure_storage ^9.0.0` (pin atual), que via
`flutter_secure_storage_windows` trava `win32` em `^5.x`. `flutter_secure_storage` é o
pacote que guarda o token de sessão do Supabase atrás do gate biométrico — nunca citado
pelo fundador nesta tarefa.

A única versão de `flutter_secure_storage` compatível com `win32 ^6.x` é `10.2.0+`, mas
`10.0.0` (o salto de major que cruza esse caminho) tem mudanças reais e não-cosméticas:
reescrita da cifra/implementação no Android (Jetpack Security depreciado, cifra padrão de
chave/armazenamento trocada, SDK mínimo do Android sobe de 19 pra 23) e troca do backend de
armazenamento no Windows (do sistema de credenciais do Windows para arquivos criptografados
em disco) — uma mudança que pode afetar silenciosamente tokens de sessão já persistidos, e
que não dá pra verificar com segurança neste ambiente (sem build-and-run nativo real
confirmado em Android/Windows).

**Decisão**: não estender a autorização "os 4" para um 5º pacote de segurança crítica não
mencionado, sem confirmação explícita separada do fundador. Escopo reduzido para o único
pacote 100% seguro e desbloqueado: `workmanager`.

## O que foi entregue

- `pubspec.yaml`: `workmanager: ^0.9.0+3` → `^0.10.10` (único bump real), com comentário
  explicando a decisão e por que os outros 3 ficaram de fora.
- `health`, `device_info_plus`, `file_picker`: revertidos ao estado original (incluindo a
  migração de código já rascunhada em `missoes_exames_page.dart` pra API do `file_picker`
  13.x, descartada via `git checkout --`).
- `test/features/dashboard/data/services/background_sync_manager_test.dart`: o bump do
  `workmanager` adicionou um novo parâmetro nomeado (`foregroundServiceConfig`) à
  assinatura de `WorkmanagerPlatform.registerPeriodicTask` — o fake de teste
  `_FakeWorkmanagerPlatform` precisou do mesmo parâmetro pra continuar sendo um `@override`
  válido. Comentário de cabeçalho do arquivo (citava a versão antiga `0.9.0+3`) também
  atualizado.

## Verificação

- `flutter analyze`: **30 issues** (linha de base exata de antes desta tarefa — todos
  `info`, nenhum `error`/`warning` novo). Confirmado em 2 rodadas: a primeira rodada
  (antes do fix do fake de teste) mostrou 31 issues com 1 `error` novo
  (`invalid_override` em `background_sync_manager_test.dart`); corrigido, segunda rodada
  voltou a 30.
- `flutter test`: **512/512 passando**, sem regressão.

## Fora do escopo desta entrega (decisão pendente do fundador)

Upgrade de `health`/`device_info_plus`/`file_picker` continua bloqueado pelo conflito
`win32`/`flutter_secure_storage` descrito acima. Caminhos possíveis, todos exigindo
autorização explícita separada:

1. Aceitar o upgrade de `flutter_secure_storage` pra `10.2.0+` (destrava os 3), com
   investigação e teste dedicados às mudanças de cifra Android e backend Windows.
2. Deixar os 3 pacotes como estão por enquanto (o aviso de KGP continua aparecendo pra
   eles até uma decisão futura).

O aviso de KGP no build **ainda vai aparecer** para `device_info_plus`/`file_picker`/
`health` — só o `workmanager_android` foi resolvido nesta entrega.
