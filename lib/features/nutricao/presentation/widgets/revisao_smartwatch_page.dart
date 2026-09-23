import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/anamnese_models.dart';

/// RELATÓRIO 20260922_0002 (Item 2 da tarefa "Anamnese Inteligente — UI") —
/// resultado da revisão: só os itens que o usuário marcou "Aceitar" viram
/// dado de verdade na tela de origem ([AnamneseSelfServicePage]). `null` em
/// qualquer campo = usuário não aceitou nada daquela seção (mantém o
/// preenchimento manual, se já houver). Nunca grava nada sozinho — quem
/// abriu a revisão decide o que fazer com o resultado.
class RevisaoSmartwatchResultado {
  final List<AtividadeSelecionada> atividadesAceitas;
  final double? horasSonoAceitas;
  final double? horasTreinoSemanaAceitas;

  const RevisaoSmartwatchResultado({
    required this.atividadesAceitas,
    required this.horasSonoAceitas,
    required this.horasTreinoSemanaAceitas,
  });
}

/// UX de Revisão (RESTRIÇÃO explícita da tarefa: "O sistema NÃO deve salvar
/// os dados automaticamente" — o usuário aceita/edita/exclui cada item
/// ANTES de qualquer coisa voltar pra tela de origem, e mesmo lá continua
/// só em memória até o fluxo normal de "Confirmar e Enviar"/"Salvar"
/// gravar). Semáforo de Confiabilidade (Verde/Amarelo/Vermelho) só é
/// mostrado onde o backend de fato devolve uma `percentual_confiabilidade`
/// (as métricas diárias — aqui, Sono); `processar_medias_smartwatch` NÃO
/// devolve uma % pra Atividades/Carga de Treino (só `ocorrencias_totais`/
/// `semanas_do_periodo`), então essas 2 seções mostram esse contexto de
/// suporte estatístico em vez de uma porcentagem inventada — este projeto
/// nunca arbitra um número que o backend não calculou (mesmo espírito da
/// Regra 0.15/N27 já aplicada no resto do app).
class RevisaoSmartwatchPage extends StatefulWidget {
  const RevisaoSmartwatchPage({
    super.key,
    required this.resultado,
    required this.catalogoAtividades,
    required this.atividadesJaAdicionadas,
  });

  final MediasSmartwatchResultado resultado;
  final List<TipoAtividadeItem> catalogoAtividades;

  /// Pra não pré-marcar como "aceitar" uma atividade que o usuário já
  /// adicionou manualmente no mesmo dia — evita duplicidade óbvia.
  final List<AtividadeSelecionada> atividadesJaAdicionadas;

  @override
  State<RevisaoSmartwatchPage> createState() => _RevisaoSmartwatchPageState();
}

class _ItemAtividadeRevisao {
  _ItemAtividadeRevisao({required this.atividade, required this.tipo, required this.aceitar})
      : minutosController = TextEditingController(text: atividade.mediaDuracaoMinutosPorSemana.round().toString()),
        intensidade = 'moderada';

  final AtividadeSmartwatch atividade;
  final TipoAtividadeItem tipo;
  bool aceitar;
  String intensidade;
  final TextEditingController minutosController;
}

class _RevisaoSmartwatchPageState extends State<RevisaoSmartwatchPage> {
  late final List<_ItemAtividadeRevisao> _itensAtividade;

  bool _aceitarSono = false;
  late final TextEditingController _horasSonoController;

  bool _aceitarCarga = false;
  late final TextEditingController _horasCargaController;

  @override
  void initState() {
    super.initState();

    final tiposPorCodigo = {for (final t in widget.catalogoAtividades) t.nomeCodigo: t};
    _itensAtividade = [
      for (final lista in widget.resultado.atividadesPorDiaSemana.values)
        for (final atividade in lista)
          if (tiposPorCodigo[atividade.modalidadeCodigo] case final tipo?)
            _ItemAtividadeRevisao(
              atividade: atividade,
              tipo: tipo,
              aceitar: !widget.atividadesJaAdicionadas
                  .any((a) => a.atividadeId == tipo.id && a.diaSemana == atividade.diaSemana),
            ),
    ];

    final minutosSono = widget.resultado.metricas['minutos_sono'];
    _horasSonoController = TextEditingController(
      text: minutosSono?.media != null ? (minutosSono!.media! / 60).toStringAsFixed(1) : '',
    );

    _horasCargaController = TextEditingController(
      text: widget.resultado.cargaAtleta.mediaSemanalHoras > 0
          ? widget.resultado.cargaAtleta.mediaSemanalHoras.toStringAsFixed(1)
          : '',
    );
  }

  @override
  void dispose() {
    for (final item in _itensAtividade) {
      item.minutosController.dispose();
    }
    _horasSonoController.dispose();
    _horasCargaController.dispose();
    super.dispose();
  }

  void _confirmar() {
    final atividadesAceitas = <AtividadeSelecionada>[
      for (final item in _itensAtividade)
        if (item.aceitar)
          AtividadeSelecionada(
            atividadeId: item.tipo.id,
            nomeExibicao: item.tipo.nomeExibicao,
            minutos: int.tryParse(item.minutosController.text.trim()) ?? item.atividade.mediaDuracaoMinutosPorSemana.round(),
            diaSemana: item.atividade.diaSemana,
            intensidade: item.intensidade,
          ),
    ];

    final horasSono = _aceitarSono ? double.tryParse(_horasSonoController.text.trim().replaceAll(',', '.')) : null;
    final horasCarga = _aceitarCarga ? double.tryParse(_horasCargaController.text.trim().replaceAll(',', '.')) : null;

    Navigator.of(context).pop(
      RevisaoSmartwatchResultado(
        atividadesAceitas: atividadesAceitas,
        horasSonoAceitas: horasSono,
        horasTreinoSemanaAceitas: horasCarga,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final minutosSono = widget.resultado.metricas['minutos_sono'];

    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('nutricao.smartwatch_revisao_title'))),
      body: SafeArea(
        child: !widget.resultado.temAlgumDado
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    i18n.tr('nutricao.smartwatch_sem_dados'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    i18n.tr('nutricao.smartwatch_revisao_aviso'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 24),

                  // ─── Sono ───
                  Text(i18n.tr('nutricao.sono_label'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (minutosSono?.media == null)
                    Text(i18n.tr('nutricao.smartwatch_sem_dados'), style: Theme.of(context).textTheme.bodySmall)
                  else
                    _CardRevisaoComConfiabilidade(
                      confiabilidade: minutosSono!.percentualConfiabilidade,
                      aceitar: _aceitarSono,
                      onAceitarChanged: (v) => setState(() => _aceitarSono = v),
                      child: TextField(
                        controller: _horasSonoController,
                        enabled: _aceitarSono,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        decoration: InputDecoration(
                          labelText: i18n.tr('nutricao.sono_horas_medias_label'),
                          suffixText: 'h',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),

                  // ─── Carga de Treino ───
                  Text(i18n.tr('nutricao.smartwatch_carga_treino_label'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    i18n.tr('nutricao.smartwatch_sem_confiabilidade_aviso'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 8),
                  if (widget.resultado.cargaAtleta.mediaSemanalHoras <= 0)
                    Text(i18n.tr('nutricao.smartwatch_sem_dados'), style: Theme.of(context).textTheme.bodySmall)
                  else
                    _CardRevisaoSimples(
                      subtitulo: i18n.tr(
                        'nutricao.smartwatch_carga_treino_subtitulo',
                        params: {'semanas': widget.resultado.cargaAtleta.semanasNoPeriodo.toStringAsFixed(1)},
                      ),
                      aceitar: _aceitarCarga,
                      onAceitarChanged: (v) => setState(() => _aceitarCarga = v),
                      child: TextField(
                        controller: _horasCargaController,
                        enabled: _aceitarCarga,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        decoration: InputDecoration(
                          labelText: i18n.tr('nutricao.bloco_atleta_horas_semana_label'),
                          suffixText: 'h/semana',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),

                  // ─── Atividades por dia da semana ───
                  Text(i18n.tr('nutricao.rotina_dia_semana_label'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    i18n.tr('nutricao.smartwatch_sem_confiabilidade_aviso'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
                  ),
                  const SizedBox(height: 8),
                  if (_itensAtividade.isEmpty)
                    Text(i18n.tr('nutricao.smartwatch_sem_dados'), style: Theme.of(context).textTheme.bodySmall)
                  else
                    for (final item in _itensAtividade) _buildItemAtividade(context, item),

                  const SizedBox(height: 32),
                  FilledButton(onPressed: _confirmar, child: Text(i18n.tr('nutricao.smartwatch_confirmar_button'))),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(i18n.tr('nutricao.smartwatch_manual_button')),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildItemAtividade(BuildContext context, _ItemAtividadeRevisao item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.mutedText.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${i18n.tr('nutricao.dia_semana_${item.atividade.diaSemana}')} · ${item.tipo.nomeExibicao}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Checkbox(value: item.aceitar, onChanged: (v) => setState(() => item.aceitar = v ?? false)),
            ],
          ),
          Text(
            i18n.tr('nutricao.smartwatch_atividade_subtitulo', params: {
              'ocorrencias': item.atividade.ocorrenciasTotais.toString(),
              'semanas': item.atividade.semanasDoPeriodo.toString(),
            }),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
          ),
          if (item.aceitar) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: item.minutosController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: i18n.tr('nutricao.atividades_modal_minutos_label'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: item.intensidade,
                    decoration: InputDecoration(labelText: i18n.tr('nutricao.atividades_modal_intensidade_label'), isDense: true),
                    items: [
                      for (final intensidade in const ['leve', 'moderada', 'alta'])
                        DropdownMenuItem(value: intensidade, child: Text(i18n.tr('nutricao.intensidade_$intensidade'))),
                    ],
                    onChanged: (v) => setState(() => item.intensidade = v ?? 'moderada'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Badge Verde (>70%) / Amarelo (30-70%) / Vermelho (<30%) — RESTRIÇÃO
/// explícita da tarefa, mesmos limiares citados literalmente.
class _BadgeConfiabilidade extends StatelessWidget {
  const _BadgeConfiabilidade({required this.percentual});

  final double percentual;

  @override
  Widget build(BuildContext context) {
    final cor = percentual > 70
        ? AppColors.success
        : percentual >= 30
            ? AppColors.warning
            : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(
        '${percentual.toStringAsFixed(0)}%',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cor, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CardRevisaoComConfiabilidade extends StatelessWidget {
  const _CardRevisaoComConfiabilidade({
    required this.confiabilidade,
    required this.aceitar,
    required this.onAceitarChanged,
    required this.child,
  });

  final double confiabilidade;
  final bool aceitar;
  final ValueChanged<bool> onAceitarChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.mutedText.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(i18n.tr('nutricao.smartwatch_confiabilidade_label'), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 8),
              _BadgeConfiabilidade(percentual: confiabilidade),
              const Spacer(),
              Text(i18n.tr('nutricao.smartwatch_aceitar_label'), style: Theme.of(context).textTheme.bodySmall),
              Checkbox(value: aceitar, onChanged: (v) => onAceitarChanged(v ?? false)),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

class _CardRevisaoSimples extends StatelessWidget {
  const _CardRevisaoSimples({
    required this.subtitulo,
    required this.aceitar,
    required this.onAceitarChanged,
    required this.child,
  });

  final String subtitulo;
  final bool aceitar;
  final ValueChanged<bool> onAceitarChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.mutedText.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(subtitulo, style: Theme.of(context).textTheme.bodySmall)),
              Text(i18n.tr('nutricao.smartwatch_aceitar_label'), style: Theme.of(context).textTheme.bodySmall),
              Checkbox(value: aceitar, onChanged: (v) => onAceitarChanged(v ?? false)),
            ],
          ),
          child,
        ],
      ),
    );
  }
}
