import 'package:flutter_test/flutter_test.dart';

import 'package:atleta_gamificacao/features/auth/presentation/controllers/cadastro_controller.dart';

/// Prova a estrutura exata que [CadastroPerfilPendente.toUserMetadata]
/// produz para `client.auth.signUp(data: ...)` — é o formato registrado no
/// RELATÓRIO DE FIM DE TAREFA para o Cadastro Dinâmico (Perfil Base +
/// Profissional de Saúde).
void main() {
  CadastroPerfilPendente perfilBase({
    String? perfilUso,
    bool ehProfissional = false,
    String? tipoProfissional,
    String? registroProfissional,
    int? idade,
    double? pesoKg,
  }) {
    return CadastroPerfilPendente(
      nickname: 'usuario',
      pais: 'Brasil',
      cep: '01310-100',
      logradouro: 'Av. Paulista',
      bairro: 'Bela Vista',
      cidade: 'São Paulo',
      uf: 'SP',
      geoRankingId: 'sp-sao-paulo',
      perfilUso: perfilUso,
      ehProfissional: ehProfissional,
      tipoProfissional: tipoProfissional,
      registroProfissional: registroProfissional,
      idade: idade,
      pesoKg: pesoKg,
    );
  }

  test('toUserMetadata: Atleta não-profissional — só perfil_uso e eh_profissional', () {
    final metadata = perfilBase(
      perfilUso: 'Atleta',
      idade: 28,
      pesoKg: 74.5,
    ).toUserMetadata();

    expect(metadata, {
      'perfil_uso': 'Atleta',
      'eh_profissional': false,
      'idade': 28,
      'peso_kg': 74.5,
    });
  });

  test(
    'toUserMetadata: Guardião/Sênior E profissional — combinação de papéis completa',
    () {
      final metadata = perfilBase(
        perfilUso: 'Senior',
        ehProfissional: true,
        tipoProfissional: 'Nutricionista',
        registroProfissional: 'CRN3 12345',
        idade: 41,
        pesoKg: 68,
      ).toUserMetadata();

      expect(metadata, {
        'perfil_uso': 'Senior',
        'eh_profissional': true,
        'tipo_profissional': 'Nutricionista',
        'registro_profissional': 'CRN3 12345',
        'idade': 41,
        'peso_kg': 68.0,
      });
    },
  );

  test('toUserMetadata: registro_profissional vazio não entra no mapa', () {
    final metadata = perfilBase(
      perfilUso: 'Atleta',
      ehProfissional: true,
      tipoProfissional: 'Medico',
      registroProfissional: '',
    ).toUserMetadata();

    expect(metadata.containsKey('registro_profissional'), isFalse);
  });

  test('toUserMetadata: sem perfilUso (caminho social reduzido) omite a chave', () {
    final metadata = perfilBase().toUserMetadata();

    expect(metadata.containsKey('perfil_uso'), isFalse);
    expect(metadata['eh_profissional'], false);
  });
}
