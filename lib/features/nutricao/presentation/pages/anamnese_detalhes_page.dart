import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/anamnese_models.dart';
import '../../data/repositories/anamnese_repository.dart';

enum _CargaStatus { carregando, sucesso, erro, naoEncontrada }

/// Detalhe de UMA anamnese passada (RELATÓRIO 20261016_0005, item 2) —
/// aberta a partir de [HistoricoAnamnesesPage] ao tocar num card da
/// lista. 100% SOMENTE LEITURA — Restrição explícita da tarefa:
/// "Nenhuma anamnese passada pode ter seus dados sobrescritos". Não há
/// NENHUM botão de salvar/editar nesta tela, nem campo editável — é puro
/// `Text`, mesmo quando o valor é idêntico ao de um campo editável em
/// [AnamneseSelfServicePage] (ex.: peso/altura).
class AnamneseDetalhesPage extends StatefulWidget {
  const AnamneseDetalhesPage({super.key, required this.anamneseId, AnamneseRepository? repository})
      : _repository = repository;

  final String anamneseId;
  final AnamneseRepository? _repository;

  @override
  State<AnamneseDetalhesPage> createState() => _AnamneseDetalhesPageState();
}

class _AnamneseDetalhesPageState extends State<AnamneseDetalhesPage> {
  late final AnamneseRepository _repository = widget._repository ?? AnamneseRepository();

  _CargaStatus _status = _CargaStatus.carregando;
  AnamneseDetalheModel? _detalhe;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final detalhe = await _repository.buscarAnamnesePorId(widget.anamneseId);
      if (!mounted) return;
      setState(() {
        _detalhe = detalhe;
        _status = detalhe == null ? _CargaStatus.naoEncontrada : _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('anamnese_detalhe.title'))),
      body: SafeArea(child: _buildCorpo(context)),
    );
  }

  Widget _buildCorpo(BuildContext context) {
    switch (_status) {
      case _CargaStatus.carregando:
        return const Center(child: CircularProgressIndicator());
      case _CargaStatus.erro:
        return _buildMensagemCentral(
          context,
          texto: i18n.tr('anamnese_detalhe.load_error'),
          cor: AppColors.error,
          comBotaoTentarNovamente: true,
        );
      case _CargaStatus.naoEncontrada:
        return _buildMensagemCentral(context, texto: i18n.tr('anamnese_detalhe.nao_encontrada'));
      case _CargaStatus.sucesso:
        return _buildDetalhe(context, _detalhe!);
    }
  }

  Widget _buildMensagemCentral(
    BuildContext context, {
    required String texto,
    Color? cor,
    bool comBotaoTentarNovamente = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              texto,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cor ?? AppColors.mutedText),
            ),
            if (comBotaoTentarNovamente) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _carregar, child: Text(i18n.tr('anamnese_detalhe.tentar_novamente'))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetalhe(BuildContext context, AnamneseDetalheModel detalhe) {
    final c = detalhe.complementares;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildCabecalho(context, detalhe),
        _secao(context, i18n.tr('anamnese_detalhe.secao_dados_fisicos'), [
          _linha(context, i18n.tr('nutricao.peso_label'), '${_formatarNumero(detalhe.pesoKg)} kg'),
          _linha(context, i18n.tr('perfil_fisico.altura_label'), '${_formatarNumero(detalhe.alturaCm)} cm'),
          _linha(context, i18n.tr('nutricao.percentual_gordura_label'), _formatarNumeroOuNull(c.percentualGordura)),
          _linha(context, i18n.tr('nutricao.massa_gorda_label'), _formatarNumeroOuNull(c.massaGordaKg)),
          _linha(context, i18n.tr('nutricao.massa_magra_label'), _formatarNumeroOuNull(c.massaMagraKg)),
          _linha(context, i18n.tr('nutricao.massa_muscular_label'), _formatarNumeroOuNull(c.massaMuscularKg)),
          _linha(context, i18n.tr('nutricao.circunferencia_cintura_label'), _formatarNumeroOuNull(c.circunferenciaCinturaCm)),
          _linha(context, i18n.tr('nutricao.circunferencia_abdominal_label'), _formatarNumeroOuNull(c.circunferenciaAbdominalCm)),
        ]),
        if (detalhe.problemasSaudeNomes.isNotEmpty || detalhe.alergiasNomes.isNotEmpty)
          _secao(context, i18n.tr('anamnese_detalhe.secao_condicoes_saude'), [
            if (detalhe.problemasSaudeNomes.isNotEmpty)
              _linha(context, i18n.tr('nutricao.condicoes_selecionar_label'), detalhe.problemasSaudeNomes.join(', ')),
            if (detalhe.alergiasNomes.isNotEmpty)
              _linha(context, i18n.tr('nutricao.alergias_label'), detalhe.alergiasNomes.join(', ')),
          ]),
        if (detalhe.medicamentos.isNotEmpty)
          _secaoItensRepetiveis(context, i18n.tr('nutricao.medicamentos_label'), detalhe.medicamentos),
        if (detalhe.suplementos.isNotEmpty)
          _secaoItensRepetiveis(context, i18n.tr('nutricao.suplementos_label'), detalhe.suplementos),
        if (detalhe.exames.isNotEmpty) _secaoItensRepetiveis(context, i18n.tr('nutricao.exames_label'), detalhe.exames),
        _secao(context, i18n.tr('anamnese_detalhe.secao_alimentacao'), [
          _linha(context, i18n.tr('nutricao.numero_refeicoes_label'), c.numeroRefeicoesDia?.toString()),
          _linha(context, i18n.tr('nutricao.preferencias_alimentares_label'), c.preferenciasAlimentares),
          _linha(context, i18n.tr('nutricao.alimentos_evitados_label'), c.alimentosEvitados),
          if (detalhe.complementares.restricoesAlimentares.isNotEmpty)
            _linha(context, i18n.tr('nutricao.restricoes_alimentares_label'), c.restricoesAlimentares.join(', ')),
          if (c.intolerancias.isNotEmpty) _linha(context, i18n.tr('nutricao.intolerancias_label'), c.intolerancias.join(', ')),
          _linha(context, i18n.tr('nutricao.padrao_alimentar_label'), c.padraoAlimentarHabitual),
          if (c.restricoesCulturaisReligiosas.isNotEmpty)
            _linha(context, i18n.tr('nutricao.restricoes_culturais_label'), c.restricoesCulturaisReligiosas.join(', ')),
        ]),
        if (detalhe.atividades.isNotEmpty || c.rotinaDiaria != null || c.atividadeOcupacional != null)
          _secao(context, i18n.tr('anamnese_detalhe.secao_atividade'), [
            _linha(context, i18n.tr('nutricao.rotina_diaria_pergunta'), c.rotinaDiaria),
            _linha(context, i18n.tr('nutricao.atividade_ocupacional_label'), c.atividadeOcupacional),
            for (final atividade in detalhe.atividades)
              _linha(
                context,
                '${atividade.nomeExibicao} — ${i18n.tr('nutricao.dia_semana_${atividade.diaSemana}')}',
                '${atividade.minutos} min · ${i18n.tr('nutricao.intensidade_${atividade.intensidade}')}',
              ),
          ]),
        _secao(context, i18n.tr('anamnese_detalhe.secao_sono'), [
          _linha(context, i18n.tr('nutricao.sono_horas_medias_label'), _formatarNumeroOuNull(c.horasSonoMedias)),
          _linha(context, i18n.tr('nutricao.sono_horario_dormir_label'), c.horarioDormirHabitual),
          _linha(context, i18n.tr('nutricao.sono_horario_acordar_label'), c.horarioAcordarHabitual),
          _linha(context, i18n.tr('nutricao.sono_qualidade_label'), c.qualidadeSonoPercebida),
          _linha(context, i18n.tr('nutricao.sono_despertares_label'), c.despertaresNoturnos?.toString()),
        ]),
        if (c.objetivosSecundarios.isNotEmpty ||
            c.metaPesoDesejadoKg != null ||
            c.metaPercentualGorduraDesejado != null ||
            c.metaMassaDesejadaKg != null)
          _secao(context, i18n.tr('anamnese_detalhe.secao_metas'), [
            if (c.objetivosSecundarios.isNotEmpty)
              _linha(context, i18n.tr('nutricao.objetivos_secundarios_label'), c.objetivosSecundarios.join(', ')),
            _linha(context, i18n.tr('nutricao.meta_peso_desejado_label'), _formatarNumeroOuNull(c.metaPesoDesejadoKg)),
            _linha(
              context,
              i18n.tr('nutricao.meta_percentual_gordura_desejado_label'),
              _formatarNumeroOuNull(c.metaPercentualGorduraDesejado),
            ),
            _linha(context, i18n.tr('nutricao.meta_massa_desejada_label'), _formatarNumeroOuNull(c.metaMassaDesejadaKg)),
            _linha(context, i18n.tr('nutricao.meta_outro_indicador_label'), c.metaOutroIndicador),
          ]),
      ],
    );
  }

  Widget _buildCabecalho(BuildContext context, AnamneseDetalheModel detalhe) {
    final ativa = detalhe.statusVigencia == 'ativo';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.primaryGold.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.primaryGold),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_formatarData(detalhe.dataPreenchimento), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(i18n.tr('nutricao.objetivo_${detalhe.objetivoCodigo}')),
          const SizedBox(height: 4),
          Text(
            ativa
                ? i18n.tr('nutricao.historico_anamnese_item_ativo')
                : i18n.tr('nutricao.historico_anamnese_item_historico'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _secao(BuildContext context, String titulo, List<Widget?> linhas) {
    final visiveis = linhas.whereType<Widget>().toList();
    if (visiveis.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...visiveis,
        ],
      ),
    );
  }

  Widget _secaoItensRepetiveis(BuildContext context, String titulo, List<ItemRepetivel> itens) {
    return _secao(context, titulo, [
      for (final item in itens)
        _linha(
          context,
          item.nome,
          item.campos.isEmpty ? null : item.campos.entries.map((e) => '${e.key}: ${e.value}').join(' · '),
        ),
    ]);
  }

  /// `null` quando [valor] é nulo/vazio — a linha inteira some (Regra 23:
  /// nunca mostra um rótulo com valor inventado tipo "—" por padrão, só
  /// omite o que não foi preenchido).
  Widget? _linha(BuildContext context, String label, String? valor) {
    if (valor == null || valor.trim().isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText)),
          ),
          Expanded(
            flex: 3,
            child: Text(valor, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  static String _formatarNumero(double valor) {
    return valor == valor.truncateToDouble() ? valor.toStringAsFixed(0) : valor.toString();
  }

  static String? _formatarNumeroOuNull(double? valor) => valor == null ? null : _formatarNumero(valor);

  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }
}
