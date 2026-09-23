import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../nutrition/data/models/prato_refeicao_extracao_model.dart';
import '../../../nutrition/presentation/controllers/registro_refeicao_ia_controller.dart';

/// RELATÓRIO 20260922_0002 (Item 3 da tarefa "Anamnese Inteligente — UI") —
/// uma linha de refeição habitual: Horário, Fora de casa (Sim/Não), texto
/// livre + resultado da IA (reutilizada, RESTRIÇÃO explícita: "não invente
/// integrações novas do zero" — é o MESMO `RegistroRefeicaoIaController`/
/// endpoint do Registro de Refeição por texto, RELATÓRIO 20260824_0003).
class _LinhaRefeicao {
  _LinhaRefeicao({required this.controller})
      : horarioController = TextEditingController(),
        descricaoController = TextEditingController();

  final TextEditingController horarioController;
  bool foraDeCasa = false;
  final TextEditingController descricaoController;
  final RegistroRefeicaoIaController controller;

  double? kcal;
  double? proteinaG;
  double? carboidratoG;
  double? gorduraG;

  void dispose() {
    horarioController.dispose();
    descricaoController.dispose();
    controller.dispose();
  }
}

/// Renderiza N linhas de refeição (N = `numeroRefeicoes`) e mantém
/// [resultadoNotifier] sempre atualizado com o array pronto para
/// `anamneses.refeicoes_diarias_habituais` — a tela de origem só lê
/// `resultadoNotifier.value` no momento de montar o rascunho, nunca grava
/// nada sozinha.
class RefeicoesHabituaisWidget extends StatefulWidget {
  const RefeicoesHabituaisWidget({
    super.key,
    required this.numeroRefeicoes,
    required this.resultadoNotifier,
    this.habilitado = true,
    RegistroRefeicaoIaController Function()? controllerFactory,
    Map<String, String> Function()? authHeadersProvider,
  })  : _controllerFactory = controllerFactory,
        _authHeadersProvider = authHeadersProvider;

  final int numeroRefeicoes;
  final ValueNotifier<List<Map<String, dynamic>>> resultadoNotifier;
  final bool habilitado;

  /// Injetáveis em teste — mesmo padrão de [DescreverRefeicaoPage].
  final RegistroRefeicaoIaController Function()? _controllerFactory;
  final Map<String, String> Function()? _authHeadersProvider;

  @override
  State<RefeicoesHabituaisWidget> createState() => _RefeicoesHabituaisWidgetState();
}

class _RefeicoesHabituaisWidgetState extends State<RefeicoesHabituaisWidget> {
  final List<_LinhaRefeicao> _linhas = [];

  @override
  void initState() {
    super.initState();
    _ajustarQuantidadeLinhas();
  }

  @override
  void didUpdateWidget(covariant RefeicoesHabituaisWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.numeroRefeicoes != widget.numeroRefeicoes) {
      setState(_ajustarQuantidadeLinhas);
    }
  }

  @override
  void dispose() {
    for (final linha in _linhas) {
      linha.dispose();
    }
    super.dispose();
  }

  void _ajustarQuantidadeLinhas() {
    final alvo = widget.numeroRefeicoes.clamp(0, 12);
    while (_linhas.length < alvo) {
      _linhas.add(_LinhaRefeicao(controller: (widget._controllerFactory ?? RegistroRefeicaoIaController.new)()));
    }
    while (_linhas.length > alvo) {
      _linhas.removeLast().dispose();
    }
    _atualizarResultado();
  }

  static Map<String, String> _authHeadersPadrao() {
    final session = Supabase.instance.client.auth.currentSession;
    return {
      'apikey': AppConfig.supabaseAnonKey,
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  void _atualizarResultado() {
    widget.resultadoNotifier.value = [
      for (var i = 0; i < _linhas.length; i++)
        {
          'numero_refeicao': i + 1,
          if (_linhas[i].horarioController.text.trim().isNotEmpty) 'horario': _linhas[i].horarioController.text.trim(),
          'fora_de_casa': _linhas[i].foraDeCasa,
          if (_linhas[i].descricaoController.text.trim().isNotEmpty) 'descricao_texto': _linhas[i].descricaoController.text.trim(),
          if (_linhas[i].kcal != null) 'kcal': _linhas[i].kcal,
          if (_linhas[i].proteinaG != null) 'proteina_g': _linhas[i].proteinaG,
          if (_linhas[i].carboidratoG != null) 'carboidrato_g': _linhas[i].carboidratoG,
          if (_linhas[i].gorduraG != null) 'gordura_g': _linhas[i].gorduraG,
        },
    ];
  }

  Future<void> _interpretarComIa(_LinhaRefeicao linha) async {
    final descricao = linha.descricaoController.text.trim();
    if (descricao.isEmpty) return;

    final headers = (widget._authHeadersProvider ?? _authHeadersPadrao)();
    await linha.controller.interpretarTexto(
      descricao: descricao,
      endpoint: Uri.parse(AppConfig.metricPhotoExtractionEndpoint),
      headers: headers,
    );

    if (!mounted) return;
    final estado = linha.controller.value;
    if (estado.status != RegistroRefeicaoIaStatus.sucesso) return;

    final extracao = estado.extracao!;
    setState(() {
      linha.kcal = _somar(extracao, (i) => i.calorias);
      linha.proteinaG = _somar(extracao, (i) => i.proteinasG);
      linha.carboidratoG = _somar(extracao, (i) => i.carboidratosG);
      linha.gorduraG = _somar(extracao, (i) => i.gordurasG);
    });
    _atualizarResultado();
  }

  double? _somar(PratoRefeicaoExtracaoModel extracao, double Function(ItemPratoExtraidoModel) selecionar) {
    if (extracao.itens.isEmpty) return null;
    final total = extracao.itens.fold<double>(0, (soma, item) => soma + selecionar(item));
    return double.parse(total.toStringAsFixed(1));
  }

  @override
  Widget build(BuildContext context) {
    if (_linhas.isEmpty) {
      return Text(
        i18n.tr('nutricao.refeicoes_habituais_vazio'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _linhas.length; i++) ...[
          _buildLinha(context, i, _linhas[i]),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildLinha(BuildContext context, int indice, _LinhaRefeicao linha) {
    return ValueListenableBuilder<RegistroRefeicaoIaState>(
      valueListenable: linha.controller,
      builder: (context, estadoIa, _) {
        final processando = estadoIa.isProcessando;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.mutedText.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i18n.tr('nutricao.refeicoes_habituais_numero', params: {'numero': (indice + 1).toString()}),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: linha.horarioController,
                      enabled: widget.habilitado && !processando,
                      decoration: InputDecoration(
                        labelText: i18n.tr('nutricao.refeicoes_habituais_horario_label'),
                        hintText: 'HH:mm',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => _atualizarResultado(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i18n.tr('nutricao.refeicoes_habituais_fora_de_casa_label'), style: Theme.of(context).textTheme.bodySmall),
                      Switch(
                        value: linha.foraDeCasa,
                        onChanged: (widget.habilitado && !processando)
                            ? (v) => setState(() {
                                  linha.foraDeCasa = v;
                                  _atualizarResultado();
                                })
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: linha.descricaoController,
                enabled: widget.habilitado && !processando,
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(
                  labelText: i18n.tr('nutricao.refeicoes_habituais_descricao_label'),
                  hintText: i18n.tr('nutricao.refeicoes_habituais_descricao_hint'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => _atualizarResultado(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: (widget.habilitado && !processando) ? () => _interpretarComIa(linha) : null,
                    icon: processando
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(
                      processando
                          ? i18n.tr('nutricao.refeicoes_habituais_interpretando')
                          : i18n.tr('nutricao.refeicoes_habituais_interpretar_button'),
                    ),
                  ),
                ],
              ),
              if (estadoIa.isErro) ...[
                const SizedBox(height: 4),
                Text(estadoIa.errorMessage!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error)),
              ],
              if (linha.kcal != null) ...[
                const SizedBox(height: 8),
                Text(
                  i18n.tr('nutricao.refeicoes_habituais_resultado_ia', params: {
                    'kcal': linha.kcal!.toStringAsFixed(0),
                    'proteina': (linha.proteinaG ?? 0).toStringAsFixed(1),
                    'carboidrato': (linha.carboidratoG ?? 0).toStringAsFixed(1),
                    'gordura': (linha.gorduraG ?? 0).toStringAsFixed(1),
                  }),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
