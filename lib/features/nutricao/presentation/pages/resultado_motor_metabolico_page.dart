import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/meta_bem_estar_repository.dart';

enum _CargaStatus { carregando, erro, sucesso }

/// RELATÓRIO 20260915_0003 — Tela de Resultado do Motor Metabólico, aberta
/// logo após salvar a Anamnese Self-Service (item 2 da tarefa). Chama
/// `gerar_sugestao_meta` (RELATÓRIO 20260915_0002) e exibe: TDEE médio da
/// semana ("Sugestão de Meta: Gasto calórico", a MÉDIA pedida pelo
/// fundador) + TMB informativo + detalhe por dia da semana.
///
/// NÃO inventa um split de macronutrientes (proteína/carbo/gordura) —
/// `gerar_sugestao_meta` não calcula isso (só TMB/TDEE, ver a migration
/// `20260915120000`), e este app nunca arbitra um número clínico sem uma
/// fórmula explícita do fundador (mesmo espírito das travas N08). Ausência
/// documentada, não esquecimento — ver o relatório desta tarefa.
///
/// Esta tela é só EXIBIÇÃO: nunca chama `validar_e_salvar_meta` nem grava
/// em `objetivos_alimentares` — o aviso legal abaixo do resultado deixa
/// isso explícito pro usuário (texto exato pedido pelo fundador).
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

  _CargaStatus _status = _CargaStatus.carregando;
  SugestaoMetaResultado? _resultado;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final resultado = await _repository.gerarSugestaoMeta();
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
  /// concluir o fluxo inteiro (Anamnese salva + resultado visto), voltar
  /// pra um formulário já enviado não faz sentido; o usuário volta direto
  /// pra tela que abriu a Anamnese (Configurações de Perfil).
  void _concluir() {
    Navigator.of(context)
      ..pop()
      ..pop();
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

  Widget _buildResultado(BuildContext context, SugestaoMetaResultado resultado) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(i18n.tr('nutricao.resultado_motor_media_label'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          resultado.tdeeMedio == null
              ? i18n.tr('nutricao.resultado_motor_sem_dado')
              : '${resultado.tdeeMedio!.round()} kcal',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if (resultado.tmb != null) ...[
          const SizedBox(height: 24),
          Text(i18n.tr('nutricao.resultado_motor_tmb_label'), style: Theme.of(context).textTheme.titleSmall),
          Text('${resultado.tmb!.round()} kcal', style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 24),
        Text(i18n.tr('nutricao.resultado_motor_detalhe_label'), style: Theme.of(context).textTheme.titleMedium),
        for (var dia = 0; dia <= 6; dia++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(i18n.tr('nutricao.dia_semana_$dia')),
            trailing: Text(
              resultado.tdeePorDia[dia] == null
                  ? i18n.tr('nutricao.resultado_motor_sem_dado')
                  : '${resultado.tdeePorDia[dia]!.round()} kcal',
            ),
          ),
        if (resultado.avisos.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final aviso in resultado.avisos)
            Text('• $aviso', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText)),
        ],
        const SizedBox(height: 24),
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
        const SizedBox(height: 24),
        FilledButton(onPressed: _concluir, child: Text(i18n.tr('nutricao.resultado_motor_concluir_button'))),
      ],
    );
  }
}
