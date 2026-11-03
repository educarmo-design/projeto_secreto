import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/anamnese_models.dart';
import '../../data/repositories/anamnese_repository.dart';
import '../../domain/anamnese_validade_status.dart';
import 'anamnese_detalhes_page.dart';

enum _CargaStatus { carregando, sucesso, erro }

/// RELATÓRIO 20260917 (item 3 — "Histórico de Anamnese e Próxima
/// Revisão") — lista todas as anamneses do usuário (data, peso, altura,
/// objetivo), mais recente primeiro, e destaca no topo a Data da Próxima
/// Revisão.
///
/// RELATÓRIO 20261101_0002 (BUG CORRIGIDO) — até esta tarefa, a Próxima
/// Revisão era calculada aqui com uma régua PRÓPRIA (`dataPreenchimento +
/// 30 dias`, hardcoded), a mesma divergência já corrigida no RELATÓRIO
/// 20261101_0001 para [AnamneseSelfServicePage]: ignorava
/// `anamneses.data_validade`/`anamnese_dias_validade_padrao` por completo.
/// Resultado real relatado: o fundador força `data_validade` pro passado
/// em teste, o Dashboard mostra "vencida", mas esta tela continuava
/// anunciando "Próxima revisão disponível em [data 30 dias depois do
/// preenchimento]" — uma 3ª régua divergente da mesma pergunta. Agora usa
/// a MESMA [AnamneseValidadeStatus] que o Dashboard/[AnamneseSelfServicePage]
/// já compartilham — zero cálculo próprio de dias restando nesta tela.
///
/// Restrição da tarefa — "Nenhuma anamnese passada pode ter seus dados
/// sobrescritos": esta tela é 100% leitura, nunca edita/deleta nada.
///
/// GAP CONHECIDO, documentado (não escondido, ver RELATÓRIO): o Motor
/// Metabólico V1 (`calcular_motor_metabolico_v1`) é uma função PURA que
/// nunca persiste resultado (ME-005/ME-006) — não existe hoje um "TMB/TDEE
/// calculado" gravado por anamnese passada pra listar aqui junto do
/// peso/altura. Persistir isso exigiria uma migration nova (fora do
/// escopo desta tarefa, cujos ARQUIVOS listam só telas Flutter) — por
/// isso esta tela mostra o snapshot real da anamnese (peso/altura/
/// objetivo/status), nunca um resultado calculado inventado ou
/// reaproveitado de outra anamnese.
class HistoricoAnamnesesPage extends StatefulWidget {
  const HistoricoAnamnesesPage({super.key, AnamneseRepository? repository})
      : _repository = repository;

  final AnamneseRepository? _repository;

  @override
  State<HistoricoAnamnesesPage> createState() => _HistoricoAnamnesesPageState();
}

class _HistoricoAnamnesesPageState extends State<HistoricoAnamnesesPage> {
  late final AnamneseRepository _repository = widget._repository ?? AnamneseRepository();

  _CargaStatus _status = _CargaStatus.carregando;
  List<AnamneseHistoricoItem> _historico = const [];
  DateTime? _dataValidade;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final historico = await _repository.buscarHistoricoAnamneses();
      final dataValidade = await _repository.buscarDataValidadeAnamnese();
      if (!mounted) return;
      setState(() {
        _historico = historico;
        _dataValidade = dataValidade;
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('nutricao.historico_anamnese_title'))),
      body: SafeArea(child: _buildCorpo(context)),
    );
  }

  Widget _buildCorpo(BuildContext context) {
    switch (_status) {
      case _CargaStatus.carregando:
        return const Center(child: CircularProgressIndicator());
      case _CargaStatus.erro:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  i18n.tr('nutricao.historico_anamnese_load_error'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _carregar, child: Text(i18n.tr('nutricao.save_button'))),
              ],
            ),
          ),
        );
      case _CargaStatus.sucesso:
        if (_historico.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                i18n.tr('nutricao.historico_anamnese_vazio'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildProximaRevisao(context),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            for (final item in _historico) _buildItem(context, item),
          ],
        );
    }
  }

  /// Destaque no topo, pedido explícito da tarefa ("calcular e exibir em
  /// destaque a Data da Próxima Revisão") — RELATÓRIO 20261101_0002,
  /// agora decidido pela MESMA [AnamneseValidadeStatus] do Dashboard, não
  /// mais por uma conta própria. `dataValidade == null` (sem anamnese
  /// vigente com validade calculada — 1ª anamnese recém-criada antes do
  /// trigger computar, ou linha de antes do RELATÓRIO 20260922_0001, sem
  /// backfill) cai no mesmo "disponível agora" do nível `atrasada`/
  /// `bloqueada` — nunca mostra uma data inventada sem dado real.
  Widget _buildProximaRevisao(BuildContext context) {
    final dataValidade = _dataValidade;
    final nivel = AnamneseValidadeStatus.calcular(dataValidade).nivel;
    String texto;
    if (dataValidade == null ||
        nivel == AnamneseValidadeNivel.atrasada ||
        nivel == AnamneseValidadeNivel.bloqueada) {
      texto = i18n.tr('nutricao.historico_anamnese_proxima_revisao_disponivel');
    } else {
      texto = i18n.tr('nutricao.historico_anamnese_proxima_revisao_label', params: {
        'data': _formatarData(dataValidade),
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryGold.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.primaryGold),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_available_outlined, color: AppColors.primaryGold),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: Theme.of(context).textTheme.titleSmall)),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, AnamneseHistoricoItem item) {
    final pesoAltura = item.pesoKg != null && item.alturaCm != null
        ? i18n.tr('nutricao.historico_anamnese_peso_altura', params: {
            'peso': _formatarNumero(item.pesoKg!),
            'altura': _formatarNumero(item.alturaCm!),
          })
        : i18n.tr('nutricao.historico_anamnese_sem_peso_altura');

    // RELATÓRIO 20261016_0005 (item 2) — abre o detalhe 100% leitura
    // daquela anamnese específica. Restrição da tarefa: nunca edita nada
    // aqui, [AnamneseDetalhesPage] não tem nenhum campo editável.
    void abrirDetalhes() => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => AnamneseDetalhesPage(anamneseId: item.id)),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            title: Text(_formatarData(item.dataPreenchimento)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i18n.tr('nutricao.objetivo_${item.objetivoCodigo}')),
                Text(pesoAltura),
              ],
            ),
            isThreeLine: true,
            trailing: Text(
              item.statusVigencia == 'ativo'
                  ? i18n.tr('nutricao.historico_anamnese_item_ativo')
                  : i18n.tr('nutricao.historico_anamnese_item_historico'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
            ),
            // O card inteiro continua tocável (atalho) — o botão abaixo é
            // a afordância EXPLÍCITA e visível (RELATÓRIO 20261102_0003,
            // item 2: "garanta um botão/link visível"), pro usuário nunca
            // depender de adivinhar que o card é tocável.
            onTap: abrirDetalhes,
          ),
          const Divider(height: 1),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: abrirDetalhes,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: Text(i18n.tr('nutricao.historico_anamnese_ver_detalhes_button')),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatarNumero(double valor) {
    return valor == valor.truncateToDouble() ? valor.toStringAsFixed(0) : valor.toString();
  }

  /// dd/mm/aaaa — mesmo padrão simples do resto do app.
  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }
}
