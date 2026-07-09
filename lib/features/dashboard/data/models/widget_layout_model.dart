import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Every card the customizable Tela Principal can render, keyed by the
/// fixed PRD Mestre identifiers — [id] is the literal string persisted to
/// storage and never renamed, even if the enum case name changes.
enum DashboardWidgetId {
  recomendacoesIa('recomendacoes_ia'),
  fotoPratoMacros('foto_prato_macros'),
  scannerCodigoBarras('scanner_codigo_barras'),
  fotoBalanca('foto_balanca'),
  fotoPressao('foto_pressao'),
  ultimasAtividadesGarmin('ultimas_atividades_garmin'),
  statusStreakDuolingo('status_streak_duolingo'),
  micronutrientesStatus('micronutrientes_status');

  const DashboardWidgetId(this.id);

  final String id;

  static DashboardWidgetId? fromId(String id) {
    for (final valor in values) {
      if (valor.id == id) return valor;
    }
    return null;
  }
}

/// Gerenciador de layout do usuário: quais [DashboardWidgetId] estão ativos
/// e em que ordem aparecem na Tela Principal Dinâmica.
///
/// [ordem] é sempre a lista *canônica completa* — todos os 8 ids, ativos ou
/// não. Ocultar um card não o remove de [ordem] (isso perderia sua posição
/// relativa caso o usuário o reative depois); [desativados] é o único campo
/// que controla visibilidade. [visiveisEmOrdem] é a projeção que a tela
/// realmente renderiza.
@immutable
class WidgetLayoutModel {
  final List<DashboardWidgetId> ordem;
  final Set<DashboardWidgetId> desativados;

  const WidgetLayoutModel({required this.ordem, required this.desativados});

  /// Layout inicial: todos os 8 cards ativos, na ordem em que o PRD Mestre
  /// os lista.
  factory WidgetLayoutModel.padrao() => const WidgetLayoutModel(
        ordem: DashboardWidgetId.values,
        desativados: {},
      );

  List<DashboardWidgetId> get visiveisEmOrdem =>
      ordem.where((id) => !desativados.contains(id)).toList(growable: false);

  bool isAtivo(DashboardWidgetId id) => !desativados.contains(id);

  WidgetLayoutModel comOrdem(List<DashboardWidgetId> novaOrdem) =>
      WidgetLayoutModel(ordem: novaOrdem, desativados: desativados);

  WidgetLayoutModel comAtivo(DashboardWidgetId id, bool ativo) {
    final novosDesativados = Set<DashboardWidgetId>.from(desativados);
    if (ativo) {
      novosDesativados.remove(id);
    } else {
      novosDesativados.add(id);
    }
    return WidgetLayoutModel(ordem: ordem, desativados: novosDesativados);
  }

  Map<String, dynamic> toJson() => {
        'ordem': ordem.map((id) => id.id).toList(),
        'desativados': desativados.map((id) => id.id).toList(),
      };

  factory WidgetLayoutModel.fromJson(Map<String, dynamic> json) {
    final ordemBruta = (json['ordem'] as List?)?.cast<String>() ?? const [];
    final ordemValida = ordemBruta
        .map(DashboardWidgetId.fromId)
        .whereType<DashboardWidgetId>()
        .toList();

    // Um card novo lançado depois que o usuário já salvou uma ordem (ex.:
    // versão do app atualizada) entra no fim da lista em vez de sumir
    // silenciosamente do painel.
    for (final id in DashboardWidgetId.values) {
      if (!ordemValida.contains(id)) ordemValida.add(id);
    }

    final desativados = ((json['desativados'] as List?)?.cast<String>() ?? const [])
        .map(DashboardWidgetId.fromId)
        .whereType<DashboardWidgetId>()
        .toSet();

    return WidgetLayoutModel(ordem: ordemValida, desativados: desativados);
  }

  // ---------------------------------------------------------------------
  // Persistência local
  // ---------------------------------------------------------------------

  static const String _storageKey = 'dashboard_widget_layout_v1';

  /// Carrega o layout salvo — ou [WidgetLayoutModel.padrao] se nada foi
  /// salvo ainda, ou se o valor salvo estiver corrompido.
  static Future<WidgetLayoutModel> carregar({
    FlutterSecureStorage? secureStorage,
  }) async {
    final storage = secureStorage ?? const FlutterSecureStorage();
    try {
      final raw = await storage.read(key: _storageKey);
      if (raw == null) return WidgetLayoutModel.padrao();
      return WidgetLayoutModel.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('Erro ao carregar layout do painel: $e');
      return WidgetLayoutModel.padrao();
    }
  }

  /// Persiste a ordem/visibilidade escolhida pelo usuário — chamado após
  /// cada reorder (drag and drop) e após cada toggle no BottomSheet de
  /// customização.
  Future<void> salvar({FlutterSecureStorage? secureStorage}) async {
    final storage = secureStorage ?? const FlutterSecureStorage();
    await storage.write(key: _storageKey, value: jsonEncode(toJson()));
  }
}
