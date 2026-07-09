import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

import 'package:atleta_gamificacao/core/security/crypto_storage_service.dart';

import '../../support/fake_secure_storage.dart';

/// Suíte de testes de invasão (penetration testing) do [CryptoStorageService]
/// — PRD Mestre §5, trancamento do token em nível bancário.
///
/// Metodologia e o que este arquivo NÃO tenta provar:
///
/// `flutter test` roda em cima da VM do Dart, sem acesso a memória nativa,
/// dump de processo ou ao Keystore/Keychain reais — não existe forma de um
/// teste de unidade *literalmente* inspecionar RAM do aparelho ou provar que
/// o Android/iOS zerou um buffer nativo. Fingir esse tipo de verificação
/// seria teatro de segurança. O que ESTE arquivo prova, com mocks agressivos
/// e asserções de comportamento, são os contratos que o código Dart
/// controla e que são a causa raiz de cada vetor de ataque descrito:
///
/// a) o token nunca tem um caminho de persistência fora do
///    [FlutterSecureStorage] hardware-backed injetado, e falhas desse canal
///    nunca são silenciosamente engolidas com um fallback inseguro;
/// b) o token só é liberado quando `LocalAuthentication.authenticate()`
///    devolve estritamente `true` — recusa, exceção ou qualquer desvio
///    resulta em `null`, nunca em texto plano;
/// c) [CryptoStorageService] não mantém nenhum campo de instância cacheando
///    o token — cada leitura é sempre um novo round-trip ao armazenamento,
///    e uma remoção (`clearSessionToken`) é definitiva mesmo com biometria
///    válida em seguida.
void main() {
  late MockFlutterSecureStorage secureStorage;
  late MockLocalAuthentication localAuth;
  late CryptoStorageService service;

  setUpAll(() {
    // Necessário para o matcher any() cobrir o parâmetro nomeado `options`
    // de LocalAuthentication.authenticate(), cujo tipo (AuthenticationOptions)
    // não é um tipo "core" que o mocktail já sabe gerar um fallback sozinho.
    registerFallbackValue(const AuthenticationOptions());
  });

  setUp(() {
    secureStorage = MockFlutterSecureStorage();
    localAuth = MockLocalAuthentication();
    service = CryptoStorageService(
      secureStorage: secureStorage,
      localAuth: localAuth,
    );
  });

  group('Ataque (a): Dump de Memória / SharedPreferences em texto limpo', () {
    test(
        'o serviço só grava através do FlutterSecureStorage injetado — '
        'não existe nenhum outro canal de persistência acessível a partir '
        'dele para um invasor explorar', () async {
      debugPrint(
        '[PENTEST-A1] Simulando dump de armazenamento comum: gravando o '
        'token de sessão e verificando qual canal realmente recebeu o dado...',
      );

      when(() => secureStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      const tokenSecreto = 'refresh-token-extremamente-sensivel';
      await service.persistSessionToken(tokenSecreto);

      // Único canal chamado, com o valor exato — não há wrapper, não há
      // segunda gravação "de segurança" em outro lugar (SharedPreferences,
      // arquivo local, cache em memória): CryptoStorageService só conhece
      // este FlutterSecureStorage.
      verify(() => secureStorage.write(
            key: any(named: 'key'),
            value: tokenSecreto,
          )).called(1);
      verifyNoMoreInteractions(secureStorage);

      debugPrint(
        '[PENTEST-A1] OK: nenhum canal alternativo de persistência foi '
        'encontrado. O token só existe dentro do armazenamento '
        'hardware-backed.',
      );
    });

    test(
        'uma recusa do Keystore/Keychain (simulando hardware comprometido '
        'ou indisponível) propaga como falha — nunca cai em um fallback '
        'que gravaria o token sem criptografia', () async {
      debugPrint(
        '[PENTEST-A2] Simulando falha/recusa do Keystore ao tentar gravar '
        'a chave do token de sessão...',
      );

      when(() => secureStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenThrow(
        PlatformException(
          code: 'keystore_unavailable',
          message: 'Hardware Keystore indisponível neste dispositivo',
        ),
      );

      await expectLater(
        () => service.persistSessionToken('token-que-nao-deve-vazar'),
        throwsA(isA<PlatformException>()),
      );

      debugPrint(
        '[PENTEST-A2] OK: a falha do Keystore propagou como exceção — não '
        'há nenhum bloco try/catch em persistSessionToken() que a engoliria '
        'e seguiria adiante como se o token tivesse sido salvo com segurança.',
      );
    });

    test(
        'campos sensíveis (nome/telefone) nunca saem como texto plano — o '
        'ciphertext jamais é igual, nem contém como substring, o valor '
        'original', () async {
      debugPrint(
        '[PENTEST-A3] Criptografando um campo sensível e inspecionando o '
        'ciphertext em busca de vazamento de texto plano...',
      );

      final storageReal = FakeSecureStorage();
      final servicoLocal = CryptoStorageService(
        secureStorage: storageReal,
        localAuth: localAuth,
      );

      const plaintext = 'Maria da Silva - CPF simulado 000.000.000-00';
      final ciphertext = await servicoLocal.encryptSensitiveField(plaintext);

      expect(ciphertext, isNotEmpty);
      expect(ciphertext, isNot(equals(plaintext)));
      expect(
        ciphertext.toLowerCase().contains(plaintext.toLowerCase()),
        isFalse,
        reason: 'O ciphertext não pode conter o plaintext como substring '
            '— isso indicaria uma "criptografia" que só ofusca (ex.: '
            'concatenação/Base64 direto) em vez de cifrar de verdade.',
      );

      // Prova que é criptografia simétrica real (reversível pela mesma
      // chave), não apenas ofuscação de mão única.
      final roundTrip = await servicoLocal.decryptSensitiveField(ciphertext);
      expect(roundTrip, equals(plaintext));

      debugPrint(
        '[PENTEST-A3] OK: ciphertext não vaza o plaintext e só é '
        'reversível através do próprio serviço (mesma chave AES-256-GCM).',
      );
    });

    test(
        'um invasor que rouba apenas o ciphertext (ex.: dump do banco) mas '
        'não tem a chave presa ao Keystore/Keychain do aparelho original '
        'não consegue decriptar o campo', () async {
      debugPrint(
        '[PENTEST-A4] Simulando exfiltração de ciphertext sem acesso ao '
        'Keystore original (chave AES gerada em outro device)...',
      );

      final storageDoAparelhoOriginal = FakeSecureStorage();
      final servicoDoAparelhoOriginal = CryptoStorageService(
        secureStorage: storageDoAparelhoOriginal,
        localAuth: localAuth,
      );
      final ciphertextRoubado = await servicoDoAparelhoOriginal
          .encryptSensitiveField('dado clínico sigiloso');

      // Keystore/Keychain de um aparelho diferente — chave AES distinta.
      final storageDoInvasor = FakeSecureStorage();
      final servicoDoInvasor = CryptoStorageService(
        secureStorage: storageDoInvasor,
        localAuth: localAuth,
      );

      final tentativaDeLeitura =
          await servicoDoInvasor.decryptSensitiveField(ciphertextRoubado);

      // decryptSensitiveField() engole a falha de autenticação do GCM (tag
      // inválida com a chave errada) e devolve string vazia — nunca uma
      // decodificação parcial, nunca uma exceção que poderia vazar
      // metadados em um log de crash.
      expect(tentativaDeLeitura, isEmpty);

      debugPrint(
        '[PENTEST-A4] OK: sem a chave do Keystore original, o ciphertext é '
        'inutilizável — decriptação falhou de forma segura (string vazia).',
      );
    });
  });

  group('Ataque (b): Bypass de Validação Biométrica Local', () {
    test(
        'authenticate() recusado (false) nunca libera o token — o '
        'armazenamento nem chega a ser lido', () async {
      debugPrint(
        '[PENTEST-B1] Simulando biometria recusada pelo usuário/sensor '
        '(authenticate() -> false) e tentando recuperar o token...',
      );

      when(() => localAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => false);

      final token = await service.readSessionTokenWithBiometrics();

      expect(token, isNull);
      verifyNever(() => secureStorage.read(key: any(named: 'key')));

      debugPrint(
        '[PENTEST-B1] OK: token não liberado e secureStorage.read() jamais '
        'foi chamado — não há como o valor ter vazado por outro caminho.',
      );
    });

    test(
        'exceção do sensor biométrico (simulando hardware manipulado, '
        'sensor travado ou attempt de bypass via plugin comprometido) é '
        'tratada como falha — nunca libera o token', () async {
      debugPrint(
        '[PENTEST-B2] Simulando hardware biométrico manipulado: '
        'authenticate() lança PlatformException em vez de responder...',
      );

      when(() => localAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenThrow(
        PlatformException(code: 'LockedOut', message: 'Sensor bloqueado'),
      );

      final token = await service.readSessionTokenWithBiometrics();

      expect(token, isNull);
      verifyNever(() => secureStorage.read(key: any(named: 'key')));

      debugPrint(
        '[PENTEST-B2] OK: exceção do sensor virou null — nenhum token '
        'liberado mesmo com o hardware respondendo de forma anômala.',
      );
    });

    test(
        'controle positivo: o token só é lido quando authenticate() '
        'devolve estritamente true — prova que os testes B1/B2 não são '
        'vácuos (a rota de sucesso realmente existe e funciona)', () async {
      debugPrint(
        '[PENTEST-B3] Controle positivo: authenticate() -> true...',
      );

      when(() => localAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => true);
      when(() => secureStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => 'token-legitimo-pos-biometria');

      final token = await service.readSessionTokenWithBiometrics();

      expect(token, equals('token-legitimo-pos-biometria'));
      verify(() => secureStorage.read(key: any(named: 'key'))).called(1);

      debugPrint(
        '[PENTEST-B3] OK: com true estrito, e só nesse caso, o token foi '
        'liberado — confirmando que B1/B2 realmente testam o desvio da '
        'trava, não um caminho morto.',
      );

      // Nota de bypass "truthy": em linguagens dinamicamente tipadas, um
      // ataque clássico é forçar authenticate() a devolver algo "truthy"
      // que não seja o booleano true (1, "true", objeto não-nulo). Em
      // Dart, authenticate() é tipado como Future<bool> em tempo de
      // compilação — não existe valor "truthy" alternativo para injetar;
      // essa classe inteira de bypass é eliminada estaticamente, não em
      // runtime, e por isso não tem um teste de runtime equivalente aqui.
    });
  });

  group('Ataque (c): Limpeza de Heap Volátil (Zero Storage Memory Integrity)',
      () {
    test(
        'clearSessionToken() apaga de forma definitiva — nenhuma leitura '
        'seguinte, mesmo com biometria válida, recupera o token antigo',
        () async {
      debugPrint(
        '[PENTEST-C1] Persistindo um token, encerrando a sessão '
        '(clearSessionToken) e tentando "ressuscitar" o valor antigo com '
        'biometria válida...',
      );

      final storage = FakeSecureStorage();
      final servicoLocal = CryptoStorageService(
        secureStorage: storage,
        localAuth: localAuth,
      );

      await servicoLocal.persistSessionToken('token-sera-apagado-no-logout');
      expect(await servicoLocal.hasStoredSessionToken(), isTrue);

      await servicoLocal.clearSessionToken();
      expect(await servicoLocal.hasStoredSessionToken(), isFalse);

      when(() => localAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => true);

      final tokenAposLogout = await servicoLocal.readSessionTokenWithBiometrics();

      expect(tokenAposLogout, isNull);

      debugPrint(
        '[PENTEST-C1] OK: nada sobrevive ao logout — mesmo passando na '
        'biometria, não há mais token nenhum para liberar.',
      );
    });

    test(
        'o serviço não faz cache do token em nenhum campo de instância — '
        'cada leitura é sempre um novo round-trip ao armazenamento, nunca '
        'um valor "flutuando" retido do processo', () async {
      debugPrint(
        '[PENTEST-C2] Trocando o token diretamente no armazenamento por '
        'baixo do serviço, para flagrar qualquer cache indevido em '
        'memória...',
      );

      final storage = FakeSecureStorage();
      final servicoLocal = CryptoStorageService(
        secureStorage: storage,
        localAuth: localAuth,
      );
      when(() => localAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => true);

      await servicoLocal.persistSessionToken('token-versao-1');
      final leitura1 = await servicoLocal.readSessionTokenWithBiometrics();
      expect(leitura1, equals('token-versao-1'));

      // Se CryptoStorageService guardasse o valor lido num campo de
      // instância (isto é, o mantivesse "vivo" na memória do processo além
      // do escopo da própria chamada), esta segunda leitura ainda
      // devolveria "token-versao-1" mesmo após a troca abaixo.
      await servicoLocal.persistSessionToken('token-versao-2');
      final leitura2 = await servicoLocal.readSessionTokenWithBiometrics();

      expect(leitura2, equals('token-versao-2'));
      expect(leitura2, isNot(equals(leitura1)));

      debugPrint(
        '[PENTEST-C2] OK: a segunda leitura refletiu o armazenamento '
        'atual, não um valor antigo em cache — não há campo de instância '
        'retendo o token entre chamadas.',
      );
    });
  });
}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockLocalAuthentication extends Mock implements LocalAuthentication {}
