import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../vinculos/data/services/vinculos_service.dart';
import '../../data/models/anamnese_models.dart';
import '../../data/repositories/anamnese_repository.dart';
import '../../data/repositories/meta_bem_estar_repository.dart';
import '../widgets/motor_metabolico_resultado_view.dart';

enum _CargaStatus { carregando, sucesso, erro, naoEncontrada }

/// Detalhe de UMA anamnese passada (RELATÓRIO 20261016_0005, item 2;
/// ampliado no RELATÓRIO 20261102_0001 com o plano de metas vigente
/// naquele período) — aberta a partir de [HistoricoAnamnesesPage] ao
/// tocar num card da lista. 100% SOMENTE LEITURA — Restrição explícita
/// da tarefa original: "Nenhuma anamnese passada pode ter seus dados
/// sobrescritos", reafirmada pela tarefa desta ampliação. Não há NENHUM
/// botão de salvar/editar nesta tela, nem campo editável — é puro
/// `Text`, mesmo quando o valor é idêntico ao de um campo editável em
/// [AnamneseSelfServicePage] (ex.: peso/altura).
///
/// RELATÓRIO 20261102_0002 — a correlação "qual meta está atrelada a esta
/// avaliação" passou a ser por FK DIRETA ([MetaBemEstarRepository.
/// buscarMetasPorAnamneseId], `objetivos_alimentares.anamnese_id`), nunca
/// mais por janela de tempo (o RELATÓRIO 20261102_0001 original usava
/// `data_criacao`/`data_preenchimento` — o fundador rejeitou essa
/// heurística explicitamente como frágil/fora de boas práticas de
/// modelagem relacional).
class AnamneseDetalhesPage extends StatefulWidget {
  const AnamneseDetalhesPage({
    super.key,
    required this.anamneseId,
    AnamneseRepository? repository,
    MetaBemEstarRepository? metaRepository,
    VinculosService? vinculosService,
  })  : _repository = repository,
        _metaRepository = metaRepository,
        _vinculosService = vinculosService;

  final String anamneseId;
  final AnamneseRepository? _repository;
  final MetaBemEstarRepository? _metaRepository;
  final VinculosService? _vinculosService;

  @override
  State<AnamneseDetalhesPage> createState() => _AnamneseDetalhesPageState();
}

class _AnamneseDetalhesPageState extends State<AnamneseDetalhesPage> {
  late final AnamneseRepository _repository = widget._repository ?? AnamneseRepository();
  late final MetaBemEstarRepository _metaRepository = widget._metaRepository ?? MetaBemEstarRepository();
  late final VinculosService _vinculosService = widget._vinculosService ?? VinculosService();

  _CargaStatus _status = _CargaStatus.carregando;
  AnamneseDetalheModel? _detalhe;
  List<MetaResumo> _metasDoPeriodo = const [];
  Map<String, ({String? nickname, String? tipoProfissional})> _nomesProfissionais = const {};

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
      if (detalhe == null) {
        setState(() => _status = _CargaStatus.naoEncontrada);
        return;
      }

      // RELATÓRIO 20261102_0002 — FK direta: busca só as metas cujo
      // `anamnese_id` seja ESTA anamnese. `buscarMetasPorAnamneseId` já
      // devolve lista vazia sozinho quando nenhuma meta está atrelada —
      // fallback tratado na UI, nunca um erro.
      final metas = await _metaRepository.buscarMetasPorAnamneseId(widget.anamneseId);
      final nomesProfissionais = metas.any((m) => m.prescritaPorProfissional)
          ? await _vinculosService.buscarNomesProfissionaisVinculados()
          : const <String, ({String? nickname, String? tipoProfissional})>{};

      if (!mounted) return;
      setState(() {
        _detalhe = detalhe;
        _metasDoPeriodo = metas;
        _nomesProfissionais = nomesProfissionais;
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  /// Mais recente por `tipoDia` — dentro da janela de uma única anamnese
  /// é raro haver mais de uma meta pro MESMO `tipoDia` (teria que ter sido
  /// revisada 2x no mesmo período), mas quando acontece, a mais recente é
  /// a que de fato valeu por mais tempo.
  Map<String, MetaResumo> _metasPorTipoDiaMaisRecente() {
    final porTipo = <String, MetaResumo>{};
    for (final meta in _metasDoPeriodo) {
      final atual = porTipo[meta.tipoDia];
      if (atual == null || meta.dataCriacao.isAfter(atual.dataCriacao)) {
        porTipo[meta.tipoDia] = meta;
      }
    }
    return porTipo;
  }

  String _nomeExibicaoProfissional(String? profissionalId) {
    if (profissionalId == null) return i18n.tr('anamnese_detalhe.plano_origem_motor');
    final perfil = _nomesProfissionais[profissionalId];
    final nickname = perfil?.nickname ?? i18n.tr('vinculos.invited_by_generic');
    final tipo = perfil?.tipoProfissional;
    final tipoExibicao = tipo == null ? '' : ' (${i18n.tr('vinculos.professional_type.$tipo')})';
    return i18n.tr('anamnese_detalhe.plano_origem_profissional', params: {'nome': '$nickname$tipoExibicao'});
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
        _buildPlanoDeMetas(context),
        const SizedBox(height: 24),
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
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),
        _buildResultadoMotorMetabolico(context, detalhe),
      ],
    );
  }

  /// RELATÓRIO 20261103_0001 (item 3) — "ao final da tela de detalhes...
  /// exibição completa dos resultados dos cálculos do Motor Metabólico
  /// (...) exatamente como apresentados na Tela de Resultado da
  /// Avaliação": [MotorMetabolicoResultadoView] é o MESMO widget usado em
  /// [ResultadoMotorMetabolicoPage] — mesmo código, mesmos textos. Lido
  /// de `anamneses.resultado_motor_v1` (snapshot gravado por
  /// `validar_e_salvar_meta`, Gap Crítico do RELATÓRIO 20260917_0001),
  /// nunca recalculado aqui. Fallback gracioso (Regra 23) quando nenhuma
  /// meta nunca foi salva pra esta anamnese — a RPC do motor nunca
  /// escreve nada sozinha.
  Widget _buildResultadoMotorMetabolico(BuildContext context, AnamneseDetalheModel detalhe) {
    final bruto = detalhe.resultadoMotorV1;
    if (bruto == null) {
      return Text(
        i18n.tr('anamnese_detalhe.motor_sem_resultado'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText, fontStyle: FontStyle.italic),
      );
    }

    return MotorMetabolicoResultadoView(
      resultado: MotorMetabolicoV1Resultado.fromJson(bruto),
      mostrarMacrosRecomendados: true,
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

  /// RELATÓRIO 20261102_0001 — "Plano de Metas" vigente na janela desta
  /// anamnese: badge de origem (Motor Metabólico vs Prescrição Clínica) +
  /// card único (meta linear, um só `tipoDia`) OU lista expansível por
  /// dia (vários `tipoDia` distintos, ex. TREINO/DESCANSO ou os 7 dias da
  /// semana — ver `PrescricaoView.tsx`/N10). Fallback gracioso quando a
  /// janela não tem nenhuma meta.
  ///
  /// GAP CONHECIDO, documentado (não escondido — mesmo espírito do GAP já
  /// registrado no cabeçalho de `HistoricoAnamnesesPage`): TMB/GET (TDEE)
  /// nunca aparecem aqui porque `calcular_motor_metabolico_v1` é uma
  /// função PURA que nunca persiste resultado (ME-005/ME-006) —
  /// `objetivos_alimentares` só guarda o VET final (`calorias_alvo`) e os
  /// macros, nunca o TMB/GET intermediário. Mostrar só o que de fato foi
  /// persistido, nunca um valor recalculado/inventado pra completar a
  /// tabela.
  Widget _buildPlanoDeMetas(BuildContext context) {
    final metasPorTipo = _metasPorTipoDiaMaisRecente();

    if (metasPorTipo.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          i18n.tr('anamnese_detalhe.plano_sem_meta'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText, fontStyle: FontStyle.italic),
        ),
      );
    }

    final algumaPrescritaPorProfissional = metasPorTipo.values.any((m) => m.prescritaPorProfissional);
    final profissionalIdExibicao =
        metasPorTipo.values.firstWhere((m) => m.prescritaPorProfissional, orElse: () => metasPorTipo.values.first).profissionalId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('anamnese_detalhe.plano_titulo'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildBadgeOrigem(context, algumaPrescritaPorProfissional, profissionalIdExibicao),
        const SizedBox(height: 12),
        if (metasPorTipo.length == 1)
          _buildCardMeta(context, metasPorTipo.values.single, comHeaderDeTipo: false)
        else
          for (final entry in metasPorTipo.entries) _buildExpansivelMetaPorDia(context, entry.key, entry.value),
      ],
    );
  }

  Widget _buildBadgeOrigem(BuildContext context, bool prescritaPorProfissional, String? profissionalId) {
    final cor = prescritaPorProfissional ? AppColors.secondaryBlue : AppColors.primaryGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        border: Border.all(color: cor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _nomeExibicaoProfissional(prescritaPorProfissional ? profissionalId : null),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cor, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildCardMeta(BuildContext context, MetaResumo meta, {required bool comHeaderDeTipo}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (comHeaderDeTipo) ...[
              Text(meta.tipoDia, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
            ],
            Text('${meta.caloriasAlvo} kcal', style: Theme.of(context).textTheme.headlineSmall),
            Text(
              i18n.tr('anamnese_detalhe.plano_macros', params: {
                'proteina': meta.proteinaG?.toString() ?? '—',
                'carbo': meta.carboG?.toString() ?? '—',
                'gordura': meta.gorduraG?.toString() ?? '—',
              }),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpansivelMetaPorDia(BuildContext context, String tipoDia, MetaResumo meta) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(tipoDia),
        subtitle: Text('${meta.caloriasAlvo} kcal'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _buildCardMeta(context, meta, comHeaderDeTipo: false),
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
