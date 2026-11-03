import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/meta_bem_estar_repository.dart';

/// RELATÓRIO 20261103_0001 — extraído de `ResultadoMotorMetabolicoPage`
/// (Seção A, "Resultados Calculados") pra ser reaproveitado por
/// [AnamneseDetalhesPage] 100% leitura: "ao final da Tela de Detalhes,
/// garanta a exibição completa dos resultados dos cálculos do Motor
/// Metabólico (...) exatamente como apresentados na Tela de Resultado da
/// Avaliação" — mesmo código, mesmos textos, nenhuma duplicação.
///
/// `mostrarMacrosRecomendados` (default `false`) — `ResultadoMotorMetabolicoPage`
/// já apresenta a distribuição de macros via o seletor INTERATIVO da Seção
/// B (`_buildProtocoloSelector`, continua lá, intocado); `AnamneseDetalhesPage`
/// não tem formulário nenhum (Restrição: 100% leitura), então pede `true`
/// pra ver a MESMA distribuição num card estático, sem chips/seleção.
class MotorMetabolicoResultadoView extends StatelessWidget {
  const MotorMetabolicoResultadoView({
    super.key,
    required this.resultado,
    this.mostrarMacrosRecomendados = false,
  });

  final MotorMetabolicoV1Resultado resultado;
  final bool mostrarMacrosRecomendados;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.tr('nutricao.resultado_motor_secao_calculo_titulo'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          i18n.tr('nutricao.resultado_motor_secao_calculo_aviso'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 16),
        Text(i18n.tr('nutricao.resultado_motor_media_label'), style: Theme.of(context).textTheme.titleMedium),
        Text(
          resultado.tdeeMedio == null
              ? i18n.tr('nutricao.resultado_motor_sem_dado')
              : '${resultado.tdeeMedio!.round()} kcal',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if (resultado.tmb != null) ...[
          const SizedBox(height: 16),
          Text(i18n.tr('nutricao.resultado_motor_tmb_label'), style: Theme.of(context).textTheme.titleSmall),
          Text('${resultado.tmb!.round()} kcal', style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        _buildQualidade(context, resultado.qualidade),
        if (resultado.energiaRecomendacao != null) ...[
          const SizedBox(height: 16),
          _buildEnergiaRecomendacao(context, resultado.energiaRecomendacao!),
        ],
        if (mostrarMacrosRecomendados && resultado.macrosRecomendados != null) ...[
          const SizedBox(height: 16),
          _buildMacrosRecomendadosEstatico(context, resultado.macrosRecomendados!),
        ],
        if (resultado.avisos.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final aviso in resultado.avisos)
            Text('• $aviso', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText)),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            border: Border.all(color: AppColors.error),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            i18n.tr('nutricao.resultado_motor_aviso_disclaimer'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildQualidade(BuildContext context, QualidadeMotorResultado qualidade) {
    final cor = switch (qualidade.score) {
      'alta' => AppColors.success,
      'media' => AppColors.warning,
      _ => AppColors.error,
    };
    final rotulo = i18n.tr('nutricao.resultado_motor_qualidade_score_${qualidade.score}');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        border: Border.all(color: cor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(i18n.tr('nutricao.resultado_motor_qualidade_titulo'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  rotulo,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          for (final motivo in qualidade.motivos)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• ${i18n.tr('nutricao.resultado_motor_qualidade_motivo_$motivo')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  /// "Definição da Meta Energética V1.0" (RELATÓRIO 20260919_0001/
  /// 20260920_0001) — manutenção ou déficit calculado pela tabela
  /// multicritério. RELATÓRIO 20261103_0001 — sem o botão "Usar este
  /// valor em Calorias" (removido por pedido do fundador em
  /// `ResultadoMotorMetabolicoPage`; este widget nunca teve um, já que é
  /// 100% leitura desde o início).
  Widget _buildEnergiaRecomendacao(BuildContext context, EnergiaRecomendacaoResultado energia) {
    final descricao = energia.estrategia == 'manutencao'
        ? i18n.tr('nutricao.resultado_motor_energia_manutencao')
        : i18n.tr(
            'nutricao.resultado_motor_energia_deficit',
            params: {'percentual': ((energia.deficitPercentual ?? 0) * 100).round().toString()},
          );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.mutedText.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n.tr('nutricao.resultado_motor_energia_titulo'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('${energia.recomendacaoMediaDiaria.round()} kcal', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(descricao, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText)),
        ],
      ),
    );
  }

  /// Equivalente ESTÁTICO (sem `ChoiceChip`/seleção) do seletor de
  /// protocolos de `ResultadoMotorMetabolicoPage` — só os que o motor
  /// conseguiu calcular (`disponivel`), cada um com os gramas exatos que
  /// a RPC devolveu (nunca recalculado aqui).
  Widget _buildMacrosRecomendadosEstatico(BuildContext context, MacrosRecomendadosResultado macros) {
    final protocolosDisponiveis = [
      (codigo: 'MACRO-001', protocolo: macros.macro001),
      (codigo: 'MACRO-002', protocolo: macros.macro002),
      (codigo: 'MACRO-003', protocolo: macros.macro003),
    ].where((item) => item.protocolo.disponivel).toList();

    if (protocolosDisponiveis.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.resultado_motor_protocolo_titulo'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final item in protocolosDisponiveis)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.mutedText.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.codigo, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'P ${item.protocolo.proteinaG?.round() ?? '—'}g · '
                    'C ${item.protocolo.carboidratoG?.round() ?? '—'}g · '
                    'G ${item.protocolo.gorduraG?.round() ?? '—'}g',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
