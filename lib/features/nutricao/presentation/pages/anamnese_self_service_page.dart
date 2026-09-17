import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/anamnese_models.dart';
import '../../data/repositories/anamnese_repository.dart';
import '../../data/repositories/meta_bem_estar_repository.dart';
import 'resultado_motor_metabolico_page.dart';

enum _CargaStatus { carregando, sucesso, erro, bloqueadaCarencia }

const _carenciaDias = 30;

/// N09 (RELATÓRIO 20260811_0007) — Anamnese Nutricional Versionada,
/// preenchimento SELF-SERVICE pelo próprio atleta (sem tela equivalente no
/// Painel Web — restrição explícita desta tarefa, foco 100% mobile).
///
/// RELATÓRIO 20260915_0003 — 3 mudanças de escopo sobre a v1 (N09):
///   1. Captura altura/sexo/peso junto (item 1 da tarefa) — mesmo padrão
///      de campo de [PerfilUsuarioPage], mas gravados aqui porque o Motor
///      Metabólico N07 precisa dos 3 pra calcular TMB/TDEE e a anamnese é
///      o momento natural de pedir isso a quem ainda não preencheu.
///   2. Rotina de Atividades agora é POR DIA DA SEMANA (Dom-Sáb), gravando
///      em `anamneses_atividades_dias` em vez da `anamneses_atividades`
///      uniforme antiga — ver o comentário de
///      [AnamneseRepository.salvarAnamnese].
///   3. Trava de 30 Dias: como [MetaBemEstarPage] já faz para a Meta, esta
///      tela bloqueia um novo preenchimento antes de 30 dias do último.
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
  const AnamneseSelfServicePage({
    super.key,
    AnamneseRepository? repository,
    MetaBemEstarRepository? metaRepository,
  })  : _repository = repository,
        _metaRepository = metaRepository;

  final AnamneseRepository? _repository;

  /// Só repassado adiante pra [ResultadoMotorMetabolicoPage] (injeção de
  /// dependência em cascata, pra testes poderem mockar a tela seguinte sem
  /// tocar rede) — esta tela em si nunca chama nada de
  /// [MetaBemEstarRepository] diretamente.
  final MetaBemEstarRepository? _metaRepository;

  @override
  State<AnamneseSelfServicePage> createState() => _AnamneseSelfServicePageState();
}

const _objetivos = ['emagrecimento', 'manutencao', 'hipertrofia'];

class _AnamneseSelfServicePageState extends State<AnamneseSelfServicePage> {
  late final AnamneseRepository _repository = widget._repository ?? AnamneseRepository();

  final _formKey = GlobalKey<FormState>();
  final _alturaController = TextEditingController();
  final _pesoController = TextEditingController();

  _CargaStatus _status = _CargaStatus.carregando;
  bool _salvando = false;
  DateTime? _dataProximaLiberacao;

  /// RELATÓRIO 20260917 (item 1 — "Captura Inteligente") — última leitura
  /// de balança/wearable, mostrada como SUGESTÃO separada do campo de
  /// peso (nunca preenche o campo sozinha).
  SugestaoBalanca? _sugestaoBalanca;

  List<CatalogoItem> _problemasSaude = const [];
  List<CatalogoItem> _alergias = const [];
  List<TipoAtividadeItem> _tiposAtividades = const [];

  String? _objetivoSelecionado;
  String? _sexoSelecionado;
  final Set<String> _problemasSaudeSelecionados = {};
  final Set<String> _alergiasSelecionadas = {};
  final List<AtividadeSelecionada> _atividadesSelecionadas = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _alturaController.dispose();
    _pesoController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final problemasSaude = await _repository.buscarProblemasSaude();
      final alergias = await _repository.buscarAlergias();
      final tiposAtividades = await _repository.buscarTiposAtividades();
      final anamneseAtiva = await _repository.buscarAnamneseAtiva();
      final dadosFisicos = await _repository.buscarDadosFisicosAtuais();
      final sugestaoBalanca = await _repository.buscarSugestaoBalanca();

      if (!mounted) return;

      // Trava de 30 Dias (item 3 da tarefa) — a anamnese ATIVA é sempre a
      // mais recentemente preenchida (o trigger de versionamento garante
      // no máximo 1 "ativo" por usuário), então `dataPreenchimento` dela
      // já é a data do último preenchimento, sem precisar de uma 2ª
      // consulta. Mesmo espírito de `MetaBemEstarPage._carregar`.
      if (anamneseAtiva != null) {
        final liberaEm = anamneseAtiva.dataPreenchimento.add(const Duration(days: _carenciaDias));
        if (liberaEm.isAfter(DateTime.now())) {
          setState(() {
            _dataProximaLiberacao = liberaEm;
            _status = _CargaStatus.bloqueadaCarencia;
          });
          return;
        }
      }

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
        if (dadosFisicos.alturaCm != null) {
          _alturaController.text = _formatarNumero(dadosFisicos.alturaCm!);
        }
        if (dadosFisicos.pesoKg != null) {
          _pesoController.text = _formatarNumero(dadosFisicos.pesoKg!);
        }
        _sexoSelecionado = dadosFisicos.sexoBiologico;
        _sugestaoBalanca = sugestaoBalanca;
        _status = _CargaStatus.sucesso;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  static String _formatarNumero(double valor) {
    return valor == valor.truncateToDouble() ? valor.toStringAsFixed(0) : valor.toString();
  }

  String? _validarAltura(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return i18n.tr('perfil_fisico.altura_validation_empty');
    final numero = double.tryParse(texto.replaceAll(',', '.'));
    if (numero == null) return i18n.tr('perfil_fisico.altura_validation_invalid');
    if (numero < 50 || numero > 250) return i18n.tr('perfil_fisico.altura_validation_range');
    return null;
  }

  String? _validarPeso(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) return i18n.tr('nutricao.peso_validation_empty');
    final numero = double.tryParse(texto.replaceAll(',', '.'));
    if (numero == null) return i18n.tr('nutricao.peso_validation_invalid');
    if (numero < 30 || numero > 300) return i18n.tr('nutricao.peso_validation_range');
    return null;
  }

  /// Modalidades ainda não adicionadas NESTE dia específico — a mesma
  /// atividade pode aparecer em dias diferentes (a duplicidade é evitada
  /// só dentro do mesmo `diaSemana`, mesma granularidade da PK de
  /// `anamneses_atividades_dias`).
  Future<void> _abrirModalAdicionarAtividade(int diaSemana) async {
    final disponiveis = _tiposAtividades
        .where((tipo) => !_atividadesSelecionadas.any((a) => a.atividadeId == tipo.id && a.diaSemana == diaSemana))
        .toList();

    if (disponiveis.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(i18n.tr('nutricao.atividades_todas_adicionadas'))));
      return;
    }

    final resultado = await showDialog<AtividadeSelecionada>(
      context: context,
      builder: (_) => _ModalAdicionarAtividade(opcoes: disponiveis, diaSemana: diaSemana),
    );

    if (resultado == null || !mounted) return;
    setState(() => _atividadesSelecionadas.add(resultado));
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

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

    if (_sexoSelecionado == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(i18n.tr('nutricao.sexo_obrigatorio')),
            backgroundColor: AppColors.error,
          ),
        );
      return;
    }

    setState(() => _salvando = true);
    try {
      await _repository.salvarAnamnese(
        objetivoCodigo: _objetivoSelecionado!,
        alturaCm: double.parse(_alturaController.text.trim().replaceAll(',', '.')),
        sexoBiologico: _sexoSelecionado!,
        pesoKg: double.parse(_pesoController.text.trim().replaceAll(',', '.')),
        problemasSaudeIds: _problemasSaudeSelecionados.toList(),
        alergiaIds: _alergiasSelecionadas.toList(),
        atividades: _atividadesSelecionadas,
      );
      if (!mounted) return;
      // Item 2 da tarefa: após o envio, abre a Tela de Resultado do Motor
      // Metabólico (que chama gerar_sugestao_meta sozinha) — não fica
      // nesta tela mostrando só um snackbar.
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ResultadoMotorMetabolicoPage(repository: widget._metaRepository),
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
      case _CargaStatus.bloqueadaCarencia:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_clock_outlined, size: 48, color: AppColors.mutedText),
                const SizedBox(height: 16),
                Text(
                  i18n.tr('nutricao.anamnese_carencia_titulo'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  i18n.tr(
                    'nutricao.anamnese_carencia_mensagem',
                    params: {'data': _formatarData(_dataProximaLiberacao!)},
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                ),
              ],
            ),
          ),
        );
      case _CargaStatus.sucesso:
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                i18n.tr('nutricao.anamnese_subtitle'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
              ),
              const SizedBox(height: 24),
              _buildSecaoDadosFisicos(context),
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
              _buildSecaoRotina(context),
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
          ),
        );
    }
  }

  Widget _buildSecaoDadosFisicos(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.dados_fisicos_label'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_sugestaoBalanca?.temAlgumDado ?? false) ...[
          _buildSugestaoBalanca(context, _sugestaoBalanca!),
          const SizedBox(height: 16),
        ],
        TextFormField(
          controller: _alturaController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: i18n.tr('perfil_fisico.altura_label'),
            hintText: i18n.tr('perfil_fisico.altura_hint'),
            suffixText: 'cm',
            border: const OutlineInputBorder(),
          ),
          validator: _validarAltura,
          enabled: !_salvando,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _pesoController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: i18n.tr('nutricao.peso_label'),
            hintText: i18n.tr('nutricao.peso_hint'),
            suffixText: 'kg',
            border: const OutlineInputBorder(),
          ),
          validator: _validarPeso,
          enabled: !_salvando,
        ),
        const SizedBox(height: 16),
        Text(i18n.tr('perfil_fisico.sexo_biologico_label'), style: Theme.of(context).textTheme.bodyMedium),
        RadioGroup<String>(
          groupValue: _sexoSelecionado,
          onChanged: (valor) {
            if (_salvando) return;
            setState(() => _sexoSelecionado = valor);
          },
          child: Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'M',
                  title: Text(i18n.tr('perfil_fisico.sexo_biologico_masculino')),
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'F',
                  title: Text(i18n.tr('perfil_fisico.sexo_biologico_feminino')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// RELATÓRIO 20260917 (item 1 — "Captura Inteligente e Confirmação
  /// Obrigatória", docs/motor_metabolico.txt Seção 1: "a leitura da
  /// balança continua existindo como dado de origem, mas só passa a ser
  /// dado antropométrico oficial após confirmação") — mostra a última
  /// leitura de `metricas_saude_diarias` como SUGESTÃO. "Confirmar" só
  /// copia o valor pro campo de peso (ainda editável) — o campo continua
  /// `required`/validado normalmente, então o usuário sempre confirma
  /// (ou corrige) antes de salvar, nunca é gravado sozinho.
  Widget _buildSugestaoBalanca(BuildContext context, SugestaoBalanca sugestao) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryGold.withValues(alpha: 0.1),
        border: Border.all(color: AppColors.primaryGold),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.tr('nutricao.sugestao_balanca_titulo'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          if (sugestao.pesoKg != null)
            Text(i18n.tr('nutricao.sugestao_balanca_peso', params: {
              'peso': _formatarNumero(sugestao.pesoKg!),
              'data': _formatarData(sugestao.dataReferencia!),
            })),
          if (sugestao.percentualGordura != null)
            Text(i18n.tr('nutricao.sugestao_balanca_percentual_gordura', params: {
              'percentual': _formatarNumero(sugestao.percentualGordura!),
              'data': _formatarData(sugestao.dataReferencia!),
            })),
          if (sugestao.pesoKg != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _salvando
                    ? null
                    : () => setState(() => _pesoController.text = _formatarNumero(sugestao.pesoKg!)),
                child: Text(i18n.tr('nutricao.sugestao_balanca_usar_button')),
              ),
            ),
          ],
        ],
      ),
    );
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

  Widget _buildSecaoRotina(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.rotina_dia_semana_label'), style: Theme.of(context).textTheme.titleMedium),
        for (var dia = 0; dia <= 6; dia++) _buildDiaSemana(context, dia),
      ],
    );
  }

  Widget _buildDiaSemana(BuildContext context, int diaSemana) {
    final atividadesDoDia = _atividadesSelecionadas.where((a) => a.diaSemana == diaSemana).toList();

    return ExpansionTile(
      key: PageStorageKey<int>(diaSemana),
      tilePadding: EdgeInsets.zero,
      title: Text(i18n.tr('nutricao.dia_semana_$diaSemana')),
      children: [
        if (atividadesDoDia.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              i18n.tr('nutricao.rotina_dia_vazio'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
            ),
          )
        else
          for (final atividade in atividadesDoDia)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(atividade.nomeExibicao),
              subtitle: Text(
                i18n.tr('nutricao.atividades_minutos', params: {'minutos': atividade.minutos.toString()}),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _salvando
                    ? null
                    : () => setState(() => _atividadesSelecionadas.remove(atividade)),
              ),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _salvando ? null : () => _abrirModalAdicionarAtividade(diaSemana),
            icon: const Icon(Icons.add),
            label: Text(i18n.tr('nutricao.rotina_dia_add_button')),
          ),
        ),
      ],
    );
  }

  /// dd/mm/aaaa — mesmo padrão simples de `meta_bem_estar_page.dart`.
  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }
}

/// Modal "Adicionar Atividade" — dropdown de modalidade + input numérico de
/// minutos, escopado a UM dia da semana. `StatefulWidget` próprio (não
/// `StatefulBuilder` inline) só pra manter o `TextEditingController` com
/// ciclo de vida correto (`dispose`), mesmo em um `showDialog`.
class _ModalAdicionarAtividade extends StatefulWidget {
  const _ModalAdicionarAtividade({required this.opcoes, required this.diaSemana});

  final List<TipoAtividadeItem> opcoes;
  final int diaSemana;

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
        minutos: minutos,
        diaSemana: widget.diaSemana,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        i18n.tr('nutricao.atividades_modal_title_dia', params: {
          'dia': i18n.tr('nutricao.dia_semana_${widget.diaSemana}'),
        }),
      ),
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
