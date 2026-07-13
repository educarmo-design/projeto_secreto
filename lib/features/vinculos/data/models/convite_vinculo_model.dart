/// Um convite pendente de `vinculos_profissional_paciente` — Adendo v4, F.3:
/// o paciente decide, vínculo por vínculo, se compartilha os próprios dados.
///
/// Mistura duas leituras (ver `VinculosService.carregarConvitesPendentes`):
/// os campos do próprio vínculo (`vinculo_profissional_paciente`, que o
/// paciente já pode ler — `vinculos_select_participantes`) e o
/// nickname/tipo do profissional (`perfis_profissionais_vinculados`, a view
/// que existe só para isso — `perfis_usuarios` cifra nome/telefone/e-mail no
/// cliente, então nickname é o único campo de identificação legível
/// entre usuários).
class ConviteVinculoModel {
  final String vinculoId;
  final String profissionalId;

  /// Nulo quando o profissional ainda não preencheu nickname no cadastro
  /// (ou — improvável, mas possível — o vínculo aponta para um perfil que
  /// não existe mais). A UI cai para um rótulo genérico nesse caso.
  final String? profissionalNickname;

  /// Valor bruto do enum `tipo_profissional_saude` (ex. "Nutricionista").
  /// Nulo pela mesma razão de [profissionalNickname].
  final String? tipoProfissional;

  final bool comEnvioGarmin;
  final DateTime convidadoEm;

  const ConviteVinculoModel({
    required this.vinculoId,
    required this.profissionalId,
    this.profissionalNickname,
    this.tipoProfissional,
    required this.comEnvioGarmin,
    required this.convidadoEm,
  });

  factory ConviteVinculoModel.fromRows({
    required Map<String, dynamic> vinculo,
    Map<String, dynamic>? perfilProfissional,
  }) {
    return ConviteVinculoModel(
      vinculoId: vinculo['id'] as String,
      profissionalId: vinculo['profissional_id'] as String,
      profissionalNickname: perfilProfissional?['nickname'] as String?,
      tipoProfissional: perfilProfissional?['tipo_profissional'] as String?,
      comEnvioGarmin: vinculo['tipo_produto'] == 'com_garmin',
      convidadoEm: DateTime.parse(vinculo['criado_em'] as String),
    );
  }
}
