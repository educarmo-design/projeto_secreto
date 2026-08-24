import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../dashboard/data/repositories/perfil_usuario_repository.dart';
import '../../data/repositories/coleta_diaria_repository.dart';

enum _CargaStatus { carregando, sucesso, erro }

/// N16 (Documento Mestre v7.0, Parte V1.I) — Hidratação: registro em ml, por
/// copo (padrão 200 ml, CONFIGURÁVEL), histórico diário, widget no
/// dashboard (ver [DashboardWidgetId.hidratacao]/[HidratacaoCard]). Grava em
/// `coleta_diaria` (EAV, `atributo = 'agua_ml'`) via [ColetaDiariaRepository]
/// — não precisou de tabela nova, ver comentário de cabeçalho da migration
/// `20260819160000_n16_hidratacao_tamanho_copo.sql`.
///
/// Regra 14 (Parte 0): "Validação = completa funcionalmente, crua
/// visualmente" — botão "+1 copo", campo de quantidade avulsa, lista de
/// histórico crua, sem gráfico/gauge. Mesmo padrão de
/// [PerfilUsuarioPage]/[HistoricoTreinosPage]: `Navigator.push`, tela
/// secundária fora do roteador enxuto.
class RegistroHidratacaoPage extends StatefulWidget {
  const RegistroHidratacaoPage({
    super.key,
    ColetaDiariaRepository? coletaRepository,
    PerfilUsuarioRepository? perfilRepository,
  })  : _coletaRepository = coletaRepository,
        _perfilRepository = perfilRepository;

  final ColetaDiariaRepository? _coletaRepository;
  final PerfilUsuarioRepository? _perfilRepository;

  @override
  State<RegistroHidratacaoPage> createState() => _RegistroHidratacaoPageState();
}

class _RegistroHidratacaoPageState extends State<RegistroHidratacaoPage> {
  late final ColetaDiariaRepository _coletaRepository =
      widget._coletaRepository ?? ColetaDiariaRepository();
  late final PerfilUsuarioRepository _perfilRepository =
      widget._perfilRepository ?? PerfilUsuarioRepository();

  final _quantidadeController = TextEditingController();
  final _tamanhoCopoController = TextEditingController();
  final _formKeyQuantidade = GlobalKey<FormState>();
  final _formKeyTamanhoCopo = GlobalKey<FormState>();

  _CargaStatus _status = _CargaStatus.carregando;
  bool _registrando = false;
  bool _salvandoTamanhoCopo = false;

  int _totalHojeMl = 0;
  int _tamanhoCopoMl = 200;
  List<HidratacaoDia> _historico = const [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _quantidadeController.dispose();
    _tamanhoCopoController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final total = await _coletaRepository.buscarTotalAguaDoDia();
      final tamanhoCopo = await _perfilRepository.buscarTamanhoCopoMl();
      final historico = await _coletaRepository.buscarHistoricoAgua();
      if (!mounted) return;
      _tamanhoCopoController.text = tamanhoCopo.toString();
      setState(() {
        _totalHojeMl = total;
        _tamanhoCopoMl = tamanhoCopo;
        _historico = historico;
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  void _mostrarSnack(String mensagem, {required bool sucesso}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensagem),
          backgroundColor: sucesso ? AppColors.success : AppColors.error,
        ),
      );
  }

  Future<void> _registrar(int mililitros) async {
    setState(() => _registrando = true);
    final resultado = await _coletaRepository.gravarAgua(mililitros: mililitros);
    if (!mounted) return;
    setState(() => _registrando = false);

    if (resultado.success) {
      _quantidadeController.clear();
      _mostrarSnack(i18n.tr('hidratacao.registro_sucesso'), sucesso: true);
      // Sempre um SELECT novo, nunca soma otimista no client — mesmo
      // princípio de [HistoricoTelemetriaPage]/[TreinosHistoricoRepository]:
      // reflete o estado real do servidor, não o que este botão específico
      // acabou de mandar.
      await _carregar();
    } else {
      _mostrarSnack(
        resultado.errorMessage ?? i18n.tr('hidratacao.registro_erro'),
        sucesso: false,
      );
    }
  }

  String? _validarQuantidade(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return null; // campo opcional — só valida se preenchido
    final numero = int.tryParse(texto);
    if (numero == null) {
      return i18n.tr('hidratacao.quantidade_validation_invalid');
    }
    if (numero < 1 || numero > 5000) {
      return i18n.tr('hidratacao.quantidade_validation_range');
    }
    return null;
  }

  Future<void> _adicionarQuantidadeCustomizada() async {
    if (!(_formKeyQuantidade.currentState?.validate() ?? false)) return;
    final texto = _quantidadeController.text.trim();
    if (texto.isEmpty) return;
    await _registrar(int.parse(texto));
  }

  String? _validarTamanhoCopo(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) {
      return i18n.tr('hidratacao.quantidade_validation_invalid');
    }
    final numero = int.tryParse(texto);
    if (numero == null) {
      return i18n.tr('hidratacao.quantidade_validation_invalid');
    }
    // 50–1000 ml: faixa plausível de copo/garrafa, só pra pegar erro de
    // digitação grosseiro — mesmo espírito de PerfilUsuarioPage._validarAltura.
    if (numero < 50 || numero > 1000) {
      return i18n.tr('hidratacao.tamanho_copo_validation_range');
    }
    return null;
  }

  Future<void> _salvarTamanhoCopo() async {
    if (!(_formKeyTamanhoCopo.currentState?.validate() ?? false)) return;
    final novoTamanho = int.parse(_tamanhoCopoController.text.trim());

    setState(() => _salvandoTamanhoCopo = true);
    try {
      await _perfilRepository.atualizarTamanhoCopoMl(novoTamanho);
      if (!mounted) return;
      setState(() => _tamanhoCopoMl = novoTamanho);
      _mostrarSnack(i18n.tr('perfil_fisico.save_success'), sucesso: true);
    } catch (_) {
      if (!mounted) return;
      _mostrarSnack(i18n.tr('perfil_fisico.save_error'), sucesso: false);
    } finally {
      if (mounted) setState(() => _salvandoTamanhoCopo = false);
    }
  }

  static String _dataFormatada(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('hidratacao.title'))),
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
                  i18n.tr('hidratacao.load_error'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _carregar,
                  child: Text(i18n.tr('hidratacao.retry_button')),
                ),
              ],
            ),
          ),
        );
      case _CargaStatus.sucesso:
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              i18n.tr('hidratacao.subtitle'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.mutedText),
            ),
            const SizedBox(height: 16),
            Text(
              i18n.tr('hidratacao.total_hoje', params: {'total': _totalHojeMl.toString()}),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.local_drink_outlined),
              label: Text(
                i18n.tr(
                  'hidratacao.adicionar_copo_button',
                  params: {'ml': _tamanhoCopoMl.toString()},
                ),
              ),
              onPressed: _registrando ? null : () => _registrar(_tamanhoCopoMl),
            ),
            const SizedBox(height: 24),
            Form(
              key: _formKeyQuantidade,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quantidadeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: i18n.tr('hidratacao.quantidade_customizada_label'),
                        hintText: i18n.tr('hidratacao.quantidade_customizada_hint'),
                        suffixText: 'ml',
                        border: const OutlineInputBorder(),
                      ),
                      validator: _validarQuantidade,
                      enabled: !_registrando,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: OutlinedButton(
                      onPressed: _registrando ? null : _adicionarQuantidadeCustomizada,
                      child: Text(i18n.tr('hidratacao.adicionar_button')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(i18n.tr('hidratacao.historico_title'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_historico.isEmpty)
              Text(
                i18n.tr('hidratacao.historico_vazio'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.mutedText),
              )
            else
              for (final dia in _historico)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${_dataFormatada(dia.data)}: ${dia.totalMl} ml',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 8),
            Form(
              key: _formKeyTamanhoCopo,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tamanhoCopoController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: i18n.tr('hidratacao.tamanho_copo_label'),
                        hintText: i18n.tr('hidratacao.tamanho_copo_hint'),
                        suffixText: 'ml',
                        border: const OutlineInputBorder(),
                      ),
                      validator: _validarTamanhoCopo,
                      enabled: !_salvandoTamanhoCopo,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: OutlinedButton(
                      onPressed: _salvandoTamanhoCopo ? null : _salvarTamanhoCopo,
                      child: Text(i18n.tr('hidratacao.salvar_tamanho_copo_button')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }
}
