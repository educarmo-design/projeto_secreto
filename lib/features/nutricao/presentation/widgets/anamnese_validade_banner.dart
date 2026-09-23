import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/anamnese_repository.dart';
import '../../domain/anamnese_validade_status.dart';
import '../pages/anamnese_self_service_page.dart';

/// Laranja distinto de [AppColors.warning] (âmbar, já usado pro lembrete) —
/// RESTRIÇÃO explícita da tarefa: 3 cores diferentes (amarelo/laranja/
/// vermelho) pros 3 níveis não-ok.
const _corAtrasada = Color(0xFFFF7A1A);

/// RELATÓRIO 20260922_0002 (Item 5) — Widget de Notificação e Bloqueio de
/// Validade, montado no Dashboard. Lê `anamneses.data_validade` (via
/// [AnamneseRepository.buscarDataValidadeAnamnese]) e usa
/// [AnamneseValidadeStatus] (lógica pura, compartilhada com o bloqueio de
/// `MetaBemEstarPage`) pra decidir o nível do alerta. Nunca aparece
/// (`SizedBox.shrink`) quando não há nada a avisar, quando ainda está
/// carregando, ou quando o usuário dispensou um alerta não-bloqueante
/// (RESTRIÇÃO explícita: "Permitir dispensar/fechar os alertas
/// não-bloqueantes" — dispensa é só da SESSÃO atual, sem persistência
/// entre reaberturas do app; documentado como decisão de escopo no
/// relatório).
class AnamneseValidadeBanner extends StatefulWidget {
  const AnamneseValidadeBanner({super.key, AnamneseRepository? repository}) : _repository = repository;

  final AnamneseRepository? _repository;

  @override
  State<AnamneseValidadeBanner> createState() => _AnamneseValidadeBannerState();
}

class _AnamneseValidadeBannerState extends State<AnamneseValidadeBanner> {
  late final AnamneseRepository _repository = widget._repository ?? AnamneseRepository();

  AnamneseValidadeStatus? _status;
  bool _dispensado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final dataValidade = await _repository.buscarDataValidadeAnamnese();
      if (!mounted) return;
      setState(() => _status = AnamneseValidadeStatus.calcular(dataValidade));
    } catch (_) {
      // Silencioso de propósito — este widget é informativo/de conveniência;
      // uma falha aqui nunca deve quebrar o Dashboard inteiro.
    }
  }

  void _refazerAnamnese() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AnamneseSelfServicePage()));
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null || !status.exigeAlerta || _dispensado) return const SizedBox.shrink();

    final cor = switch (status.nivel) {
      AnamneseValidadeNivel.lembrete => AppColors.warning,
      AnamneseValidadeNivel.atrasada => _corAtrasada,
      AnamneseValidadeNivel.bloqueada => AppColors.error,
      AnamneseValidadeNivel.ok => AppColors.mutedText,
    };

    final titulo = switch (status.nivel) {
      AnamneseValidadeNivel.lembrete => i18n.tr('nutricao.validade_lembrete_titulo'),
      AnamneseValidadeNivel.atrasada => i18n.tr('nutricao.validade_atrasada_titulo'),
      AnamneseValidadeNivel.bloqueada => i18n.tr('nutricao.validade_bloqueada_titulo'),
      AnamneseValidadeNivel.ok => '',
    };

    final mensagem = switch (status.nivel) {
      AnamneseValidadeNivel.lembrete when status.dias == 0 => i18n.tr('nutricao.validade_lembrete_hoje_mensagem'),
      AnamneseValidadeNivel.lembrete => i18n.tr('nutricao.validade_lembrete_mensagem', params: {'dias': status.dias.toString()}),
      AnamneseValidadeNivel.atrasada => i18n.tr('nutricao.validade_atrasada_mensagem', params: {'dias': status.dias.toString()}),
      AnamneseValidadeNivel.bloqueada => i18n.tr('nutricao.validade_bloqueada_mensagem', params: {'dias': status.dias.toString()}),
      AnamneseValidadeNivel.ok => '',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        border: Border.all(color: cor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_busy_outlined, color: cor, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cor))),
              if (status.podeDispensar)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _dispensado = true),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(mensagem, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cor),
              onPressed: _refazerAnamnese,
              child: Text(i18n.tr('nutricao.validade_refazer_button')),
            ),
          ),
        ],
      ),
    );
  }
}
