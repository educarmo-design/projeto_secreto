import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../vinculos/data/services/vinculos_service.dart';
import '../../data/repositories/anamnese_repository.dart';
import '../../data/repositories/meta_bem_estar_repository.dart';
import '../widgets/meta_bloqueio_modal.dart';
import '../widgets/motor_metabolico_resultado_view.dart';
import 'anamnese_detalhes_page.dart';

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
  const ResultadoMotorMetabolicoPage({
    super.key,
    required this.anamneseId,
    MetaBemEstarRepository? repository,
    AnamneseRepository? anamneseRepository,
    VinculosService? vinculosService,
  })  : _repository = repository,
        _anamneseRepository = anamneseRepository,
        _vinculosService = vinculosService;

  /// RELATÓRIO 20261102_0003 — id da anamnese que originou este cálculo
  /// (devolvido agora por [AnamneseRepository.salvarAnamnese]), usado pra
  /// navegar até [AnamneseDetalhesPage] dela — "Ver Resultado da
  /// Prescrição" e ao concluir o fluxo (salvando a meta ou pulando).
  final String anamneseId;
  final MetaBemEstarRepository? _repository;

  /// Repassados direto pra [AnamneseDetalhesPage] na navegação — mesmo
  /// motivo de todo outro parâmetro opcional deste arquivo: permitir
  /// injeção de mocks em teste, sem mudar nada em produção (`null` cai no
  /// default real de [AnamneseDetalhesPage]).
  final AnamneseRepository? _anamneseRepository;
  final VinculosService? _vinculosService;

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

  /// RELATÓRIO 20260920 (item 3) — protocolo de macros escolhido pelo
  /// usuário pra AJUDAR a preencher Proteína/Carboidrato/Gordura
  /// (`'MACRO-001'|'MACRO-002'|'MACRO-003'|null`). Só um atalho de
  /// preenchimento: os campos continuam editáveis e nada é salvo até o
  /// usuário tocar em "Salvar Minha Meta" (ME-005).
  String? _protocoloSelecionado;

  @override
  void initState() {
    super.initState();
    _carregar();
    _caloriasController.addListener(_recalcularProtocoloSelecionado);
  }

  @override
  void dispose() {
    _caloriasController.removeListener(_recalcularProtocoloSelecionado);
    _caloriasController.dispose();
    _proteinaController.dispose();
    _carboController.dispose();
    _gorduraController.dispose();
    super.dispose();
  }

  /// RELATÓRIO 20260920 (item 3) — converte os percentuais/g-por-kg do
  /// protocolo selecionado ([_protocoloSelecionado]) em gramas finais,
  /// usando exatamente os `parametros` versionados que a RPC devolveu
  /// (nunca um número reinventado no app) aplicados sobre o que estiver
  /// digitado em Calorias agora. `null` quando falta um pré-requisito
  /// (protocolo indisponível, Calorias vazio/inválido, peso/massa magra
  /// ausentes) — nesse caso os campos de macro não são tocados.
  Map<String, double>? _calcularGramasProtocolo(String protocolo, double caloriasAlvo) {
    final macros = _resultado?.macrosRecomendados;
    if (macros == null) return null;
    final pesoKg = _resultado?.pesoKg;
    final massaMagraKg = _resultado?.massaMagraKg;

    switch (protocolo) {
      case 'MACRO-001':
        final p = macros.macro001.parametros;
        final pctProteina = (p['percentual_proteina'] as num?)?.toDouble();
        final pctCarboidrato = (p['percentual_carboidrato'] as num?)?.toDouble();
        final pctGordura = (p['percentual_gordura'] as num?)?.toDouble();
        if (pctProteina == null || pctCarboidrato == null || pctGordura == null) return null;
        return {
          'proteina': caloriasAlvo * pctProteina / 4,
          'carboidrato': caloriasAlvo * pctCarboidrato / 4,
          'gordura': caloriasAlvo * pctGordura / 9,
        };
      case 'MACRO-002':
        if (pesoKg == null) return null;
        final p = macros.macro002.parametros;
        final gPorKgProteina = (p['proteina_g_por_kg'] as num?)?.toDouble();
        final gPorKgGordura = (p['gordura_g_por_kg'] as num?)?.toDouble();
        if (gPorKgProteina == null || gPorKgGordura == null) return null;
        final proteinaG = pesoKg * gPorKgProteina;
        final gorduraG = pesoKg * gPorKgGordura;
        return {
          'proteina': proteinaG,
          'carboidrato': (caloriasAlvo - proteinaG * 4 - gorduraG * 9) / 4,
          'gordura': gorduraG,
        };
      case 'MACRO-003':
        if (!macros.macro003.disponivel || pesoKg == null || massaMagraKg == null) return null;
        final p = macros.macro003.parametros;
        final gPorKgMlg = (p['proteina_g_por_kg_mlg'] as num?)?.toDouble();
        final gPorKgGordura = (p['gordura_g_por_kg_peso'] as num?)?.toDouble();
        if (gPorKgMlg == null || gPorKgGordura == null) return null;
        final proteinaG = massaMagraKg * gPorKgMlg;
        final gorduraG = pesoKg * gPorKgGordura;
        return {
          'proteina': proteinaG,
          'carboidrato': (caloriasAlvo - proteinaG * 4 - gorduraG * 9) / 4,
          'gordura': gorduraG,
        };
      case 'MACRO-004':
        // RELATÓRIO 20261103_0002 — proteína prioritária (g/kg) + gordura
        // por percentual mínimo da própria energia-alvo digitada +
        // carboidrato residual (mesma fórmula da RPC, `20260920100000`).
        if (pesoKg == null) return null;
        final p = macros.macro004.parametros;
        final gPorKgProteina = (p['proteina_g_por_kg'] as num?)?.toDouble();
        final pctMinimoGordura = (p['gordura_percentual_minimo'] as num?)?.toDouble();
        if (gPorKgProteina == null || pctMinimoGordura == null) return null;
        final proteinaG = pesoKg * gPorKgProteina;
        final gorduraG = (caloriasAlvo * pctMinimoGordura) / 9;
        return {
          'proteina': proteinaG,
          'carboidrato': (caloriasAlvo - proteinaG * 4 - gorduraG * 9) / 4,
          'gordura': gorduraG,
        };
      default:
        return null;
    }
  }

  void _recalcularProtocoloSelecionado() {
    final protocolo = _protocoloSelecionado;
    if (protocolo == null) return;
    final calorias = double.tryParse(_caloriasController.text.trim());
    if (calorias == null || calorias <= 0) return;

    final gramas = _calcularGramasProtocolo(protocolo, calorias);
    if (gramas == null) return;

    _proteinaController.text = gramas['proteina']!.round().toString();
    _carboController.text = gramas['carboidrato']!.round().toString();
    _gorduraController.text = gramas['gordura']!.round().toString();
  }

  void _selecionarProtocolo(String? protocolo) {
    setState(() => _protocoloSelecionado = protocolo);
    if (protocolo != null) _recalcularProtocoloSelecionado();
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

  /// RELATÓRIO 20261102_0003 (ACEITE 2 — "ao concluir, leva o usuário
  /// para a tela de resultado da prescrição") — substitui o antigo
  /// `_fecharFluxo` (`pop(); pop();`, que fechava o fluxo inteiro sem
  /// mostrar nada): achado real em device físico, o fundador não
  /// conseguia acessar/visualizar o resultado completo da anamnese que
  /// acabara de concluir. Agora, ao salvar a meta OU pular ("Definir
  /// Depois"), o app SUBSTITUI esta tela por [AnamneseDetalhesPage] da
  /// anamnese recém-criada — mesma profundidade de pilha de antes (troca
  /// só o topo), mostrando o formulário completo + o card do Motor
  /// Metabólico/Plano de Metas vinculado por FK (`anamnese_id`, RELATÓRIO
  /// 20261102_0002) — inclusive a meta que acabou de ser salva, se foi o
  /// caso.
  void _irParaResultadoCompleto() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AnamneseDetalhesPage(
          anamneseId: widget.anamneseId,
          repository: widget._anamneseRepository,
          metaRepository: _repository,
          vinculosService: widget._vinculosService,
        ),
      ),
    );
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
      _irParaResultadoCompleto();
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
          // RELATÓRIO 20261103_0001 — extraída pra [MotorMetabolicoResultadoView],
          // reaproveitada também por [AnamneseDetalhesPage].
          // RELATÓRIO 20261103_0002 (item 2) — `mostrarMacrosRecomendados:
          // true` liga o comparativo de TODOS os protocolos aqui também
          // (antes só na tela de Detalhes); o seletor INTERATIVO da Seção
          // B abaixo continua só pra "escolher 1 e preencher os campos",
          // função diferente — nenhum dos dois substitui o outro.
          MotorMetabolicoResultadoView(resultado: resultado, mostrarMacrosRecomendados: true),
          const SizedBox(height: 16),
          // RELATÓRIO 20261102_0003 (ACEITE 2) — ação primária, sempre
          // visível, pra ver o resultado completo da anamnese que acabou
          // de ser enviada SEM precisar passar pelo formulário de meta
          // abaixo (Seção B é opcional — o usuário pode pular pra ver o
          // registro completo direto).
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AnamneseDetalhesPage(
                  anamneseId: widget.anamneseId,
                  repository: widget._anamneseRepository,
                  metaRepository: _repository,
                  vinculosService: widget._vinculosService,
                ),
              ),
            ),
            child: Text(i18n.tr('nutricao.resultado_motor_ver_prescricao_button')),
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
          if (resultado.macrosRecomendados != null) ...[
            const SizedBox(height: 16),
            _buildProtocoloSelector(context, resultado.macrosRecomendados!),
          ],
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
            onPressed: _salvandoMeta ? null : _irParaResultadoCompleto,
            child: Text(i18n.tr('nutricao.resultado_motor_meta_definir_depois_button')),
          ),
        ],
      ),
    );
  }

  /// RELATÓRIO 20260920 (item 3, ACEITE) — seletor de MACRO-001/002/003
  /// na Seção B: ao escolher, converte os percentuais/g-por-kg em gramas
  /// finais e preenche Proteína/Carboidrato/Gordura — só um atalho de
  /// preenchimento, os campos continuam editáveis (ME-005).
  Widget _buildProtocoloSelector(BuildContext context, MacrosRecomendadosResultado macros) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.resultado_motor_protocolo_titulo'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          i18n.tr('nutricao.resultado_motor_protocolo_aviso'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(i18n.tr('nutricao.resultado_motor_protocolo_nenhum')),
              selected: _protocoloSelecionado == null,
              onSelected: _salvandoMeta ? null : (_) => _selecionarProtocolo(null),
            ),
            ChoiceChip(
              label: Text(i18n.tr('nutricao.resultado_motor_protocolo_001')),
              selected: _protocoloSelecionado == 'MACRO-001',
              onSelected: _salvandoMeta ? null : (_) => _selecionarProtocolo('MACRO-001'),
            ),
            ChoiceChip(
              label: Text(i18n.tr('nutricao.resultado_motor_protocolo_002')),
              selected: _protocoloSelecionado == 'MACRO-002',
              onSelected: _salvandoMeta ? null : (_) => _selecionarProtocolo('MACRO-002'),
            ),
            Tooltip(
              message: macros.macro003.disponivel ? '' : i18n.tr('nutricao.resultado_motor_protocolo_003_indisponivel'),
              child: ChoiceChip(
                label: Text(i18n.tr('nutricao.resultado_motor_protocolo_003')),
                selected: _protocoloSelecionado == 'MACRO-003',
                onSelected: (_salvandoMeta || !macros.macro003.disponivel)
                    ? null
                    : (_) => _selecionarProtocolo('MACRO-003'),
              ),
            ),
            // RELATÓRIO 20261103_0002 — MACRO-004 sempre disponível (sem
            // pré-requisito de composição corporal, diferente do MACRO-003).
            ChoiceChip(
              label: Text(i18n.tr('nutricao.resultado_motor_protocolo_004')),
              selected: _protocoloSelecionado == 'MACRO-004',
              onSelected: _salvandoMeta ? null : (_) => _selecionarProtocolo('MACRO-004'),
            ),
          ],
        ),
        if (_protocoloSelecionado != null && double.tryParse(_caloriasController.text.trim()) == null) ...[
          const SizedBox(height: 4),
          Text(
            i18n.tr('nutricao.resultado_motor_protocolo_calorias_necessarias'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.warning),
          ),
        ],
      ],
    );
  }
}
