import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../gamification/models/gamification_models.dart';
import '../../../nutricao/data/repositories/meta_bem_estar_repository.dart';
import '../../../nutrition/data/repositories/coleta_diaria_repository.dart';
import '../../data/models/widget_layout_model.dart';

/// Resumo de uma atividade sincronizada de wearable (Garmin/Health Connect/
/// HealthKit) — DTO de apresentação enxuto para não acoplar
/// [UltimasAtividadesCard] ao formato interno de `metricas_saude_diarias`.
@immutable
class GarminAtividadeResumo {
  final String tipoAtividade;
  final int minutosAtivos;
  final double distanciaMetros;

  const GarminAtividadeResumo({
    required this.tipoAtividade,
    required this.minutosAtivos,
    required this.distanciaMetros,
  });
}

/// Todo dado + callback que os cards configuráveis podem precisar,
/// agrupados num único bundle para que [DashboardWidgetFactory.build] tenha
/// uma assinatura simples independente de quantos cards existem. Campos
/// nulos viram o estado vazio de cada card — nunca um erro.
@immutable
class DashboardCardData {
  final String? recomendacaoIaResumo;
  final GarminAtividadeResumo? ultimaAtividadeGarmin;
  final Streak? streakAtual;
  final League? ligaAtual;

  /// Nutriente -> progresso da meta diária, de 0.0 a 1.0+ (ex.:
  /// `{'Vitamina D': 0.4, 'Ferro': 0.9}`).
  final Map<String, double>? statusMicronutrientes;

  final VoidCallback? onFotoPrato;
  final VoidCallback? onFotoRotulo;
  final VoidCallback? onFotoBalanca;
  final VoidCallback? onFotoPressao;

  /// N16 (RELATÓRIO 20260819) — `null` = ainda carregando (card mostra
  /// estado vazio, nunca "0 ml" antes da primeira leitura real).
  final int? totalAguaHojeMl;
  final VoidCallback? onAbrirHidratacao;

  /// N12 (RELATÓRIO 20260820) — `null` = ainda carregando OU usuário nunca
  /// definiu meta nenhuma; [consumoHoje] `null` = ainda carregando (card
  /// distingue os dois estados, ver [ConsumoMetaCard]).
  final MetaResumo? metaAtiva;
  final ConsumoDia? consumoHoje;

  const DashboardCardData({
    this.recomendacaoIaResumo,
    this.ultimaAtividadeGarmin,
    this.streakAtual,
    this.ligaAtual,
    this.statusMicronutrientes,
    this.onFotoPrato,
    this.onFotoRotulo,
    this.onFotoBalanca,
    this.onFotoPressao,
    this.totalAguaHojeMl,
    this.onAbrirHidratacao,
    this.metaAtiva,
    this.consumoHoje,
  });
}

/// Fábrica de Widgets Configuráveis: mapeia cada [DashboardWidgetId] para o
/// card independente correspondente. `foto_prato_macros`/`fotoRotulo`
/// compartilham a família visual "Câmera Nutricional (Misto)" e
/// `foto_balanca`/`foto_pressao` a família "Aparelhos Clínicos" — cada um
/// ainda é um item independente e reordenável/ocultável no painel, só a
/// aparência é compartilhada.
class DashboardWidgetFactory {
  const DashboardWidgetFactory._();

  static Widget build(DashboardWidgetId id, DashboardCardData data) {
    switch (id) {
      case DashboardWidgetId.recomendacoesIa:
        return RecomendacoesIaCard(resumo: data.recomendacaoIaResumo);

      case DashboardWidgetId.fotoPratoMacros:
        return CameraNutricionalCard(
          modo: _ModoCameraNutricional.fotoPrato,
          onPressed: data.onFotoPrato,
        );

      case DashboardWidgetId.fotoRotulo:
        return CameraNutricionalCard(
          modo: _ModoCameraNutricional.fotoRotulo,
          onPressed: data.onFotoRotulo,
        );

      case DashboardWidgetId.fotoBalanca:
        return AparelhoClinicoCard(
          modo: _ModoAparelhoClinico.balanca,
          onPressed: data.onFotoBalanca,
        );

      case DashboardWidgetId.fotoPressao:
        return AparelhoClinicoCard(
          modo: _ModoAparelhoClinico.pressao,
          onPressed: data.onFotoPressao,
        );

      case DashboardWidgetId.ultimasAtividadesGarmin:
        return UltimasAtividadesCard(atividade: data.ultimaAtividadeGarmin);

      case DashboardWidgetId.statusStreakDuolingo:
        return TermometroOfensivaCard(
          streak: data.streakAtual,
          liga: data.ligaAtual,
        );

      case DashboardWidgetId.micronutrientesStatus:
        return MicronutrientesStatusCard(status: data.statusMicronutrientes);

      case DashboardWidgetId.hidratacao:
        return HidratacaoCard(
          totalHojeMl: data.totalAguaHojeMl,
          onPressed: data.onAbrirHidratacao,
        );

      case DashboardWidgetId.consumoMeta:
        return ConsumoMetaCard(meta: data.metaAtiva, consumo: data.consumoHoje);
    }
  }

  /// Título i18n de cada card — usado tanto no card em si quanto na lista de
  /// linhas de [GerenciadorLayoutPage], para que os dois lugares nunca
  /// fiquem com rótulos diferentes para o mesmo id.
  static String titleKeyFor(DashboardWidgetId id) {
    switch (id) {
      case DashboardWidgetId.recomendacoesIa:
        return 'dashboard.widget_recomendacoes_ia_title';
      case DashboardWidgetId.fotoPratoMacros:
        return 'dashboard.widget_foto_prato_title';
      case DashboardWidgetId.fotoRotulo:
        return 'dashboard.widget_rotulo_nutricional_title';
      case DashboardWidgetId.fotoBalanca:
        return 'dashboard.widget_foto_balanca_title';
      case DashboardWidgetId.fotoPressao:
        return 'dashboard.widget_foto_pressao_title';
      case DashboardWidgetId.ultimasAtividadesGarmin:
        return 'dashboard.widget_atividades_garmin_title';
      case DashboardWidgetId.statusStreakDuolingo:
        return 'dashboard.widget_streak_title';
      case DashboardWidgetId.micronutrientesStatus:
        return 'dashboard.widget_micronutrientes_title';
      case DashboardWidgetId.hidratacao:
        return 'hidratacao.title';
      case DashboardWidgetId.consumoMeta:
        return 'dashboard.widget_consumo_meta_title';
    }
  }

  /// Descrição curta de uma linha, usada só por [GerenciadorLayoutPage] —
  /// mais enxuta que a descrição de dentro do próprio card, já que aqui ela
  /// cabe num `ListTile.subtitle` de uma linha só.
  static String descriptionKeyFor(DashboardWidgetId id) {
    switch (id) {
      case DashboardWidgetId.recomendacoesIa:
        return 'dashboard.card_recomendacoes_ia_desc';
      case DashboardWidgetId.fotoPratoMacros:
        return 'dashboard.card_foto_prato_desc';
      case DashboardWidgetId.fotoRotulo:
        return 'dashboard.card_rotulo_nutricional_desc';
      case DashboardWidgetId.fotoBalanca:
        return 'dashboard.card_foto_balanca_desc';
      case DashboardWidgetId.fotoPressao:
        return 'dashboard.card_foto_pressao_desc';
      case DashboardWidgetId.ultimasAtividadesGarmin:
        return 'dashboard.card_garmin_desc';
      case DashboardWidgetId.statusStreakDuolingo:
        return 'dashboard.card_streak_desc';
      case DashboardWidgetId.micronutrientesStatus:
        return 'dashboard.card_micronutrientes_desc';
      case DashboardWidgetId.hidratacao:
        return 'hidratacao.card_desc';
      case DashboardWidgetId.consumoMeta:
        return 'dashboard.card_consumo_meta_desc';
    }
  }
}

/// Casca visual compartilhada por todos os cards: fundo escuro, cantos
/// arredondados, ícone + título + conteúdo — a "linguagem de design"
/// comum que faz o painel parecer um sistema único em vez de 6 telas
/// diferentes coladas juntas.
class _DashboardCardShell extends StatelessWidget {
  const _DashboardCardShell({
    required this.icon,
    required this.titleKey,
    required this.child,
    this.iconColor,
  });

  final IconData icon;
  final String titleKey;
  final Widget child;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor ?? AppColors.primaryGold, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    i18n.tr(titleKey),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.lightText,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// (a) Card Recomendações da IA — resumo convidativo dos relatórios,
/// nunca um dump técnico.
class RecomendacoesIaCard extends StatelessWidget {
  const RecomendacoesIaCard({super.key, required this.resumo});

  final String? resumo;

  @override
  Widget build(BuildContext context) {
    return _DashboardCardShell(
      icon: Icons.auto_awesome_outlined,
      titleKey: 'dashboard.widget_recomendacoes_ia_title',
      child: Text(
        resumo ?? i18n.tr('dashboard.widget_recomendacoes_ia_empty'),
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.mutedText),
      ),
    );
  }
}

enum _ModoCameraNutricional { fotoPrato, fotoRotulo }

/// (b) Card Câmera Nutricional (Misto) — família visual compartilhada por
/// `foto_prato_macros` (câmera ao vivo, Zero Storage) e `fotoRotulo`
/// (fotografa a tabela nutricional impressa; F10 Passo 3 — antes era o
/// stub de "scanner de código de barras", religado para o extrator de
/// rótulo real, ver RELATÓRIO).
class CameraNutricionalCard extends StatelessWidget {
  const CameraNutricionalCard({
    super.key,
    required this.modo,
    required this.onPressed,
  });

  final _ModoCameraNutricional modo;
  final VoidCallback? onPressed;

  bool get _isFotoPrato => modo == _ModoCameraNutricional.fotoPrato;

  @override
  Widget build(BuildContext context) {
    final titleKey = _isFotoPrato
        ? 'dashboard.widget_foto_prato_title'
        : 'dashboard.widget_rotulo_nutricional_title';
    final descriptionKey = _isFotoPrato
        ? 'dashboard.widget_foto_prato_description'
        : 'dashboard.widget_rotulo_nutricional_description';
    final buttonKey = _isFotoPrato
        ? 'dashboard.widget_foto_prato_button'
        : 'dashboard.widget_rotulo_nutricional_button';

    return _DashboardCardShell(
      icon: _isFotoPrato
          ? Icons.restaurant_outlined
          : Icons.receipt_long_outlined,
      titleKey: titleKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            i18n.tr(descriptionKey),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.mutedText),
          ),
          if (_isFotoPrato) ...[
            const SizedBox(height: 4),
            Text(
              i18n.tr('dashboard.widget_foto_prato_zero_storage_note'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.success),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onPressed,
            child: Text(i18n.tr(buttonKey)),
          ),
        ],
      ),
    );
  }
}

enum _ModoAparelhoClinico { balanca, pressao }

/// (c) Card Aparelhos Clínicos — família visual compartilhada por
/// `foto_balanca` e `foto_pressao`, ambos usando o mesmo pipeline de
/// captura por câmera ao vivo do Perfil 1/2.
class AparelhoClinicoCard extends StatelessWidget {
  const AparelhoClinicoCard({
    super.key,
    required this.modo,
    required this.onPressed,
  });

  final _ModoAparelhoClinico modo;
  final VoidCallback? onPressed;

  bool get _isBalanca => modo == _ModoAparelhoClinico.balanca;

  @override
  Widget build(BuildContext context) {
    final titleKey = _isBalanca
        ? 'dashboard.widget_foto_balanca_title'
        : 'dashboard.widget_foto_pressao_title';
    final descriptionKey = _isBalanca
        ? 'dashboard.widget_foto_balanca_description'
        : 'dashboard.widget_foto_pressao_description';

    return _DashboardCardShell(
      icon: _isBalanca ? Icons.monitor_weight_outlined : Icons.favorite_outline,
      titleKey: titleKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            i18n.tr(descriptionKey),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: Text(i18n.tr('dashboard.camera_take_photo_button')),
          ),
        ],
      ),
    );
  }
}

/// (d) Card Últimas Atividades — minutos e distância sincronizados do
/// Garmin/wearable.
class UltimasAtividadesCard extends StatelessWidget {
  const UltimasAtividadesCard({super.key, required this.atividade});

  final GarminAtividadeResumo? atividade;

  @override
  Widget build(BuildContext context) {
    final resumo = atividade;
    return _DashboardCardShell(
      icon: Icons.directions_run_outlined,
      titleKey: 'dashboard.widget_atividades_garmin_title',
      child: resumo == null
          ? Text(
              i18n.tr('dashboard.widget_atividades_garmin_empty'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.mutedText),
            )
          : Row(
              children: [
                Expanded(
                  child: _MetricaCompacta(
                    label: resumo.tipoAtividade,
                    valor: i18n.tr(
                      'dashboard.widget_atividades_garmin_minutos',
                      params: {'minutos': resumo.minutosAtivos.toString()},
                    ),
                  ),
                ),
                Expanded(
                  child: _MetricaCompacta(
                    label: i18n.tr('dashboard.distance_label'),
                    valor: i18n.tr(
                      'dashboard.widget_atividades_garmin_distancia',
                      params: {
                        'km': (resumo.distanciaMetros / 1000)
                            .toStringAsFixed(1),
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// (e) Card Termômetro da Ofensiva — status da chama diária (streak) +
/// pontuação/liga atual.
class TermometroOfensivaCard extends StatelessWidget {
  const TermometroOfensivaCard({super.key, this.streak, this.liga});

  final Streak? streak;
  final League? liga;

  @override
  Widget build(BuildContext context) {
    if (streak == null) {
      return _DashboardCardShell(
        icon: Icons.local_fire_department_outlined,
        titleKey: 'dashboard.widget_streak_title',
        child: Text(
          i18n.tr('dashboard.widget_streak_empty'),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.mutedText),
        ),
      );
    }

    final diaAtual = streak!.currentDays;
    final ligaAtual = liga;

    return _DashboardCardShell(
      icon: Icons.local_fire_department,
      iconColor: AppColors.primaryOrange,
      titleKey: 'dashboard.widget_streak_title',
      child: Row(
        children: [
          Text(
            i18n.tr('gamification.fire_emoji'),
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.tr(
                    'gamification.streak_days',
                    params: {'days': diaAtual.toString()},
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.lightText,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (ligaAtual != null)
                  Text(
                    '${ligaAtual.getDisplayName(i18n.currentLanguage)} · '
                    '${ligaAtual.currentPoints}pts',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.mutedText),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Card do 8º id (`micronutrientes_status`) — sem descrição própria no
/// PRD Mestre (que só nomeia os cards a-e); modelado na mesma linguagem
/// visual enxuta do card de recomendações, com uma barra de progresso por
/// nutriente rastreado.
class MicronutrientesStatusCard extends StatelessWidget {
  const MicronutrientesStatusCard({super.key, required this.status});

  final Map<String, double>? status;

  @override
  Widget build(BuildContext context) {
    final entradas = status?.entries.toList() ?? const [];
    return _DashboardCardShell(
      icon: Icons.eco_outlined,
      titleKey: 'dashboard.widget_micronutrientes_title',
      child: entradas.isEmpty
          ? Text(
              i18n.tr('dashboard.widget_micronutrientes_empty'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.mutedText),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entrada in entradas.take(4)) ...[
                  Text(
                    entrada.key,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: entrada.value.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.darkBg,
                      color: entrada.value >= 1.0
                          ? AppColors.success
                          : AppColors.secondaryBlue,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

/// Card do 9º id (`hidratacao`, N16 — RELATÓRIO 20260819) — total de água já
/// registrado hoje (via [ColetaDiariaRepository.buscarTotalAguaDoDia] em
/// [MainNavigationPage]), com um botão que abre [RegistroHidratacaoPage]
/// (mesmo padrão de [AparelhoClinicoCard]: o card só resume/navega, nunca
/// registra inline).
class HidratacaoCard extends StatelessWidget {
  const HidratacaoCard({super.key, this.totalHojeMl, this.onPressed});

  final int? totalHojeMl;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final total = totalHojeMl;
    return _DashboardCardShell(
      icon: Icons.local_drink_outlined,
      titleKey: 'hidratacao.title',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            total == null
                ? i18n.tr('hidratacao.card_empty')
                : i18n.tr('hidratacao.total_hoje', params: {'total': total.toString()}),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.lightText,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.add, size: 18),
            label: Text(i18n.tr('hidratacao.button')),
          ),
        ],
      ),
    );
  }
}

/// Card do 10º id (`consumo_meta`, N12 — RELATÓRIO 20260820) — calorias e
/// macros já registrados hoje (via refeições confirmadas em
/// `ConfirmacaoPratoPage`, somadas em
/// [ColetaDiariaRepository.buscarConsumoHoje]) contra a meta EFETIVA
/// (profissional ou self-service, [MetaBemEstarRepository.buscarMetaEfetivaAtual]).
/// Só leitura/resumo — sem botão de ação, diferente dos demais cards desta
/// fábrica: a tela de definir/editar meta já existe própria
/// (`MetaBemEstarPage`), este card não duplica aquele fluxo.
class ConsumoMetaCard extends StatelessWidget {
  const ConsumoMetaCard({super.key, this.meta, this.consumo});

  final MetaResumo? meta;
  final ConsumoDia? consumo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText);

    if (meta == null) {
      return _DashboardCardShell(
        icon: Icons.track_changes_outlined,
        titleKey: 'dashboard.widget_consumo_meta_title',
        child: Text(i18n.tr('dashboard.widget_consumo_meta_sem_meta'), style: mutedStyle),
      );
    }
    if (consumo == null) {
      return _DashboardCardShell(
        icon: Icons.track_changes_outlined,
        titleKey: 'dashboard.widget_consumo_meta_title',
        child: Text(i18n.tr('dashboard.widget_consumo_meta_carregando'), style: mutedStyle),
      );
    }

    final metaVal = meta!;
    final consumoVal = consumo!;
    final progresso = metaVal.caloriasAlvo > 0
        ? (consumoVal.calorias / metaVal.caloriasAlvo).clamp(0.0, 1.0)
        : 0.0;
    final restante = metaVal.caloriasAlvo - consumoVal.calorias;

    return _DashboardCardShell(
      icon: Icons.track_changes_outlined,
      titleKey: 'dashboard.widget_consumo_meta_title',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            i18n.tr(
              'dashboard.widget_consumo_meta_calorias',
              params: {
                'consumido': consumoVal.calorias.round().toString(),
                'meta': metaVal.caloriasAlvo.toString(),
              },
            ),
            style: theme.textTheme.titleMedium
                ?.copyWith(color: AppColors.lightText, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            restante >= 0
                ? i18n.tr('dashboard.widget_consumo_meta_restante', params: {
                    'valor': restante.round().toString(),
                  })
                : i18n.tr('dashboard.widget_consumo_meta_excedido', params: {
                    'valor': (-restante).round().toString(),
                  }),
            style: mutedStyle,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 6,
              backgroundColor: AppColors.darkBg,
              color: restante < 0 ? AppColors.error : AppColors.secondaryBlue,
            ),
          ),
          if (metaVal.proteinaG != null ||
              metaVal.carboG != null ||
              metaVal.gorduraG != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              children: [
                if (metaVal.proteinaG != null)
                  _MetricaCompacta(
                    label: i18n.tr('dashboard.widget_consumo_meta_proteina'),
                    valor: '${consumoVal.proteinasG.round()}/${metaVal.proteinaG}g',
                  ),
                if (metaVal.carboG != null)
                  _MetricaCompacta(
                    label: i18n.tr('dashboard.widget_consumo_meta_carbo'),
                    valor: '${consumoVal.carboidratosG.round()}/${metaVal.carboG}g',
                  ),
                if (metaVal.gorduraG != null)
                  _MetricaCompacta(
                    label: i18n.tr('dashboard.widget_consumo_meta_gordura'),
                    valor: '${consumoVal.gordurasG.round()}/${metaVal.gorduraG}g',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricaCompacta extends StatelessWidget {
  const _MetricaCompacta({required this.label, required this.valor});

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          valor,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.lightText,
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.mutedText),
        ),
      ],
    );
  }
}
