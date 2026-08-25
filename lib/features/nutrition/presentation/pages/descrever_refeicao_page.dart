import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../controllers/registro_refeicao_ia_controller.dart';
import 'confirmacao_prato_page.dart';

/// RELATÓRIO 20260824_0003 — Registro de Refeição, Método 1 (descritivo).
/// Usuário digita a refeição em texto livre; o servidor interpreta e
/// devolve o MESMO formato de item que a foto produz — a tela de revisão/
/// edição/favoritar é a mesma `ConfirmacaoPratoPage` do Método 4, sem
/// nenhum código a mais aqui além de "digitar e interpretar".
class DescreverRefeicaoPage extends StatefulWidget {
  const DescreverRefeicaoPage({
    super.key,
    this.controller,
    Map<String, String> Function()? authHeadersProvider,
  }) : _authHeadersProvider = authHeadersProvider;

  /// Injetável em teste — mesmo padrão de `ConfirmacaoPratoPage`.
  final RegistroRefeicaoIaController? controller;

  /// Injetável em teste — mesmo padrão de `FoodSearchController`
  /// (`authHeadersProvider`). Sem isto, `Supabase.instance` (chamado só no
  /// padrão real, `_authHeadersPadrao`) lança `AssertionError` em qualquer
  /// ambiente onde o SDK não foi inicializado (todo widget test — achado
  /// real ao investigar por que os testes desta tela travavam).
  final Map<String, String> Function()? _authHeadersProvider;

  @override
  State<DescreverRefeicaoPage> createState() => _DescreverRefeicaoPageState();
}

class _DescreverRefeicaoPageState extends State<DescreverRefeicaoPage> {
  late final RegistroRefeicaoIaController _controller =
      widget.controller ?? RegistroRefeicaoIaController();
  late final bool _controllerEhProprio = widget.controller == null;
  final TextEditingController _campoDescricao = TextEditingController();

  @override
  void dispose() {
    if (_controllerEhProprio) _controller.dispose();
    _campoDescricao.dispose();
    super.dispose();
  }

  static Map<String, String> _authHeadersPadrao() {
    final session = Supabase.instance.client.auth.currentSession;
    return {
      'apikey': AppConfig.supabaseAnonKey,
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  Future<void> _interpretar() async {
    final descricao = _campoDescricao.text.trim();
    if (descricao.isEmpty) return;

    final headers = (widget._authHeadersProvider ?? _authHeadersPadrao)();
    await _controller.interpretarTexto(
      descricao: descricao,
      endpoint: Uri.parse(AppConfig.metricPhotoExtractionEndpoint),
      headers: headers,
    );

    final estado = _controller.value;
    if (!mounted || estado.status != RegistroRefeicaoIaStatus.sucesso) return;

    final confirmado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ConfirmacaoPratoPage(extracao: estado.extracao!)),
    );
    if (!mounted) return;
    if (confirmado == true) {
      Navigator.of(context).pop(true); // avisa quem abriu (dashboard) pra recarregar
    } else {
      _controller.reset(); // usuário voltou sem confirmar — deixa tentar de novo
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('descrever_refeicao.title'))),
      body: SafeArea(
        child: ValueListenableBuilder<RegistroRefeicaoIaState>(
          valueListenable: _controller,
          builder: (context, state, _) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(i18n.tr('descrever_refeicao.instrucao'), style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _campoDescricao,
                    enabled: !state.isProcessando,
                    maxLines: 6,
                    minLines: 4,
                    decoration: InputDecoration(
                      hintText: i18n.tr('descrever_refeicao.hint'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (state.isErro) ...[
                    const SizedBox(height: 12),
                    _ErroBanner(mensagem: state.errorMessage!, debugDetalhe: state.debugDetail),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: state.isProcessando ? null : _interpretar,
                    child: state.isProcessando
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 12),
                              Text(i18n.tr('descrever_refeicao.interpretando')),
                            ],
                          )
                        : Text(i18n.tr('descrever_refeicao.interpretar_button')),
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

class _ErroBanner extends StatelessWidget {
  const _ErroBanner({required this.mensagem, this.debugDetalhe});

  final String mensagem;
  final String? debugDetalhe;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mensagem, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
          if (debugDetalhe != null) ...[
            const SizedBox(height: 6),
            Text(
              debugDetalhe!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
