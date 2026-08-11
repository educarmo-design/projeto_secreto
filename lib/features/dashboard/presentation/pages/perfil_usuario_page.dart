import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/perfil_usuario_repository.dart';

enum _CargaStatus { carregando, sucesso, erro }

/// Tela de Perfil do Usuário (RELATÓRIO 20260810_0006, decisão do
/// fundador) — hoje só edita `altura_cm`. Existe para resolver um problema
/// concreto encontrado no teste físico: o IMC não calculava porque
/// `perfis_usuarios.altura_cm` estava vazio, e o fundador decidiu que o
/// caminho certo é o próprio usuário preencher pelo app, não alguém
/// injetar o valor via SQL manual.
///
/// Regra 14 (Parte 0): "Validação = completa funcionalmente, crua
/// visualmente" — um `TextFormField` numérico, um botão, um SnackBar de
/// confirmação. Sem card bonito, sem ilustração.
///
/// Aberta via [Navigator.push] a partir de [ConfiguracoesPerfilPage], mesmo
/// padrão de [TesteFrequenciaCardiacaPage]/[TestePesoPage]/[TesteSonoPage] —
/// tela secundária fora do roteador enxuto (ver app_router.dart), não uma
/// rota do GoRouter.
class PerfilUsuarioPage extends StatefulWidget {
  const PerfilUsuarioPage({super.key, PerfilUsuarioRepository? repository})
      : _repository = repository;

  final PerfilUsuarioRepository? _repository;

  @override
  State<PerfilUsuarioPage> createState() => _PerfilUsuarioPageState();
}

/// N03 (RELATÓRIO 20260811_0005, ajuste do fundador) — trava de maioridade
/// (18+), mesma aritmética de `calcular_idade()` no banco
/// (`20260811190000_n03_trava_maioridade.sql`) e de `calcularIdade()` no
/// Painel Web (`LoginPage.tsx`): anos completos entre a data e hoje.
int _idadeEmAnos(DateTime dataNascimento) {
  final hoje = DateTime.now();
  var idade = hoje.year - dataNascimento.year;
  final aindaNaoFezAniversarioEsteAno = hoje.month < dataNascimento.month ||
      (hoje.month == dataNascimento.month && hoje.day < dataNascimento.day);
  if (aindaNaoFezAniversarioEsteAno) idade -= 1;
  return idade;
}

const _idadeMinimaAnos = 18;

class _PerfilUsuarioPageState extends State<PerfilUsuarioPage> {
  late final PerfilUsuarioRepository _repository =
      widget._repository ?? PerfilUsuarioRepository();

  final _formKey = GlobalKey<FormState>();
  final _alturaController = TextEditingController();

  _CargaStatus _status = _CargaStatus.carregando;
  bool _salvando = false;

  /// `null` até o usuário escolher uma data nova ou uma já cadastrada ser
  /// carregada — distingue "ainda não mexeu no campo" (não reenviar nada
  /// no salvar) de "escolheu uma data".
  DateTime? _dataNascimentoSelecionada;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _alturaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final alturaCm = await _repository.buscarAlturaCm();
      final dataNascimento = await _repository.buscarDataNascimento();
      if (!mounted) return;
      // toStringAsFixed(0): altura_cm é numeric(5,1) no banco, mas o
      // teclado numérico simples não precisa mostrar ".0" pro caso comum
      // de uma altura inteira — quem digitar uma casa decimal continua
      // livre de fazer isso (ver keyboardType/inputFormatters abaixo).
      _alturaController.text = alturaCm == null
          ? ''
          : (alturaCm == alturaCm.roundToDouble()
              ? alturaCm.toStringAsFixed(0)
              : alturaCm.toStringAsFixed(1));
      setState(() {
        _dataNascimentoSelecionada = dataNascimento;
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  Future<void> _escolherDataNascimento() async {
    final hoje = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      // 100 anos atrás como limite inferior — generoso o bastante pra
      // nunca travar um caso real, sem deixar o seletor mostrar séculos
      // irrelevantes.
      firstDate: DateTime(hoje.year - 100),
      lastDate: hoje,
      initialDate: _dataNascimentoSelecionada ??
          DateTime(hoje.year - _idadeMinimaAnos, hoje.month, hoje.day),
    );
    if (escolhida == null || !mounted) return;
    setState(() => _dataNascimentoSelecionada = escolhida);
  }

  /// dd/mm/aaaa — sem `intl`, só concatenação com zero à esquerda (mesmo
  /// padrão simples já usado nesta tela para evitar dependência nova).
  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  String? _validarAltura(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) {
      return i18n.tr('perfil_fisico.altura_validation_empty');
    }
    final numero = double.tryParse(texto.replaceAll(',', '.'));
    if (numero == null) {
      return i18n.tr('perfil_fisico.altura_validation_invalid');
    }
    // 50–250 cm: faixa humana plausível, só para pegar erro de digitação
    // grosseiro (ex.: "1790" em vez de "179") — não é validação clínica.
    if (numero < 50 || numero > 250) {
      return i18n.tr('perfil_fisico.altura_validation_range');
    }
    return null;
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // N03 — validação de UX, espelhando a CHECK constraint
    // `perfis_usuarios_maioridade` do banco (a barreira real). Se o campo
    // nunca foi preenchido (usuário antigo, sem data de nascimento salva
    // ainda), não bloqueia o salvamento da altura — só valida quando há
    // uma data selecionada.
    final dataNascimento = _dataNascimentoSelecionada;
    if (dataNascimento != null &&
        _idadeEmAnos(dataNascimento) < _idadeMinimaAnos) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('perfil_fisico.data_nascimento_menor_idade')),
            backgroundColor: AppColors.error,
          ),
        );
      return;
    }

    final alturaCm =
        double.parse(_alturaController.text.trim().replaceAll(',', '.'));

    setState(() => _salvando = true);
    try {
      await _repository.atualizarAlturaCm(alturaCm);
      if (dataNascimento != null) {
        await _repository.atualizarDataNascimento(dataNascimento);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('perfil_fisico.save_success')),
            backgroundColor: AppColors.success,
          ),
        );
    } on PostgrestException catch (erro) {
      // A CHECK constraint `perfis_usuarios_maioridade` recusa o UPDATE se,
      // por algum motivo, a validação client-side acima foi contornada —
      // essa é a barreira real (Zero Trust), não a checagem em Dart.
      if (!mounted) return;
      final ehErroDeMaioridade =
          erro.message.contains('perfis_usuarios_maioridade');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              ehErroDeMaioridade
                  ? i18n.tr('perfil_fisico.data_nascimento_menor_idade')
                  : i18n.tr('perfil_fisico.save_error'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('perfil_fisico.save_error')),
            backgroundColor: AppColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('perfil_fisico.title'))),
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
                  i18n.tr('perfil_fisico.load_error'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _carregar,
                  child: Text(i18n.tr('perfil_fisico.save_button')),
                ),
              ],
            ),
          ),
        );
      case _CargaStatus.sucesso:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  i18n.tr('perfil_fisico.subtitle'),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.mutedText),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _alturaController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  // Impede letras (Restrição da tarefa) já na digitação, não
                  // só na validação — dígitos e, no máximo, um separador
                  // decimal (vírgula ou ponto).
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: i18n.tr('perfil_fisico.altura_label'),
                    hintText: i18n.tr('perfil_fisico.altura_hint'),
                    suffixText: 'cm',
                    border: const OutlineInputBorder(),
                  ),
                  validator: _validarAltura,
                  enabled: !_salvando,
                ),
                const SizedBox(height: 24),
                // N03 (RELATÓRIO 20260811_0005) — não é um TextFormField:
                // data de nascimento é sempre escolhida via showDatePicker
                // (evita todo o parsing/máscara de texto livre). Regra 14:
                // um InkWell cru com o rótulo + valor, sem card.
                InkWell(
                  onTap: _salvando ? null : _escolherDataNascimento,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: i18n.tr('perfil_fisico.data_nascimento_label'),
                      border: const OutlineInputBorder(),
                      enabled: !_salvando,
                    ),
                    child: Text(
                      _dataNascimentoSelecionada == null
                          ? i18n.tr('perfil_fisico.data_nascimento_hint')
                          : _formatarData(_dataNascimentoSelecionada!),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  i18n.tr('perfil_fisico.data_nascimento_ajuda'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.mutedText),
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
                      : Text(i18n.tr('perfil_fisico.save_button')),
                ),
              ],
            ),
          ),
        );
    }
  }
}
