import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../data/models/convite_vinculo_model.dart';
import '../controllers/vinculos_controller.dart';

/// UI de Consentimento do Paciente (Adendo v4, F.3): lista os convites de
/// profissionais com `status = 'pendente'` e deixa o paciente aceitar (abre
/// a leitura dos próprios exames/métricas para aquele profissional) ou
/// recusar (o vínculo nunca chega a ativar). Acessível a partir de
/// `ConfiguracoesPerfilPage`, em qualquer perfil de uso — B2B não depende de
/// o paciente estar no modo Atleta ou Guardião.
class GerirVinculosPage extends StatefulWidget {
  const GerirVinculosPage({super.key, this.controller});

  /// Injetável em teste (ver gerir_vinculos_page_test.dart) para não depender
  /// de rede/Supabase de verdade — mesmo padrão de [MissoesExamesPage].
  final VinculosController? controller;

  @override
  State<GerirVinculosPage> createState() => _GerirVinculosPageState();
}

class _GerirVinculosPageState extends State<GerirVinculosPage> {
  late final VinculosController _controller = widget.controller ?? VinculosController();
  late final bool _controllerEhProprio = widget.controller == null;

  @override
  void dispose() {
    if (_controllerEhProprio) _controller.dispose();
    super.dispose();
  }

  String _nomeExibicao(ConviteVinculoModel convite) =>
      convite.profissionalNickname ?? i18n.tr('vinculos.invited_by_generic');

  Future<void> _aceitar(ConviteVinculoModel convite) async {
    final sucesso = await _controller.aceitar(convite.vinculoId);
    if (!mounted || !sucesso) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          i18n.tr('vinculos.accept_success', params: {'nome': _nomeExibicao(convite)}),
        ),
      ),
    );
  }

  Future<void> _recusar(ConviteVinculoModel convite) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n.tr('vinculos.reject_confirm_title')),
        content: Text(i18n.tr('vinculos.reject_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(i18n.tr('vinculos.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(i18n.tr('vinculos.reject_confirm_action')),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await _controller.recusar(convite.vinculoId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('vinculos.title'))),
      body: SafeArea(
        child: ValueListenableBuilder<VinculosPendentesState>(
          valueListenable: _controller,
          builder: (context, state, _) {
            if (state.carregando) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: _controller.carregarConvites,
              child: Column(
                children: [
                  if (state.erro != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Text(
                        state.erro!,
                        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ),
                  Expanded(
                    child: state.convites.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  i18n.tr('vinculos.empty_state'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: state.convites.length,
                            itemBuilder: (context, index) {
                              final convite = state.convites[index];
                              return _ConviteCard(
                                convite: convite,
                                nomeExibicao: _nomeExibicao(convite),
                                processando: state.processandoVinculoId == convite.vinculoId,
                                onAceitar: () => _aceitar(convite),
                                onRecusar: () => _recusar(convite),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConviteCard extends StatelessWidget {
  const _ConviteCard({
    required this.convite,
    required this.nomeExibicao,
    required this.processando,
    required this.onAceitar,
    required this.onRecusar,
  });

  final ConviteVinculoModel convite;
  final String nomeExibicao;
  final bool processando;
  final VoidCallback onAceitar;
  final VoidCallback onRecusar;

  String _tipoProfissionalExibicao() {
    final tipo = convite.tipoProfissional;
    if (tipo == null) return '';
    return i18n.tr('vinculos.professional_type.$tipo');
  }

  String _formatarData(DateTime data) =>
      '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';

  @override
  Widget build(BuildContext context) {
    final tipoProfissional = _tipoProfissionalExibicao();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i18n.tr('vinculos.invited_by', params: {'nome': nomeExibicao}),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (tipoProfissional.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(tipoProfissional, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  convite.comEnvioGarmin ? Icons.watch_outlined : Icons.fitness_center_outlined,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    i18n.tr(
                      convite.comEnvioGarmin
                          ? 'vinculos.product_with_garmin'
                          : 'vinculos.product_without_garmin',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              i18n.tr('vinculos.invited_at', params: {'data': _formatarData(convite.convidadoEm)}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              i18n.tr('vinculos.privacy_notice'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
            if (processando)
              const Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onRecusar, child: Text(i18n.tr('vinculos.reject'))),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: onAceitar, child: Text(i18n.tr('vinculos.accept'))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
