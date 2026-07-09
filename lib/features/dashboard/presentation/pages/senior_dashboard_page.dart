import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/models/health_payload_model.dart';
import '../../data/models/medicamento_model.dart';
import '../../data/models/resultado_exame_model.dart';
import '../../data/services/senior_dashboard_service.dart';
import '../controllers/camera_capture_controller.dart';
import '../widgets/camera_capture_view.dart';
import '../widgets/health_payload_dialog.dart';

/// Tela principal do Perfil 2 (Guardião Clínico / Sênior) — PRD Mestre
/// §1/§2/§4.
///
/// Deliberadamente NÃO existe aqui: cards esportivos, ligas, contagem de
/// passos ou chama de streak — nenhum widget de gamificação é sequer
/// importado neste arquivo, então não há como um deles vazar para esta
/// árvore por engano.
///
/// A tela é a Pasta Digital de Exames (linha do tempo cronológica de
/// `resultados_exames`) mais o módulo "Medicamentos do Dia" e dois botões
/// grandes e acessíveis para registro assíncrono via câmera (Balança /
/// Pressão), reaproveitando o mesmo pipeline zero-storage de
/// [CameraCaptureView] já usado pelo Perfil 1.
class SeniorDashboardPage extends StatefulWidget {
  const SeniorDashboardPage({super.key});

  @override
  State<SeniorDashboardPage> createState() => _SeniorDashboardPageState();
}

class _SeniorDashboardPageState extends State<SeniorDashboardPage> {
  final SeniorDashboardService _service = SeniorDashboardService();

  bool _isLoading = true;
  List<ResultadoExameModel> _exames = const [];
  List<MedicamentoModel> _medicamentos = const [];
  String? _medicamentoConfirmandoId;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);
    final resultados = await Future.wait([
      _service.carregarExames(),
      _service.carregarMedicamentos(),
    ]);
    if (!mounted) return;
    setState(() {
      _exames = resultados[0] as List<ResultadoExameModel>;
      _medicamentos = resultados[1] as List<MedicamentoModel>;
      _isLoading = false;
    });
  }

  Future<void> _confirmarDose(MedicamentoModel medicamento) async {
    setState(() => _medicamentoConfirmandoId = medicamento.id);
    final sucesso = await _service.confirmarDoseTomada(medicamento.id);
    if (!mounted) return;
    setState(() => _medicamentoConfirmandoId = null);

    if (!sucesso) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(i18n.tr('dashboard.medication_confirm_error'))),
      );
      return;
    }
    await _carregarDados();
  }

  Future<void> _tirarFoto(TipoAparelho tipoAparelho) async {
    final extracted = await Navigator.of(context).push<HealthPayloadModel?>(
      MaterialPageRoute(
        builder: (_) => CameraCaptureView(tipoAparelho: tipoAparelho),
      ),
    );
    if (extracted != null && mounted) {
      await showExtractedDataDialog(context, extracted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _carregarDados,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      i18n.tr('dashboard.senior_dashboard_title'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    _MedicamentosDoDiaCard(
                      medicamentos: _medicamentos,
                      medicamentoConfirmandoId: _medicamentoConfirmandoId,
                      onConfirmar: _confirmarDose,
                    ),
                    const SizedBox(height: 24),
                    _RegistroAssincronoSection(onTirarFoto: _tirarFoto),
                    const SizedBox(height: 24),
                    _PastaDigitalExamesTimeline(exames: _exames),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Módulo "Medicamentos do Dia": um card por medicamento ativo, com botão
/// grande "Tomei" que fica desabilitado assim que a dose de hoje já foi
/// confirmada — nunca permite registrar a mesma dose duas vezes no dia.
class _MedicamentosDoDiaCard extends StatelessWidget {
  const _MedicamentosDoDiaCard({
    required this.medicamentos,
    required this.medicamentoConfirmandoId,
    required this.onConfirmar,
  });

  final List<MedicamentoModel> medicamentos;
  final String? medicamentoConfirmandoId;
  final ValueChanged<MedicamentoModel> onConfirmar;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.medication_outlined, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    i18n.tr('dashboard.medication_reminder_label'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (medicamentos.isEmpty)
              Text(
                i18n.tr('dashboard.medications_empty'),
                style: Theme.of(context).textTheme.bodyLarge,
              )
            else
              for (final medicamento in medicamentos)
                _MedicamentoTile(
                  medicamento: medicamento,
                  isConfirming: medicamentoConfirmandoId == medicamento.id,
                  onConfirmar: () => onConfirmar(medicamento),
                ),
          ],
        ),
      ),
    );
  }
}

class _MedicamentoTile extends StatelessWidget {
  const _MedicamentoTile({
    required this.medicamento,
    required this.isConfirming,
    required this.onConfirmar,
  });

  final MedicamentoModel medicamento;
  final bool isConfirming;
  final VoidCallback onConfirmar;

  @override
  Widget build(BuildContext context) {
    final jaTomada = medicamento.tomadaHoje;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicamento.nomeMedicamento,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  [
                    if (medicamento.dosagem != null) medicamento.dosagem!,
                    medicamento.horarioFormatado,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (jaTomada)
            Chip(
              avatar: const Icon(Icons.check_circle, size: 18),
              label: Text(i18n.tr('dashboard.medication_taken_today_label')),
            )
          else
            FilledButton(
              onPressed: isConfirming ? null : onConfirmar,
              child: isConfirming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(i18n.tr('dashboard.medication_taken_button')),
            ),
        ],
      ),
    );
  }
}

/// Registro assíncrono via câmera — botões grandes e diretos, sem o seletor
/// de tipo de aparelho do Perfil 1 (aqui o botão já diz qual é).
class _RegistroAssincronoSection extends StatelessWidget {
  const _RegistroAssincronoSection({required this.onTirarFoto});

  final ValueChanged<TipoAparelho> onTirarFoto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => onTirarFoto(TipoAparelho.balanca),
          icon: const Icon(Icons.monitor_weight_outlined),
          label: Text(i18n.tr('dashboard.take_photo_scale_button')),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => onTirarFoto(TipoAparelho.pressaoArterial),
          icon: const Icon(Icons.favorite_outline),
          label: Text(i18n.tr('dashboard.take_photo_pressure_button')),
        ),
      ],
    );
  }
}

/// Pasta Digital de Exames: linha do tempo cronológica (mais recente
/// primeiro) dos resultados extraídos de `resultados_exames`.
class _PastaDigitalExamesTimeline extends StatelessWidget {
  const _PastaDigitalExamesTimeline({required this.exames});

  final List<ResultadoExameModel> exames;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.tr('dashboard.exam_folder_tab'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        if (exames.isEmpty)
          Text(
            i18n.tr('dashboard.exam_folder_empty'),
            style: Theme.of(context).textTheme.bodyLarge,
          )
        else
          for (final exame in exames) _ExameTimelineTile(exame: exame),
      ],
    );
  }
}

class _ExameTimelineTile extends StatelessWidget {
  const _ExameTimelineTile({required this.exame});

  final ResultadoExameModel exame;

  @override
  Widget build(BuildContext context) {
    final foraDaFaixa = exame.foraDaFaixaReferencia;
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.science_outlined,
          color: foraDaFaixa ? Theme.of(context).colorScheme.error : null,
        ),
        title: Text(exame.tipoExame),
        subtitle: Text(_formatarData(exame.dataExame)),
        trailing: exame.valorResultado != null
            ? Text(
                '${exame.valorResultado}${exame.unidadeMedida != null ? ' ${exame.unidadeMedida}' : ''}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: foraDaFaixa
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
              )
            : null,
      ),
    );
  }

  static String _formatarData(DateTime data) =>
      '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
}
