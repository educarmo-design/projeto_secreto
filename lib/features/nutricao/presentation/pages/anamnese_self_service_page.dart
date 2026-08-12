import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/anamnese_models.dart';
import '../../data/repositories/anamnese_repository.dart';

enum _CargaStatus { carregando, sucesso, erro }

/// N09 (RELATÓRIO 20260811_0007) — Anamnese Nutricional Versionada,
/// preenchimento SELF-SERVICE pelo próprio atleta (sem tela equivalente no
/// Painel Web — restrição explícita desta tarefa, foco 100% mobile).
///
/// Regra 14 (Parte 0): "Validação = completa funcionalmente, crua
/// visualmente" — Radio/Checkbox/ListTile crus, sem carrossel/ilustração.
///
/// Salvar SEMPRE cria uma anamnese NOVA (nunca edita a anterior) — o
/// trigger `anamneses_trg_versionar` no banco vira a anterior pra
/// "historico" sozinho. Por isso esta tela pré-preenche com a anamnese
/// ATIVA (se existir) só pra conveniência de quem está atualizando, mas
/// "Salvar" nunca é um UPDATE.
class AnamneseSelfServicePage extends StatefulWidget {
  const AnamneseSelfServicePage({super.key, AnamneseRepository? repository})
      : _repository = repository;

  final AnamneseRepository? _repository;

  @override
  State<AnamneseSelfServicePage> createState() => _AnamneseSelfServicePageState();
}

const _objetivos = ['emagrecimento', 'manutencao', 'hipertrofia'];

class _AnamneseSelfServicePageState extends State<AnamneseSelfServicePage> {
  late final AnamneseRepository _repository = widget._repository ?? AnamneseRepository();

  _CargaStatus _status = _CargaStatus.carregando;
  bool _salvando = false;

  List<CatalogoItem> _problemasSaude = const [];
  List<CatalogoItem> _alergias = const [];
  List<TipoAtividadeItem> _tiposAtividades = const [];

  String? _objetivoSelecionado;
  final Set<String> _problemasSaudeSelecionados = {};
  final Set<String> _alergiasSelecionadas = {};
  final List<AtividadeSelecionada> _atividadesSelecionadas = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final problemasSaude = await _repository.buscarProblemasSaude();
      final alergias = await _repository.buscarAlergias();
      final tiposAtividades = await _repository.buscarTiposAtividades();
      final anamneseAtiva = await _repository.buscarAnamneseAtiva();

      if (!mounted) return;
      setState(() {
        _problemasSaude = problemasSaude;
        _alergias = alergias;
        _tiposAtividades = tiposAtividades;
        if (anamneseAtiva != null) {
          _objetivoSelecionado = anamneseAtiva.objetivoCodigo;
          _problemasSaudeSelecionados
            ..clear()
            ..addAll(anamneseAtiva.problemasSaudeIds);
          _alergiasSelecionadas
            ..clear()
            ..addAll(anamneseAtiva.alergiaIds);
          _atividadesSelecionadas
            ..clear()
            ..addAll(anamneseAtiva.atividades);
        }
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  Future<void> _abrirModalAdicionarAtividade() async {
    final disponiveis = _tiposAtividades
        .where((tipo) => !_atividadesSelecionadas.any((a) => a.atividadeId == tipo.id))
        .toList();

    if (disponiveis.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(i18n.tr('nutricao.atividades_todas_adicionadas'))));
      return;
    }

    final resultado = await showDialog<AtividadeSelecionada>(
      context: context,
      builder: (_) => _ModalAdicionarAtividade(opcoes: disponiveis),
    );

    if (resultado == null || !mounted) return;
    setState(() => _atividadesSelecionadas.add(resultado));
  }

  Future<void> _salvar() async {
    if (_objetivoSelecionado == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('nutricao.objetivo_obrigatorio')),
            backgroundColor: AppColors.error,
          ),
        );
      return;
    }

    setState(() => _salvando = true);
    try {
      await _repository.salvarAnamnese(
        objetivoCodigo: _objetivoSelecionado!,
        problemasSaudeIds: _problemasSaudeSelecionados.toList(),
        alergiaIds: _alergiasSelecionadas.toList(),
        atividades: _atividadesSelecionadas,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('nutricao.save_success')),
            backgroundColor: AppColors.success,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('nutricao.save_error')),
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
      appBar: AppBar(title: Text(i18n.tr('nutricao.anamnese_title'))),
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
                  i18n.tr('nutricao.load_error'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _carregar,
                  child: Text(i18n.tr('nutricao.save_button')),
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
              i18n.tr('nutricao.anamnese_subtitle'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
            ),
            const SizedBox(height: 24),
            _buildSecaoObjetivo(context),
            const SizedBox(height: 24),
            _buildSecaoMultiSelect(
              titulo: i18n.tr('nutricao.problemas_saude_label'),
              vazio: i18n.tr('nutricao.problemas_saude_empty'),
              itens: _problemasSaude,
              selecionados: _problemasSaudeSelecionados,
            ),
            const SizedBox(height: 24),
            _buildSecaoMultiSelect(
              titulo: i18n.tr('nutricao.alergias_label'),
              vazio: i18n.tr('nutricao.alergias_empty'),
              itens: _alergias,
              selecionados: _alergiasSelecionadas,
            ),
            const SizedBox(height: 24),
            _buildSecaoAtividades(context),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _salvando ? null : _salvar,
              child: _salvando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(i18n.tr('nutricao.save_button')),
            ),
          ],
        );
    }
  }

  Widget _buildSecaoObjetivo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.objetivo_label'), style: Theme.of(context).textTheme.titleMedium),
        RadioGroup<String>(
          groupValue: _objetivoSelecionado,
          onChanged: (valor) {
            if (_salvando) return;
            setState(() => _objetivoSelecionado = valor);
          },
          child: Column(
            children: [
              for (final objetivo in _objetivos)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: objetivo,
                  title: Text(i18n.tr('nutricao.objetivo_$objetivo')),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecaoMultiSelect({
    required String titulo,
    required String vazio,
    required List<CatalogoItem> itens,
    required Set<String> selecionados,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.titleMedium),
        if (itens.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(vazio, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText)),
          )
        else
          for (final item in itens)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: selecionados.contains(item.id),
              title: Text(item.nome),
              onChanged: _salvando
                  ? null
                  : (marcado) => setState(() {
                        if (marcado ?? false) {
                          selecionados.add(item.id);
                        } else {
                          selecionados.remove(item.id);
                        }
                      }),
            ),
      ],
    );
  }

  Widget _buildSecaoAtividades(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.atividades_label'), style: Theme.of(context).textTheme.titleMedium),
        if (_atividadesSelecionadas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              i18n.tr('nutricao.atividades_empty'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
            ),
          )
        else
          for (final atividade in _atividadesSelecionadas)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(atividade.nomeExibicao),
              subtitle: Text(
                i18n.tr('nutricao.atividades_minutos_por_dia', params: {
                  'minutos': atividade.minutosDiarios.toString(),
                }),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _salvando
                    ? null
                    : () => setState(() => _atividadesSelecionadas.remove(atividade)),
              ),
            ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _salvando ? null : _abrirModalAdicionarAtividade,
          icon: const Icon(Icons.add),
          label: Text(i18n.tr('nutricao.atividades_add_button')),
        ),
      ],
    );
  }
}

/// Modal "Adicionar Atividade" — dropdown de modalidade + input numérico de
/// minutos/dia. `StatefulWidget` próprio (não `StatefulBuilder` inline) só
/// pra manter o `TextEditingController` com ciclo de vida correto
/// (`dispose`), mesmo em um `showDialog`.
class _ModalAdicionarAtividade extends StatefulWidget {
  const _ModalAdicionarAtividade({required this.opcoes});

  final List<TipoAtividadeItem> opcoes;

  @override
  State<_ModalAdicionarAtividade> createState() => _ModalAdicionarAtividadeState();
}

class _ModalAdicionarAtividadeState extends State<_ModalAdicionarAtividade> {
  final _minutosController = TextEditingController();
  TipoAtividadeItem? _tipoSelecionado;
  String? _erroMinutos;

  @override
  void dispose() {
    _minutosController.dispose();
    super.dispose();
  }

  void _confirmar() {
    final tipo = _tipoSelecionado;
    final minutos = int.tryParse(_minutosController.text.trim());

    if (tipo == null || minutos == null || minutos <= 0 || minutos > 1440) {
      setState(() => _erroMinutos = i18n.tr('nutricao.atividades_modal_minutos_invalido'));
      return;
    }

    Navigator.of(context).pop(
      AtividadeSelecionada(
        atividadeId: tipo.id,
        nomeExibicao: tipo.nomeExibicao,
        minutosDiarios: minutos,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(i18n.tr('nutricao.atividades_modal_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<TipoAtividadeItem>(
            initialValue: _tipoSelecionado,
            decoration: InputDecoration(labelText: i18n.tr('nutricao.atividades_modal_tipo_label')),
            items: [
              for (final opcao in widget.opcoes)
                DropdownMenuItem(value: opcao, child: Text(opcao.nomeExibicao)),
            ],
            onChanged: (valor) => setState(() => _tipoSelecionado = valor),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _minutosController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: i18n.tr('nutricao.atividades_modal_minutos_label'),
              hintText: i18n.tr('nutricao.atividades_modal_minutos_hint'),
              errorText: _erroMinutos,
            ),
            onChanged: (_) {
              if (_erroMinutos != null) setState(() => _erroMinutos = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(i18n.tr('nutricao.atividades_modal_cancel')),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: Text(i18n.tr('nutricao.atividades_modal_confirm')),
        ),
      ],
    );
  }
}
