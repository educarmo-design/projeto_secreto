import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/meta_bem_estar_repository.dart';
import '../widgets/meta_bloqueio_modal.dart';

enum _CargaStatus { carregando, erro, sucesso }

/// RELATÓRIO 20260917 (item 2 — "Tela Final: Separação de Cálculo vs
/// Meta", ME-005/ME-006, docs/motor_metabolico.txt) — reescrita completa
/// sobre a v1 (RELATÓRIO 20260915_0003): passa a chamar
/// `calcular_motor_metabolico_v1` (RELATÓRIO 20260916_0001, o Motor
/// Centralizado) em vez de `gerar_sugestao_meta`, e ganha DUAS seções
/// visuais claramente separadas:
///
///   A. Resultados Calculados (SÓ LEITURA) — TMB + TDEE médio, com aviso
///      explícito de que são valores informativos calculados pelo motor.
///   B. Minha Meta Diária (EDITÁVEL) — 4 campos EM BRANCO (Calorias/
///      Proteína/Carboidrato/Gordura). O USUÁRIO preenche; o app nunca
///      pré-calcula nem sugere um valor aqui (Restrição da tarefa: "O app
///      não pode calcular macronutrientes automaticamente e salvar como
///      meta"). "Salvar Minha Meta" grava via `validar_e_salvar_meta`
///      (Motor de Exceções N08, mesmo caminho de [MetaBemEstarPage]) como
///      a meta `tipo_dia = 'PADRAO'` — uma meta média replicada pros 7
///      dias da semana, exatamente como o documento pede pra usuário sem
///      acompanhamento profissional (Seção 23).
///
/// Regra 14 (Parte 0): "Validação = completa funcionalmente, crua
/// visualmente" — sem carrossel/ilustração.
class ResultadoMotorMetabolicoPage extends StatefulWidget {
  const ResultadoMotorMetabolicoPage({super.key, MetaBemEstarRepository? repository})
      : _repository = repository;

  final MetaBemEstarRepository? _repository;

  @override
  State<ResultadoMotorMetabolicoPage> createState() => _ResultadoMotorMetabolicoPageState();
}

class _ResultadoMotorMetabolicoPageState extends State<ResultadoMotorMetabolicoPage> {
  late final MetaBemEstarRepository _repository = widget._repository ?? MetaBemEstarRepository();

  final _formKey = GlobalKey<FormState>();
  final _caloriasController = TextEditingController();
  final _proteinaController = TextEditingController();
  final _carboController = TextEditingController();
  final _gorduraController = TextEditingController();

  _CargaStatus _status = _CargaStatus.carregando;
  bool _salvandoMeta = false;
  MotorMetabolicoV1Resultado? _resultado;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _caloriasController.dispose();
    _proteinaController.dispose();
    _carboController.dispose();
    _gorduraController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final resultado = await _repository.calcularMotorMetabolicoV1();
      if (!mounted) return;
      setState(() {
        _resultado = resultado;
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  /// Fecha esta tela E a Anamnese logo abaixo dela na pilha — depois de
  /// concluir o fluxo inteiro (Anamnese salva + resultado visto/meta
  /// definida ou pulada), voltar pra um formulário já enviado não faz
  /// sentido; o usuário volta direto pra tela que abriu a Anamnese
  /// (Configurações de Perfil).
  void _fecharFluxo() {
    Navigator.of(context)
      ..pop()
      ..pop();
  }

  int? _parseOpcional(String texto) {
    final limpo = texto.trim();
    return limpo.isEmpty ? null : int.tryParse(limpo);
  }

  String? _validarCalorias(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return i18n.tr('nutricao.meta_calorias_validation_empty');
    final numero = int.tryParse(texto);
    if (numero == null || numero <= 0) return i18n.tr('nutricao.meta_calorias_validation_invalid');
    return null;
  }

  /// Grava a meta que o USUÁRIO digitou (nunca um valor calculado pelo
  /// motor) via `validar_e_salvar_meta` — mesmo Motor de Exceções N08 de
  /// [MetaBemEstarPage]. Se bloqueado (trava clínica/carência/prioridade
  /// profissional), mostra o mesmo modal vermelho compartilhado.
  Future<void> _salvarMeta() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _salvandoMeta = true);
    try {
      await _repository.salvarMeta(
        caloriasAlvo: int.parse(_caloriasController.text.trim()),
        proteinaG: _parseOpcional(_proteinaController.text),
        carboG: _parseOpcional(_carboController.text),
        gorduraG: _parseOpcional(_gorduraController.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('nutricao.meta_save_success')),
            backgroundColor: AppColors.success,
          ),
        );
      _fecharFluxo();
    } on MetaBloqueadaException catch (erro) {
      if (!mounted) return;
      await mostrarModalBloqueioMeta(context, erro);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('nutricao.meta_save_error')),
            backgroundColor: AppColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _salvandoMeta = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('nutricao.resultado_motor_title'))),
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
                  i18n.tr('nutricao.resultado_motor_erro'),
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
        return _buildResultado(context, _resultado!);
    }
  }

  Widget _buildResultado(BuildContext context, MotorMetabolicoV1Resultado resultado) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ─── Seção A — Resultados Calculados (SÓ LEITURA) ───
          Text(
            i18n.tr('nutricao.resultado_motor_secao_calculo_titulo'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            i18n.tr('nutricao.resultado_motor_secao_calculo_aviso'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 16),
          Text(i18n.tr('nutricao.resultado_motor_media_label'), style: Theme.of(context).textTheme.titleMedium),
          Text(
            resultado.tdeeMedio == null
                ? i18n.tr('nutricao.resultado_motor_sem_dado')
                : '${resultado.tdeeMedio!.round()} kcal',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (resultado.tmb != null) ...[
            const SizedBox(height: 16),
            Text(i18n.tr('nutricao.resultado_motor_tmb_label'), style: Theme.of(context).textTheme.titleSmall),
            Text('${resultado.tmb!.round()} kcal', style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (resultado.avisos.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final aviso in resultado.avisos)
              Text('• $aviso', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText)),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              border: Border.all(color: AppColors.error),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              i18n.tr('nutricao.resultado_motor_aviso_disclaimer'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.error, fontWeight: FontWeight.w600),
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),

          // ─── Seção B — Minha Meta Diária (EDITÁVEL pelo usuário) ───
          Text(
            i18n.tr('nutricao.resultado_motor_secao_meta_titulo'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            i18n.tr('nutricao.resultado_motor_secao_meta_aviso'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _caloriasController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: i18n.tr('nutricao.meta_calorias_label'),
              suffixText: 'kcal',
              border: const OutlineInputBorder(),
            ),
            validator: _validarCalorias,
            enabled: !_salvandoMeta,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _proteinaController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: i18n.tr('nutricao.meta_proteina_label'),
              suffixText: 'g',
              border: const OutlineInputBorder(),
            ),
            enabled: !_salvandoMeta,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _carboController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: i18n.tr('nutricao.meta_carbo_label'),
              suffixText: 'g',
              border: const OutlineInputBorder(),
            ),
            enabled: !_salvandoMeta,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _gorduraController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: i18n.tr('nutricao.meta_gordura_label'),
              suffixText: 'g',
              border: const OutlineInputBorder(),
            ),
            enabled: !_salvandoMeta,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _salvandoMeta ? null : _salvarMeta,
            child: _salvandoMeta
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(i18n.tr('nutricao.resultado_motor_meta_salvar_button')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _salvandoMeta ? null : _fecharFluxo,
            child: Text(i18n.tr('nutricao.resultado_motor_meta_definir_depois_button')),
          ),
        ],
      ),
    );
  }
}
