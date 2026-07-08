/// Raw response DTO for the ViaCEP address-lookup API
/// (https://viacep.com.br/ws/{cep}/json/). Mirrors the wire format
/// field-for-field; validation and anonymization live outside this class.
///
/// ViaCEP is a Brazil-only free API — this DTO only ever represents a
/// Brazilian address. International addresses are captured as free text
/// directly on the cadastro form and never routed through this model.
class CepModel {
  final String cep;
  final String logradouro;
  final String bairro;
  final String localidade;
  final String uf;

  const CepModel({
    required this.cep,
    required this.logradouro,
    required this.bairro,
    required this.localidade,
    required this.uf,
  });

  factory CepModel.fromJson(Map<String, dynamic> json) => CepModel(
        cep: (json['cep'] as String?) ?? '',
        logradouro: (json['logradouro'] as String?) ?? '',
        bairro: (json['bairro'] as String?) ?? '',
        localidade: (json['localidade'] as String?) ?? '',
        uf: (json['uf'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'cep': cep,
        'logradouro': logradouro,
        'bairro': bairro,
        'localidade': localidade,
        'uf': uf,
      };

  /// ViaCEP responds with HTTP 200 and `{"erro": true}` (no other fields)
  /// for a CEP that doesn't exist — it is not surfaced as an HTTP error, so
  /// callers must check the decoded body explicitly before parsing.
  static bool isErrorResponse(Map<String, dynamic> json) =>
      json['erro'] == true;
}

/// LGPD-conscious geographic bucketing for regional rankings.
///
/// Builds a `PAIS-ESTADO-CIDADE` identifier so leaderboards never carry
/// street-level data (`logradouro`/`bairro`) or the raw CEP/postal code —
/// only the granularity needed to place a user in a regional ranking
/// bucket. Shared by both sign-up flows: [fromBrazil] for the ViaCEP-backed
/// Brazilian flow, [build] for international users who type their
/// país/estado/cidade manually.
class GeoRankingId {
  const GeoRankingId._();

  static String fromBrazil(CepModel cep) => build(
        pais: 'BR',
        estadoOuProvincia: cep.uf,
        cidade: cep.localidade,
      );

  static String build({
    required String pais,
    required String estadoOuProvincia,
    required String cidade,
  }) {
    final paisSlug = _slugify(pais);
    final estadoSlug = _slugify(estadoOuProvincia);
    final cidadeSlug = _slugify(cidade);
    if (paisSlug.isEmpty && estadoSlug.isEmpty && cidadeSlug.isEmpty) {
      return '';
    }
    return '$paisSlug-$estadoSlug-$cidadeSlug';
  }
}

/// Convenience accessor kept for callers that already hold a [CepModel]
/// from the Brazilian ViaCEP flow.
extension CepGeoRanking on CepModel {
  String get geoRankingId => GeoRankingId.fromBrazil(this);
}

const Map<String, String> _accentMap = {
  'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A',
  'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
  'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
  'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O',
  'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
  'Ç': 'C',
};

String _slugify(String value) {
  final upper = value.trim().toUpperCase();
  final unaccented = upper.replaceAllMapped(
    RegExp('[${_accentMap.keys.join()}]'),
    (match) => _accentMap[match.group(0)]!,
  );
  return unaccented
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}
