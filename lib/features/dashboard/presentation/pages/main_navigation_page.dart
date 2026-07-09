import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/router/ui_profile_switcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/senior_theme.dart';
import '../../../gamification/models/gamification_models.dart';
import '../../../gamification/repositories/gamification_repository.dart';
import '../../../intelligence/data/repositories/recommendations_repository.dart';
import '../../data/models/health_payload_model.dart';
import '../../data/models/widget_layout_model.dart';
import '../controllers/camera_capture_controller.dart';
import '../controllers/layout_controller.dart';
import '../widgets/camera_capture_view.dart';
import '../widgets/dynamic_widget_factory.dart';
import '../widgets/health_payload_dialog.dart';
import 'configuracoes_perfil_page.dart';
import 'gerenciador_layout_page.dart';
import 'senior_dashboard_page.dart';

/// Casca principal de navegação do app — Zero Trust §5: escuta
/// [uiProfileSwitcher] globalmente e troca o layout inteiro instantaneamente
/// quando `perfil_uso` muda, sem esperar por uma nova navegação.
///
/// Perfil Atleta -> layout competitivo (estilo Strava), cuja aba Dashboard é
/// a Tela Principal Dinâmica e Customizável: uma [ReorderableListView] de
/// cards independentes ([DashboardWidgetFactory]) cuja ordem/visibilidade o
/// próprio usuário controla via [layoutController] — reordenar direto no
/// Dashboard, ou pela tela dedicada [GerenciadorLayoutPage].
///
/// Perfil Sênior/Guardião -> [SeniorDashboardPage] (tema acessível, Pasta
/// Digital de Exames, Medicamentos do Dia) + Perfil. As rotas de jogo não
/// apenas ficam inacessíveis por redirect (já garantido por
/// `AppRouter._handleRedirect`) — elas simplesmente não existem na árvore de
/// widgets deste shell, o que é o que torna o bloqueio "instantâneo": não há
/// aba, botão ou rota de gamificação para sequer tentar tocar.
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _athleteTabIndex = 0;
  int _seniorTabIndex = 0;

  final GamificationRepository _gamificationRepository =
      GamificationRepository();
  final RecommendationsRepository _recommendationsRepository =
      RecommendationsRepository();

  Streak? _streak;
  League? _liga;
  String? _recomendacaoIa;

  @override
  void initState() {
    super.initState();
    uiProfileSwitcher.addListener(_onProfileChanged);
    layoutController.addListener(_onLayoutChanged);
    _carregarGamificacao();
    _carregarRecomendacaoIa();
  }

  @override
  void dispose() {
    uiProfileSwitcher.removeListener(_onProfileChanged);
    layoutController.removeListener(_onLayoutChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  void _onLayoutChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _carregarGamificacao() async {
    final streak = await _gamificationRepository.getCachedStreak();
    final liga = await _gamificationRepository.getCachedLeague();
    if (!mounted) return;
    setState(() {
      _streak = streak;
      _liga = liga;
    });
  }

  /// Leitura pura do cache local (`RecommendationsRepository`) — nunca
  /// dispara uma nova chamada ao Gemini a partir do Dashboard. O insight só
  /// é gerado uma vez, no Gatilho do Dia 7 (`IntelligenceController` via
  /// `TeaserConversaoPage`); aqui é só o Card Recomendações da IA lendo o
  /// que já foi salvo, instantâneo e offline.
  Future<void> _carregarRecomendacaoIa() async {
    final insight = await _recommendationsRepository.obterUltimoInsight();
    if (!mounted) return;
    setState(() => _recomendacaoIa = insight);
  }

  /// Abre [GerenciadorLayoutPage] em página cheia com uma transição de
  /// slide (da direita para a esquerda) em vez do `MaterialPageRoute`
  /// padrão — microinteração deliberada, não incidental.
  void _abrirGerenciadorLayout() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => const GerenciadorLayoutPage(),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  Future<void> _capturarEExibir(TipoAparelho tipoAparelho) async {
    final extracted = await Navigator.of(context).push<HealthPayloadModel?>(
      MaterialPageRoute(
        builder: (_) => CameraCaptureView(tipoAparelho: tipoAparelho),
      ),
    );
    if (extracted != null && mounted) {
      await showExtractedDataDialog(context, extracted);
    }
  }

  void _handleScanBarcode() {
    // Leitura de código de barras precisa de um pacote dedicado (ex.:
    // mobile_scanner) e configuração nativa de câmera que este projeto
    // ainda não tem (sem pastas android/ios ainda) — o gancho já está
    // cabeado ponta a ponta (card -> callback -> aqui); falta só plugar o
    // scanner real quando as plataformas nativas existirem.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(i18n.tr('dashboard.scanner_barcode_coming_soon'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (uiProfileSwitcher.isLoading && uiProfileSwitcher.profileType == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Guardião/Sênior é o único perfil com o jogo travado; qualquer outro
    // valor (Atleta, Assíncrono ou ainda não definido) recebe o layout
    // competitivo padrão.
    if (uiProfileSwitcher.isSenior) {
      return _SeniorShell(
        currentIndex: _seniorTabIndex,
        onTabSelected: (index) => setState(() => _seniorTabIndex = index),
      );
    }

    final data = DashboardCardData(
      streakAtual: _streak,
      ligaAtual: _liga,
      recomendacaoIaResumo: _recomendacaoIa,
      onFotoPrato: () => _capturarEExibir(TipoAparelho.pratoRefeicao),
      onScanBarcode: _handleScanBarcode,
      onFotoBalanca: () => _capturarEExibir(TipoAparelho.balanca),
      onFotoPressao: () => _capturarEExibir(TipoAparelho.pressaoArterial),
    );

    return _AthleteShell(
      currentIndex: _athleteTabIndex,
      onTabSelected: (index) => setState(() => _athleteTabIndex = index),
      layout: layoutController.layout,
      cardData: data,
      onReorder: layoutController.atualizarOrdemVisivel,
      onCustomizePressed: _abrirGerenciadorLayout,
    );
  }
}

/// Layout competitivo estilo Strava: fundo escuro, acentos dourado/laranja,
/// navegação em 4 abas. A aba Dashboard (índice 0) é a Tela Principal
/// Dinâmica e Customizável.
class _AthleteShell extends StatelessWidget {
  const _AthleteShell({
    required this.currentIndex,
    required this.onTabSelected,
    required this.layout,
    required this.cardData,
    required this.onReorder,
    required this.onCustomizePressed,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final WidgetLayoutModel? layout;
  final DashboardCardData cardData;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onCustomizePressed;

  static const List<_TabSpec> _tabs = [
    _TabSpec(icon: Icons.dashboard_outlined, labelKey: 'dashboard.title'),
    _TabSpec(icon: Icons.emoji_events_outlined, labelKey: 'gamification.leagues'),
    _TabSpec(icon: Icons.leaderboard_outlined, labelKey: 'gamification.rankings'),
    _TabSpec(icon: Icons.person_outline, labelKey: 'profile.title'),
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: getDarkTheme(),
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: AppBar(
          title: Text(i18n.tr('app_title')),
          actions: [
            // Botão discreto — só aparece na própria aba que ele customiza.
            if (currentIndex == 0)
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: i18n.tr('dashboard.customize_panel_button'),
                onPressed: onCustomizePressed,
              ),
          ],
        ),
        body: IndexedStack(
          index: currentIndex,
          children: [
            _DynamicDashboardHome(
              layout: layout,
              data: cardData,
              onReorder: onReorder,
            ),
            const _CompetitiveSectionPlaceholder(
              icon: Icons.emoji_events,
              titleKey: 'gamification.leagues',
              descriptionKey: 'gamification.league_description',
            ),
            const _CompetitiveSectionPlaceholder(
              icon: Icons.leaderboard,
              titleKey: 'gamification.your_rank',
              descriptionKey: 'gamification.offline_ranking',
            ),
            const ConfiguracoesPerfilPage(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.darkSurface,
          selectedItemColor: AppColors.primaryGold,
          unselectedItemColor: AppColors.mutedText,
          currentIndex: currentIndex,
          onTap: onTabSelected,
          items: [
            for (final tab in _tabs)
              BottomNavigationBarItem(
                icon: Icon(tab.icon),
                label: i18n.tr(tab.labelKey),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tela Principal Dinâmica: renderiza [layout.visiveisEmOrdem] num
/// [ReorderableListView], onde arrastar um card já persiste a nova ordem
/// via [layoutController].
class _DynamicDashboardHome extends StatelessWidget {
  const _DynamicDashboardHome({
    required this.layout,
    required this.data,
    required this.onReorder,
  });

  final WidgetLayoutModel? layout;
  final DashboardCardData data;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final layoutAtual = layout;
    if (layoutAtual == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final visiveis = layoutAtual.visiveisEmOrdem;
    if (visiveis.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            i18n.tr('dashboard.customize_panel_empty_state'),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.mutedText),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: visiveis.length,
      onReorderItem: onReorder,
      itemBuilder: (context, index) {
        final id = visiveis[index];
        return Padding(
          key: ValueKey(id),
          padding: const EdgeInsets.only(bottom: 16),
          child: DashboardWidgetFactory.build(id, data),
        );
      },
    );
  }
}

/// Tema acessível (ver [getSeniorTheme]), navegação em 2 abas — Pasta
/// Digital de Exames (tela principal do Perfil 2) e Perfil/Configurações.
/// Nenhuma aba de gamificação existe nesta árvore.
class _SeniorShell extends StatelessWidget {
  const _SeniorShell({
    required this.currentIndex,
    required this.onTabSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  static const List<_TabSpec> _tabs = [
    _TabSpec(icon: Icons.folder_shared_outlined, labelKey: 'dashboard.exam_folder_tab'),
    _TabSpec(icon: Icons.person_outline, labelKey: 'profile.title'),
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: getSeniorTheme(),
      child: Scaffold(
        appBar: AppBar(title: Text(i18n.tr('app_title'))),
        body: IndexedStack(
          index: currentIndex,
          children: const [
            SeniorDashboardPage(),
            ConfiguracoesPerfilPage(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          selectedFontSize: 16,
          unselectedFontSize: 14,
          iconSize: 32,
          currentIndex: currentIndex,
          onTap: onTabSelected,
          items: [
            for (final tab in _tabs)
              BottomNavigationBarItem(
                icon: Icon(tab.icon),
                label: i18n.tr(tab.labelKey),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({required this.icon, required this.labelKey});

  final IconData icon;
  final String labelKey;
}

class _CompetitiveSectionPlaceholder extends StatelessWidget {
  const _CompetitiveSectionPlaceholder({
    required this.icon,
    required this.titleKey,
    required this.descriptionKey,
  });

  final IconData icon;
  final String titleKey;
  final String descriptionKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.primaryGold),
            const SizedBox(height: 16),
            Text(
              i18n.tr(titleKey),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              i18n.tr(descriptionKey),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
