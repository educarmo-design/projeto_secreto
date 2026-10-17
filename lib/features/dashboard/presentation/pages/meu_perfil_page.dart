import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../vinculos/data/models/vinculo_ativo_model.dart';
import '../../../vinculos/data/services/vinculos_service.dart';
import '../../data/repositories/perfil_usuario_repository.dart';

enum _CargaStatus { carregando, sucesso, erro }

/// Tela de Perfil (RELATÓRIO 20261016_0005) — "com qual email estou
/// logado, sou paciente ou profissional, quem me acompanha" + edição de
/// Nome/CEP. Diferente de [PerfilUsuarioPage] ("Meus Dados Físicos" —
/// data de nascimento/sexo biológico, insumo do Motor Metabólico): esta
/// tela é sobre a IDENTIDADE da conta, não dado físico.
///
/// Restrição da tarefa: só Nome e CEP são editáveis aqui. Email, tipo de
/// perfil e a lista de profissionais vinculados são somente leitura — não
/// há caminho de escrita para nenhum dos três nesta tela (email é
/// definido no cadastro; tipo de perfil e vínculos são geridos pelo
/// backend/painel profissional, nunca pelo próprio paciente).
///
/// Mesmo padrão de [PerfilUsuarioPage]: `StatefulWidget` + repositório
/// injetável em teste, `enum _CargaStatus`, `Form`+botão Salvar cru
/// (Regra 14).
class MeuPerfilPage extends StatefulWidget {
  const MeuPerfilPage({
    super.key,
    PerfilUsuarioRepository? repository,
    VinculosService? vinculosService,
  })  : _repository = repository,
        _vinculosService = vinculosService;

  final PerfilUsuarioRepository? _repository;
  final VinculosService? _vinculosService;

  @override
  State<MeuPerfilPage> createState() => _MeuPerfilPageState();
}

class _MeuPerfilPageState extends State<MeuPerfilPage> {
  late final PerfilUsuarioRepository _repository =
      widget._repository ?? PerfilUsuarioRepository();
  late final VinculosService _vinculosService =
      widget._vinculosService ?? VinculosService();

  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _cepController = TextEditingController();

  _CargaStatus _status = _CargaStatus.carregando;
  bool _salvando = false;
  PerfilContaResumo? _perfilConta;
  List<VinculoAtivoModel> _vinculosAtivos = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _cepController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final perfilConta = await _repository.buscarPerfilConta();
      final vinculosAtivos = await _vinculosService.carregarVinculosAtivos();
      if (!mounted) return;
      setState(() {
        _perfilConta = perfilConta;
        _vinculosAtivos = vinculosAtivos;
        _nomeController.text = perfilConta?.nome ?? '';
        _cepController.text = perfilConta?.cep ?? '';
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  String? _validarNome(String? valor) {
    if ((valor ?? '').trim().isEmpty) {
      return i18n.tr('meu_perfil.nome_validation_empty');
    }
    return null;
  }

  static final _cepApenasDigitos = RegExp(r'^\d{8}$');

  String? _validarCep(String? valor) {
    final digitos = (valor ?? '').replaceAll(RegExp(r'\D'), '');
    if (digitos.isEmpty) {
      return i18n.tr('meu_perfil.cep_validation_empty');
    }
    if (!_cepApenasDigitos.hasMatch(digitos)) {
      return i18n.tr('meu_perfil.cep_validation_invalid');
    }
    return null;
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _salvando = true);
    try {
      final cepDigitos = _cepController.text.replaceAll(RegExp(r'\D'), '');
      await _repository.atualizarNomeECep(
        nome: _nomeController.text.trim(),
        cep: cepDigitos,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('meu_perfil.save_success')),
            backgroundColor: AppColors.success,
          ),
        );
      await _carregar();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('meu_perfil.save_error')),
            backgroundColor: AppColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  String _tipoPerfilExibicao(PerfilContaResumo perfil) {
    if (!perfil.ehProfissional) return i18n.tr('meu_perfil.tipo_perfil_paciente');
    final tipo = perfil.tipoProfissional;
    if (tipo == null) return i18n.tr('meu_perfil.tipo_perfil_profissional');
    return i18n.tr('vinculos.professional_type.$tipo');
  }

  String _nomeExibicaoVinculo(VinculoAtivoModel vinculo) =>
      vinculo.profissionalNickname ?? i18n.tr('vinculos.invited_by_generic');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('meu_perfil.title'))),
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
                  i18n.tr('meu_perfil.load_error'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _carregar, child: Text(i18n.tr('meu_perfil.save_button'))),
              ],
            ),
          ),
        );
      case _CargaStatus.sucesso:
        final perfil = _perfilConta;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(i18n.tr('meu_perfil.identificacao_label'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _buildCampoLeitura(
              context,
              label: i18n.tr('meu_perfil.email_label'),
              valor: perfil?.email ?? i18n.tr('meu_perfil.email_vazio'),
            ),
            const SizedBox(height: 16),
            _buildCampoLeitura(
              context,
              label: i18n.tr('meu_perfil.tipo_perfil_label'),
              valor: perfil == null ? '—' : _tipoPerfilExibicao(perfil),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text(i18n.tr('meu_perfil.vinculos_label'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _buildVinculosAtivos(context),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text(i18n.tr('meu_perfil.editar_label'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nomeController,
                    decoration: InputDecoration(
                      labelText: i18n.tr('meu_perfil.nome_label'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: _validarNome,
                    enabled: !_salvando,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cepController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: i18n.tr('meu_perfil.cep_label'),
                      hintText: i18n.tr('meu_perfil.cep_hint'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: _validarCep,
                    enabled: !_salvando,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _salvando ? null : _salvar,
                    child: _salvando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(i18n.tr('meu_perfil.save_button')),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget _buildCampoLeitura(BuildContext context, {required String label, required String valor}) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), enabled: false),
      child: Text(valor),
    );
  }

  Widget _buildVinculosAtivos(BuildContext context) {
    if (_vinculosAtivos.isEmpty) {
      return Text(
        i18n.tr('meu_perfil.vinculos_vazio'),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
      );
    }

    return Column(
      children: [
        for (final vinculo in _vinculosAtivos)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.medical_services_outlined),
              title: Text(_nomeExibicaoVinculo(vinculo)),
              subtitle: vinculo.tipoProfissional == null
                  ? null
                  : Text(i18n.tr('vinculos.professional_type.${vinculo.tipoProfissional}')),
            ),
          ),
      ],
    );
  }
}
