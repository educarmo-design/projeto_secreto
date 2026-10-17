/// Um vínculo ATIVO de `vinculos_profissional_paciente` do lado do
/// PACIENTE (RELATÓRIO 20261016_0005, Tela de Perfil) — "com qual(is)
/// profissional(is) de saúde este usuário está sendo acompanhado agora".
/// Mesma estrutura de dados de [ConviteVinculoModel] (join em memória com
/// `perfis_profissionais_vinculados`), mas outro status (`'ativo'`, não
/// `'pendente'`) e outro uso (exibição read-only no Perfil, não
/// aceitar/recusar) — por isso um modelo próprio, não o mesmo reutilizado.
class VinculoAtivoModel {
  final String vinculoId;
  final String profissionalId;

  /// Nulo quando o profissional ainda não preencheu nickname no cadastro —
  /// mesma observação de [ConviteVinculoModel.profissionalNickname].
  final String? profissionalNickname;

  /// Valor bruto do enum `tipo_profissional_saude` (ex. "Nutricionista").
  final String? tipoProfissional;

  const VinculoAtivoModel({
    required this.vinculoId,
    required this.profissionalId,
    this.profissionalNickname,
    this.tipoProfissional,
  });

  factory VinculoAtivoModel.fromRows({
    required Map<String, dynamic> vinculo,
    Map<String, dynamic>? perfilProfissional,
  }) {
    return VinculoAtivoModel(
      vinculoId: vinculo['id'] as String,
      profissionalId: vinculo['profissional_id'] as String,
      profissionalNickname: perfilProfissional?['nickname'] as String?,
      tipoProfissional: perfilProfissional?['tipo_profissional'] as String?,
    );
  }
}
