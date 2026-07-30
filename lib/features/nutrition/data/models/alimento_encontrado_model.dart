import 'package:flutter/foundation.dart';

/// Um alimento de `alimentos_referencia` devolvido por `search-food`
/// (Adendo v5.1 §A.3/§C.3) — espelha exatamente `AlimentoEncontrado` do lado
/// servidor (supabase/functions/search-food/index.ts). Valores nutricionais
/// são por 100g, como toda a tabela TACO/`alimentos_referencia`.
@immutable
class AlimentoEncontradoModel {
  final String id;
  final String nomeTaco;
  final List<String> aliases;
  final double caloriasKcal100g;
  final double proteinasG100g;
  final double carboidratosG100g;
  final double gordurasG100g;

  /// Similaridade de cosseno com o termo buscado, de 0.0 a 1.0 — o servidor
  /// já aplicou o `match_threshold` (0.68), então tudo que chega aqui já
  /// passou no corte de qualidade; este valor é só para exibição.
  final double similarity;

  const AlimentoEncontradoModel({
    required this.id,
    required this.nomeTaco,
    required this.aliases,
    required this.caloriasKcal100g,
    required this.proteinasG100g,
    required this.carboidratosG100g,
    required this.gordurasG100g,
    required this.similarity,
  });

  factory AlimentoEncontradoModel.fromJson(Map<String, dynamic> json) {
    return AlimentoEncontradoModel(
      id: json['id'] as String,
      nomeTaco: json['nome_taco'] as String,
      aliases: (json['aliases'] as List?)?.cast<String>() ?? const [],
      caloriasKcal100g: (json['calorias_kcal_100g'] as num).toDouble(),
      proteinasG100g: (json['proteinas_g_100g'] as num).toDouble(),
      carboidratosG100g: (json['carboidratos_g_100g'] as num).toDouble(),
      gordurasG100g: (json['gorduras_g_100g'] as num).toDouble(),
      similarity: (json['similarity'] as num).toDouble(),
    );
  }
}
