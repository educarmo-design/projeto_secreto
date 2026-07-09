import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/esteira_trial_controller.dart';

/// Cadeado Dourado Borrado: the Dia 7 high-impact conversion teaser. The
/// "real" longevity projection sits fully rendered behind a
/// [BackdropFilter] blur, with a centered gold-padlock offer overlay
/// driving straight to the Plano Anual checkout.
class TeaserConversaoPage extends StatelessWidget {
  const TeaserConversaoPage({
    super.key,
    required this.controller,
    required this.onLiberarProjecao,
  });

  final EsteiraTrialController controller;

  /// Directs to the Plano Anual checkout (R$ 179,90/ano, 14 dias free).
  /// Left as a callback so this page stays decoupled from whatever
  /// payment/checkout flow ends up wiring it.
  final VoidCallback onLiberarProjecao;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: ValueListenableBuilder<EsteiraTrialState>(
          valueListenable: controller,
          builder: (context, state, _) {
            return Stack(
              children: [
                Positioned.fill(child: _ConteudoProjecao(diaAtual: state.diaAtual)),
                // Regra de UI Estrita: o gráfico e o painel de insights ficam
                // fosco/borrado atrás deste filtro — nunca legíveis antes da
                // conversão.
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                    child: Container(color: Colors.black.withValues(alpha: 0.45)),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: _CadeadoDouradoOverlay(
                      onLiberarProjecao: onLiberarProjecao,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The blurred-away layer: badge, headline, the simulated 6-month
/// longevity chart, and the preventive-insights panel. Renders fully —
/// the blur, not missing content, is what hides it.
class _ConteudoProjecao extends StatelessWidget {
  const _ConteudoProjecao({required this.diaAtual});

  final int diaAtual;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryOrange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primaryOrange),
            ),
            child: Text(
              i18n.tr(
                'gamification.teaser_dia7_badge',
                params: {'dia': diaAtual.toString()},
              ),
              style: const TextStyle(
                color: AppColors.primaryOrange,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            i18n.tr('gamification.teaser_titulo'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            i18n.tr('gamification.teaser_subtitulo'),
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 28),
          Text(
            i18n.tr('gamification.teaser_grafico_eixo_tempo').toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 220,
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const CustomPaint(
              painter: _LongevityProjectionPainter(),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            i18n.tr('gamification.teaser_insight_titulo'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.insights_outlined,
                color: AppColors.secondaryBlue,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  i18n.tr('gamification.teaser_insight_placeholder'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two smooth 7-point trajectories (hoje + 6 meses) rendered with a plain
/// [CustomPainter] — no chart package. Simulated placeholder data: the real
/// projection (IA + tabelas do banco) lands here once the backend model is
/// wired up; visually this never matters much since the whole thing sits
/// under [BackdropFilter] until conversion.
class _LongevityProjectionPainter extends CustomPainter {
  const _LongevityProjectionPainter();

  static const List<double> _trajetoriaAtual = [
    0.55, 0.53, 0.50, 0.49, 0.46, 0.44, 0.41,
  ];
  static const List<double> _trajetoriaOtimizada = [
    0.55, 0.60, 0.66, 0.71, 0.78, 0.84, 0.92,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawLine(canvas, size, _trajetoriaAtual, AppColors.mutedText, dashed: true);
    _drawLine(canvas, size, _trajetoriaOtimizada, AppColors.primaryGold, dashed: false);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawLine(
    Canvas canvas,
    Size size,
    List<double> pontos,
    Color color, {
    required bool dashed,
  }) {
    final path = Path();
    for (var i = 0; i < pontos.length; i++) {
      final x = size.width * i / (pontos.length - 1);
      final y = size.height * (1 - pontos[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }

    const dashWidth = 6.0;
    const dashGap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          paint,
        );
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Centered gold-padlock offer: icon, premium seal, persuasive copy, and
/// the main CTA into the Plano Anual checkout.
class _CadeadoDouradoOverlay extends StatelessWidget {
  const _CadeadoDouradoOverlay({required this.onLiberarProjecao});

  final VoidCallback onLiberarProjecao;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: AppColors.darkSurface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primaryGold.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGold.withValues(alpha: 0.25),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFFFFD700), AppColors.primaryGold],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.lock_rounded, color: Colors.black, size: 36),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryGold,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.workspace_premium, size: 14, color: Colors.black),
                const SizedBox(width: 4),
                Text(
                  i18n.tr('gamification.teaser_selo_premium'),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            i18n.tr('gamification.teaser_cadeado_titulo'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            i18n.tr('gamification.teaser_cadeado_copy'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onLiberarProjecao,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                i18n.tr('gamification.teaser_cta_button'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            i18n.tr('gamification.teaser_plano_preco'),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            i18n.tr('gamification.teaser_plano_disclaimer'),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
