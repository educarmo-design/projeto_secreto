import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/controllers/cadastro_controller.dart';
import '../../../vinculos/data/models/vinculo_ativo_model.dart';
import '../../../vinculos/data/services/vinculos_service.dart';
import '../../data/repositories/perfil_usuario_repository.dart';

enum _CargaStatus { carregando, sucesso, erro }

/// Tela de Perfil (RELATÓRIO 20261016_0005, ampliada no RELATÓRIO
/// 20261016_0009) — "com qual email estou logado, sou paciente ou
/// profissional, quem me acompanha" + edição de Nome/Telefone/CEP/
/// Endereço completo. Diferente de [PerfilUsuarioPage] ("Meus Dados
/// Físicos" — data de nascimento/sexo biológico, insumo do Motor
/// Metabólico): esta tela é sobre a IDENTIDADE da conta, não dado físico
/// — por isso não duplica aqueles 2 campos aqui, mesmo a tarefa de
/// ampliação os citando como exemplo (ver RELATÓRIO 20261016_0009 pra a
/// decisão completa).
///
/// RELATÓRIO 20261016_0009 — achado da auditoria de "paridade com o
/// Painel Web": o Painel Web NÃO tem nenhuma tela de perfil self-service
/// (só um formulário de CADASTRO de profissional, sem CEP/endereço). Os
/// campos novos desta tela (telefone, endereço completo com busca
/// automática por CEP via ViaCEP) vêm de onde já existiam de verdade —
/// `CadastroController`/`perfis_usuarios`, o próprio cadastro do app —
/// não do Web. Zero coluna nova, zero RPC nova (Restrição da tarefa).
///
/// Restrição original (RELATÓRIO 20261016_0005): email, tipo de perfil e
/// a lista de profissionais vinculados continuam somente leitura — não há
/// caminho de escrita para nenhum dos três nesta tela.
///
/// Mesmo padrão de [PerfilUsuarioPage]: `StatefulWidget` + repositório
/// injetável em teste, `enum _CargaStatus`, `Form`+botão Salvar cru
/// (Regra 14).
class MeuPerfilPage extends StatefulWidget {
  const MeuPerfilPage({
    super.key,
    PerfilUsuarioRepository? repository,
    VinculosService? vinculosService,
    CadastroController? cepController,
  })  : _repository = repository,
        _vinculosService = vinculosService,
        _cepController = cepController;

  final PerfilUsuarioRepository? _repository;
  final VinculosService? _vinculosService;

  /// RELATÓRIO 20261016_0009 — reaproveita literalmente o mesmo
  /// `CadastroController` (ViaCEP) do cadastro, nunca uma 2ª implementação
  /// da mesma chamada HTTP. Injetável em teste pelo mesmo motivo de
  /// `_repository`/`_vinculosService`.
  final CadastroController? _cepController;

  @override
  State<MeuPerfilPage> createState() => _MeuPerfilPageState();
}

class _MeuPerfilPageState extends State<MeuPerfilPage> {
  late final PerfilUsuarioRepository _repository =
      widget._repository ?? PerfilUsuarioRepository();
  late final VinculosService _vinculosService =
      widget._vinculosService ?? VinculosService();
  late final CadastroController _cepController =
      widget._cepController ?? CadastroController();
  late final bool _cepControllerEhProprio = widget._cepController == null;

  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _cepTextController = TextEditingController();
  final _logradouroController = TextEditingController();
  final _bairroController = TextEditingController();
  final _cidadeController = TextEditingController();
  final _estadoController = TextEditingController();

  /// RELATÓRIO 20261016_0009 (item 2 — "mover o cursor pro campo
  /// seguinte") — não existe coluna/campo de "número" em `perfis_usuarios`
  /// (nem no cadastro, nem no Web — confirmado na auditoria, Restrição
  /// "não criar coluna nova" impede inventar um aqui). O campo seguinte
  /// que de fato existe é o Logradouro — focar nele deixa o usuário
  /// completar o número direto ali, mesmo padrão informal já usado no
  /// cadastro (`_streetController` sem campo de número separado).
  final _logradouroFocusNode = FocusNode();

  _CargaStatus _status = _CargaStatus.carregando;
  bool _salvando = false;
  PerfilContaResumo? _perfilConta;
  List<VinculoAtivoModel> _vinculosAtivos = const [];

  @override
  void initState() {
    super.initState();
    _cepController.addListener(_onCepStateChanged);
    _carregar();
  }

  @override
  void dispose() {
    _cepController.removeListener(_onCepStateChanged);
    if (_cepControllerEhProprio) _cepController.dispose();
    _nomeController.dispose();
    _telefoneController.dispose();
    _cepTextController.dispose();
    _logradouroController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
    _estadoController.dispose();
    _logradouroFocusNode.dispose();
    super.dispose();
  }

  /// Mesmo padrão de `CadastroPage._onCadastroStateChanged` — preenche os
  /// campos de endereço quando o ViaCEP responde com sucesso, e move o
  /// foco pro Logradouro (item 2 da tarefa) pra o usuário completar número/
  /// complemento direto ali.
  void _onCepStateChanged() {
    final cepModel = _cepController.value.cepModel;
    if (_cepController.value.isSuccess && cepModel != null) {
      _logradouroController.text = cepModel.logradouro;
      _bairroController.text = cepModel.bairro;
      _cidadeController.text = cepModel.localidade;
      _estadoController.text = cepModel.uf;
      _logradouroFocusNode.requestFocus();
    }
    setState(() {});
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
        _telefoneController.text = perfilConta?.telefone ?? '';
        _cepTextController.text = perfilConta?.cep ?? '';
        _logradouroController.text = perfilConta?.logradouro ?? '';
        _bairroController.text = perfilConta?.bairro ?? '';
        _cidadeController.text = perfilConta?.cidade ?? '';
        _estadoController.text = perfilConta?.estado ?? '';
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

  String? _validarTelefone(String? valor) {
    if ((valor ?? '').trim().isEmpty) {
      return i18n.tr('auth.phone_required');
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

  String? _validarCampoEndereco(String? valor) {
    if ((valor ?? '').trim().isEmpty) {
      return i18n.tr('meu_perfil.endereco_validation_empty');
    }
    return null;
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _salvando = true);
    try {
      final cepDigitos = _cepTextController.text.replaceAll(RegExp(r'\D'), '');
      await _repository.atualizarDadosConta(
        nome: _nomeController.text.trim(),
        telefone: _telefoneController.text.trim(),
        cep: cepDigitos,
        logradouro: _logradouroController.text.trim(),
        bairro: _bairroController.text.trim(),
        cidade: _cidadeController.text.trim(),
        estado: _estadoController.text.trim(),
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
                    controller: _telefoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: i18n.tr('auth.phone_label'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: _validarTelefone,
                    enabled: !_salvando,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cepTextController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: i18n.tr('meu_perfil.cep_label'),
                      hintText: i18n.tr('meu_perfil.cep_hint'),
                      border: const OutlineInputBorder(),
                      suffixIcon: _cepController.value.isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    validator: _validarCep,
                    enabled: !_salvando,
                    // RELATÓRIO 20261016_0009 (item 2) — mesma lógica de
                    // `CadastroController.onCepChanged`: só dispara a busca
                    // ViaCEP de verdade quando chega a exatamente 8 dígitos.
                    onChanged: _cepController.onCepChanged,
                  ),
                  if (_cepController.value.isError) ...[
                    const SizedBox(height: 4),
                    Text(
                      i18n.tr('auth.cep_invalid'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _logradouroController,
                    focusNode: _logradouroFocusNode,
                    decoration: InputDecoration(
                      labelText: i18n.tr('auth.street_label'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: _validarCampoEndereco,
                    enabled: !_salvando,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bairroController,
                    decoration: InputDecoration(
                      labelText: i18n.tr('auth.neighborhood_label'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: _validarCampoEndereco,
                    enabled: !_salvando,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _cidadeController,
                          decoration: InputDecoration(
                            labelText: i18n.tr('auth.city_label'),
                            border: const OutlineInputBorder(),
                          ),
                          validator: _validarCampoEndereco,
                          enabled: !_salvando,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _estadoController,
                          decoration: InputDecoration(
                            labelText: i18n.tr('auth.state_label'),
                            border: const OutlineInputBorder(),
                          ),
                          validator: _validarCampoEndereco,
                          enabled: !_salvando,
                        ),
                      ),
                    ],
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
