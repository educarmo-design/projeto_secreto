import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/treino_model.dart';
import '../../data/repositories/treinos_historico_repository.dart';

/// RELATÓRIO 20260811_0002 (decisão do fundador) — histórico de treinos
/// (`atividades_fisicas_treinos`), com a FC isolada ao intervalo de cada
/// treino específico (calculada em `HealthSyncService._processarTreinos`,
/// não a FC do dia inteiro).
///
/// Regra 14 (Parte 0): "Validação = completa funcionalmente, crua
/// visualmente" — cards diretos, sem gráfico, sem paginação. Mesmo padrão
/// de [HistoricoTelemetriaPage]: SEMPRE um SELECT novo no Supabase, nunca
/// cache local.
class HistoricoTreinosPage extends StatefulWidget {
  const HistoricoTreinosPage({
    super.key,
    TreinosHistoricoRepository? repository,
  }) : _repository = repository;

  final TreinosHistoricoRepository? _repository;

  @override
  State<HistoricoTreinosPage> createState() => _HistoricoTreinosPageState();
}

enum _CargaStatus { carregando, sucesso, erro }

class _HistoricoTreinosPageState extends State<HistoricoTreinosPage> {
  late final TreinosHistoricoRepository _repository =
      widget._repository ?? TreinosHistoricoRepository();

  _CargaStatus _status = _CargaStatus.carregando;
  List<TreinoModel> _treinos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final treinos = await _repository.buscarUltimosTreinos();
      if (!mounted) return;
      setState(() {
        _treinos = treinos;
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('dashboard.historico_treinos_title'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                i18n.tr('dashboard.historico_treinos_subtitle'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.mutedText),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildCorpo(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildCorpo(BuildContext context) {
    switch (_status) {
      case _CargaStatus.carregando:
        return const Center(child: CircularProgressIndicator());
      case _CargaStatus.erro:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              i18n.tr('dashboard.historico_treinos_error'),
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.error),
            ),
          ),
        );
      case _CargaStatus.sucesso:
        if (_treinos.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                i18n.tr('dashboard.historico_treinos_empty'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.mutedText),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _treinos.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) => _CardTreino(treino: _treinos[index]),
        );
    }
  }
}

class _CardTreino extends StatelessWidget {
  const _CardTreino({required this.treino});

  final TreinoModel treino;

  static String _dataHoraFormatada(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year} $hora:$minuto';
  }

  static String _duracaoFormatada(Duration duracao) {
    final horas = duracao.inHours;
    final minutos = duracao.inMinutes.remainder(60);
    return horas > 0 ? '${horas}h ${minutos}min' : '${minutos}min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campos = <MapEntry<String, String>>[
      MapEntry(
        i18n.tr('dashboard.historico_treinos_field_duracao'),
        _duracaoFormatada(treino.duracao),
      ),
      if (treino.distanciaMetros != null)
        MapEntry(
          i18n.tr('dashboard.historico_treinos_field_distancia'),
          '${(treino.distanciaMetros! / 1000).toStringAsFixed(2)} km',
        ),
      if (treino.energiaQueimadaKcal != null)
        MapEntry(
          i18n.tr('dashboard.historico_treinos_field_calorias'),
          '${treino.energiaQueimadaKcal!.toStringAsFixed(0)} kcal',
        ),
      if (treino.fcMedia != null)
        MapEntry(
          i18n.tr('dashboard.historico_treinos_field_fc_media'),
          '${treino.fcMedia} bpm',
        ),
      if (treino.fcMinima != null)
        MapEntry(
          i18n.tr('dashboard.historico_treinos_field_fc_minima'),
          '${treino.fcMinima} bpm',
        ),
      if (treino.fcMaxima != null)
        MapEntry(
          i18n.tr('dashboard.historico_treinos_field_fc_maxima'),
          '${treino.fcMaxima} bpm',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(treino.nomeExibicao, style: theme.textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            _dataHoraFormatada(treino.inicioAtividade),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              for (final campo in campos)
                Text(
                  '${campo.key}: ${campo.value}',
                  style: theme.textTheme.bodyMedium,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
