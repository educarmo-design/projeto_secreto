import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/anamnese_models.dart';
import '../../data/repositories/anamnese_repository.dart';
import '../../data/repositories/meta_bem_estar_repository.dart';
import '../widgets/lista_repetivel_widget.dart';
import '../widgets/refeicoes_habituais_widget.dart';
import '../widgets/revisao_smartwatch_page.dart';
import '../widgets/seletor_multiplo_bottom_sheet.dart';
import 'confirmar_anamnese_page.dart';

enum _CargaStatus { carregando, sucesso, erro, bloqueadaCarencia }

const _carenciaDias = 30;
const _idadeMinimaBlocoIdoso = 60;

/// N09 (RELATÓRIO 20260811_0007) — Anamnese Nutricional Versionada,
/// self-service. RELATÓRIO 20260918_0001 — compliance total com os Blocos
/// 1-16 de docs/motor_metabolico.txt: esta tela cobre os Blocos 1-12
/// (coleta de dados) em seções sequenciais dentro de uma única página
/// rolável — "passos" no sentido de blocos claramente delimitados, não uma
/// troca de tela por bloco (decisão de escopo registrada no relatório
/// desta tarefa) — seguidos por uma tela dedicada de confirmação final
/// ([ConfirmarAnamnesePage], Seção 11) antes de qualquer gravação.
///
/// "Salvar" nesta tela NUNCA grava nada — só monta um [AnamneseRascunho] e
/// navega pra confirmação; a gravação de verdade
/// ([AnamneseRepository.salvarAnamnese]) só acontece lá.
///
/// Regra 14 (Parte 0): "Validação = completa funcionalmente, crua
/// visualmente" — Radio/Checkbox/ListTile crus, sem carrossel/ilustração.
class AnamneseSelfServicePage extends StatefulWidget {
  const AnamneseSelfServicePage({
    super.key,
    AnamneseRepository? repository,
    MetaBemEstarRepository? metaRepository,
  })  : _repository = repository,
        _metaRepository = metaRepository;

  final AnamneseRepository? _repository;

  /// Só repassado adiante em cascata (Anamnese → Confirmação → Resultado)
  /// pra testes poderem mockar a última tela sem tocar rede.
  final MetaBemEstarRepository? _metaRepository;

  @override
  State<AnamneseSelfServicePage> createState() => _AnamneseSelfServicePageState();
}

const _objetivos = [
  'perder_peso',
  'manter_peso',
  'ganhar_peso',
  'reduzir_gordura_corporal',
  'ganhar_massa_muscular',
  'recomposicao_corporal',
  'melhorar_desempenho_esportivo',
  'outro',
];

const _motivosAvaliacao = [
  'avaliacao_inicial',
  'reavaliacao_periodica',
  'alteracao_objetivo',
  'alteracao_condicao_saude',
  'alteracao_peso',
  'alteracao_rotina',
  'nova_avaliacao_profissional',
  'retorno_apos_interrupcao',
  'outro',
];

const _rotinasDiarias = [
  'predominantemente_sentado',
  'pouco_ativo',
  'moderadamente_ativo',
  'muito_ativo',
  'trabalho_fisicamente_intenso',
];

const _qualidadesSono = ['muito_ruim', 'ruim', 'regular', 'boa', 'muito_boa'];
const _intensidades = ['leve', 'moderada', 'alta'];

/// RELATÓRIO 20260922_0002 (Item 1) — catálogo de Restrições Culturais/
/// Religiosas. `restricoes_culturais_religiosas` é `text[]` LIVRE no banco
/// (sem tabela-catálogo, diferente de Alergias) — os `id`s aqui só
/// existem pra alimentar a MESMA mecânica visual de [abrirSeletorMultiplo]
/// (checkbox + busca implícita da lista curta); ao salvar, cada `id`
/// selecionado vira o texto traduzido correspondente (ver
/// `_restricoesCulturaisComoTexto`).
const _restricoesCulturaisCodigos = [
  'vegano',
  'vegetariano',
  'kosher',
  'halal',
  'jejum_intermitente',
  'outros',
];

class _AnamneseSelfServicePageState extends State<AnamneseSelfServicePage> {
  late final AnamneseRepository _repository = widget._repository ?? AnamneseRepository();

  final _formKey = GlobalKey<FormState>();
  final _alturaController = TextEditingController();
  final _pesoController = TextEditingController();

  _CargaStatus _status = _CargaStatus.carregando;
  bool _indoParaConfirmacao = false;
  DateTime? _dataProximaLiberacao;

  SugestaoBalanca? _sugestaoBalanca;
  HistoricoPeso? _historicoPeso;
  int? _idade;

  List<CatalogoItem> _problemasSaude = const [];
  List<CatalogoItem> _alergias = const [];
  List<TipoAtividadeItem> _tiposAtividades = const [];

  String? _motivoAvaliacaoSelecionado;
  final _motivoAvaliacaoOutroController = TextEditingController();

  String? _objetivoSelecionado;
  final _objetivoOutroController = TextEditingController();
  final Set<String> _objetivosSecundariosSelecionados = {};
  final _metaPesoController = TextEditingController();
  final _metaPercentualGorduraController = TextEditingController();
  final _metaMassaController = TextEditingController();
  final _metaOutroIndicadorController = TextEditingController();

  String? _sexoSelecionado;
  final _percentualGorduraController = TextEditingController();
  final _massaMagraController = TextEditingController();
  final _massaGordaController = TextEditingController();
  final _massaMuscularController = TextEditingController();
  final _circCinturaController = TextEditingController();
  final _circAbdominalController = TextEditingController();

  String? _houveAlteracaoPeso;

  final _numeroRefeicoesController = TextEditingController();
  final _horariosRefeicoesController = TextEditingController();
  final _refeicoesForaController = TextEditingController();
  final _preferenciasController = TextEditingController();
  final _alimentosEvitadosController = TextEditingController();
  final _restricoesController = TextEditingController();
  final _intolerenciasController = TextEditingController();
  final _padraoAlimentarController = TextEditingController();

  String? _rotinaDiariaSelecionada;
  final _atividadeOcupacionalController = TextEditingController();

  final _horasSonoController = TextEditingController();
  final _horarioDormirController = TextEditingController();
  final _horarioAcordarController = TextEditingController();
  String? _qualidadeSonoSelecionada;
  final _despertaresController = TextEditingController();

  bool? _possuiCondicaoSaude;
  final Set<String> _problemasSaudeSelecionados = {};
  final Set<String> _alergiasSelecionadas = {};
  final List<AtividadeSelecionada> _atividadesSelecionadas = [];

  // RELATÓRIO 20260922_0002 (Item 1) — Restrições Culturais/Religiosas.
  final Set<String> _restricoesCulturaisSelecionadas = {};
  final _restricoesCulturaisOutroController = TextEditingController();

  // RELATÓRIO 20260922_0002 (Item 2) — Motor de Agregação de Smartwatch.
  JanelaAnamnese? _janelaSmartwatch;
  bool _buscandoSmartwatch = false;

  // RELATÓRIO 20260922_0002 (Item 3) — Refeições Diárias Habituais + IA.
  final ValueNotifier<List<Map<String, dynamic>>> _refeicoesHabituaisNotifier = ValueNotifier(const []);

  bool _praticaEsporteEstruturado = false;
  final _atletaModalidadeController = TextEditingController();
  final _atletaHorasSemanaController = TextEditingController();
  final _atletaObjetivoEsportivoController = TextEditingController();
  bool _atletaCompeticaoProxima = false;

  bool _idosoPerdaPeso = false;
  bool _idosoReducaoForcaMobilidade = false;
  bool _idosoDificuldadeAlimentacao = false;

  final _diabetesTipoController = TextEditingController();
  bool _diabetesUsaInsulina = false;
  bool _diabetesUsaMedicamento = false;
  final _diabetesHba1cController = TextEditingController();

  final _renalEstagioController = TextEditingController();
  final _renalTfgController = TextEditingController();
  bool _renalFazDialise = false;

  final _recomposicaoPercentualAtualController = TextEditingController();
  final _recomposicaoPercentualDesejadoController = TextEditingController();
  bool _recomposicaoTreinamentoResistido = false;

  final List<ItemRepetivel> _medicamentos = [];
  final List<ItemRepetivel> _suplementos = [];
  final List<ItemRepetivel> _exames = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _alturaController.dispose();
    _pesoController.dispose();
    _motivoAvaliacaoOutroController.dispose();
    _objetivoOutroController.dispose();
    _metaPesoController.dispose();
    _metaPercentualGorduraController.dispose();
    _metaMassaController.dispose();
    _metaOutroIndicadorController.dispose();
    _percentualGorduraController.dispose();
    _massaMagraController.dispose();
    _massaGordaController.dispose();
    _massaMuscularController.dispose();
    _circCinturaController.dispose();
    _circAbdominalController.dispose();
    _numeroRefeicoesController.dispose();
    _horariosRefeicoesController.dispose();
    _refeicoesForaController.dispose();
    _preferenciasController.dispose();
    _alimentosEvitadosController.dispose();
    _restricoesController.dispose();
    _intolerenciasController.dispose();
    _padraoAlimentarController.dispose();
    _atividadeOcupacionalController.dispose();
    _horasSonoController.dispose();
    _horarioDormirController.dispose();
    _horarioAcordarController.dispose();
    _despertaresController.dispose();
    _atletaModalidadeController.dispose();
    _atletaHorasSemanaController.dispose();
    _atletaObjetivoEsportivoController.dispose();
    _diabetesTipoController.dispose();
    _diabetesHba1cController.dispose();
    _renalEstagioController.dispose();
    _renalTfgController.dispose();
    _recomposicaoPercentualAtualController.dispose();
    _recomposicaoPercentualDesejadoController.dispose();
    _restricoesCulturaisOutroController.dispose();
    _refeicoesHabituaisNotifier.dispose();
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
      final historicoPeso = await _repository.buscarHistoricoPeso();

      if (!mounted) return;

      // Trava de 30 Dias — mesmo espírito de MetaBemEstarPage._carregar.
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
        _historicoPeso = historicoPeso;
        _idade = dadosFisicos.idade;
        if (anamneseAtiva != null) {
          _objetivoSelecionado = anamneseAtiva.objetivoCodigo;
          _problemasSaudeSelecionados
            ..clear()
            ..addAll(anamneseAtiva.problemasSaudeIds);
          _possuiCondicaoSaude = anamneseAtiva.problemasSaudeIds.isNotEmpty ? true : _possuiCondicaoSaude;
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

    // RELATÓRIO 20260922_0002 (Item 2) — janela de tempo do botão "Buscar
    // dados do relógio". Best-effort, isolado do try/catch acima de
    // propósito: uma falha aqui NUNCA deve travar a tela inteira (o botão
    // simplesmente fica indisponível, o preenchimento manual continua 100%
    // funcional).
    try {
      final janela = await _repository.buscarJanelaSmartwatch();
      if (mounted) setState(() => _janelaSmartwatch = janela);
    } catch (_) {
      // Sem janela = botão "Buscar dados do relógio" some da tela (ver
      // `_janelaSmartwatch == null` nos pontos de uso).
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

  bool get _mostrarBlocoIdoso => (_idade ?? 0) >= _idadeMinimaBlocoIdoso;

  bool get _mostrarBlocoDiabetes => _problemasSaudeSelecionados.any((id) {
        final nome = _problemasSaude.firstWhere((item) => item.id == id, orElse: () => const CatalogoItem(id: '', nome: '')).nome;
        return nome.toLowerCase().contains('diabetes');
      });

  bool get _mostrarBlocoRenal => _problemasSaudeSelecionados.any((id) {
        final nome = _problemasSaude.firstWhere((item) => item.id == id, orElse: () => const CatalogoItem(id: '', nome: '')).nome;
        return nome.toLowerCase().contains('renal');
      });

  bool get _mostrarBlocoRecomposicao => _objetivoSelecionado == 'recomposicao_corporal';

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

  /// RELATÓRIO 20260922_0002 (Item 2) — "Buscar dados do relógio": chama
  /// `processar_medias_smartwatch` (janela calculada por
  /// `iniciar_rascunho_anamnese` no carregamento da tela) e abre a UX de
  /// Revisão ([RevisaoSmartwatchPage]) — NUNCA aplica nada automaticamente
  /// (RESTRIÇÃO explícita da tarefa); só o que o usuário marcar "Aceitar"
  /// lá volta aqui, ainda como rascunho em memória (o Salvar/Confirmar de
  /// sempre continua sendo o único jeito de gravar).
  Future<void> _buscarDadosRelogio() async {
    final janela = _janelaSmartwatch;
    if (janela == null) return;

    setState(() => _buscandoSmartwatch = true);
    MediasSmartwatchResultado resultado;
    try {
      resultado = await _repository.buscarMediasSmartwatch(dataInicio: janela.dataInicio, dataFim: janela.dataFim);
    } catch (_) {
      if (mounted) {
        setState(() => _buscandoSmartwatch = false);
        _mostrarErro(i18n.tr('nutricao.smartwatch_erro'));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _buscandoSmartwatch = false);

    final revisao = await Navigator.of(context).push<RevisaoSmartwatchResultado>(
      MaterialPageRoute(
        builder: (_) => RevisaoSmartwatchPage(
          resultado: resultado,
          catalogoAtividades: _tiposAtividades,
          atividadesJaAdicionadas: _atividadesSelecionadas,
        ),
      ),
    );
    if (revisao == null || !mounted) return;

    setState(() {
      for (final atividade in revisao.atividadesAceitas) {
        // Evita duplicar se o usuário já tinha essa mesma atividade+dia
        // adicionada manualmente antes de abrir a revisão.
        if (!_atividadesSelecionadas.contains(atividade)) {
          _atividadesSelecionadas.add(atividade);
        }
      }
      if (revisao.horasSonoAceitas != null) {
        _horasSonoController.text = _formatarNumero(revisao.horasSonoAceitas!);
      }
      if (revisao.horasTreinoSemanaAceitas != null) {
        _praticaEsporteEstruturado = true;
        _atletaHorasSemanaController.text = _formatarNumero(revisao.horasTreinoSemanaAceitas!);
      }
    });
  }

  void _irParaConfirmacao() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_objetivoSelecionado == null) {
      _mostrarErro(i18n.tr('nutricao.objetivo_obrigatorio'));
      return;
    }
    if (_sexoSelecionado == null) {
      _mostrarErro(i18n.tr('nutricao.sexo_obrigatorio'));
      return;
    }

    final complementares = DadosComplementaresAnamnese(
      motivoAvaliacao: _motivoAvaliacaoSelecionado,
      motivoAvaliacaoOutro: _textoOuNulo(_motivoAvaliacaoOutroController),
      objetivoOutro: _textoOuNulo(_objetivoOutroController),
      objetivosSecundarios: _objetivosSecundariosSelecionados.toList(),
      metaPesoDesejadoKg: double.tryParse(_metaPesoController.text.trim().replaceAll(',', '.')),
      metaPercentualGorduraDesejado: double.tryParse(_metaPercentualGorduraController.text.trim().replaceAll(',', '.')),
      metaMassaDesejadaKg: double.tryParse(_metaMassaController.text.trim().replaceAll(',', '.')),
      metaOutroIndicador: _metaOutroIndicadorController.text.trim().isEmpty ? null : _metaOutroIndicadorController.text.trim(),
      percentualGordura: double.tryParse(_percentualGorduraController.text.trim().replaceAll(',', '.')),
      massaMagraKg: double.tryParse(_massaMagraController.text.trim().replaceAll(',', '.')),
      massaGordaKg: double.tryParse(_massaGordaController.text.trim().replaceAll(',', '.')),
      massaMuscularKg: double.tryParse(_massaMuscularController.text.trim().replaceAll(',', '.')),
      circunferenciaCinturaCm: double.tryParse(_circCinturaController.text.trim().replaceAll(',', '.')),
      circunferenciaAbdominalCm: double.tryParse(_circAbdominalController.text.trim().replaceAll(',', '.')),
      houveAlteracaoPesoNaoPlanejada: _houveAlteracaoPeso,
      numeroRefeicoesDia: int.tryParse(_numeroRefeicoesController.text.trim()),
      horariosRefeicoesHabituais: _textoOuNulo(_horariosRefeicoesController),
      refeicoesForaDeCasa: _textoOuNulo(_refeicoesForaController),
      preferenciasAlimentares: _textoOuNulo(_preferenciasController),
      alimentosEvitados: _textoOuNulo(_alimentosEvitadosController),
      restricoesAlimentares: _listaDeTexto(_restricoesController),
      intolerancias: _listaDeTexto(_intolerenciasController),
      padraoAlimentarHabitual: _textoOuNulo(_padraoAlimentarController),
      restricoesCulturaisReligiosas: _restricoesCulturaisComoTexto(),
      refeicoesDiariasHabituais: _refeicoesHabituaisNotifier.value,
      rotinaDiaria: _rotinaDiariaSelecionada,
      atividadeOcupacional: _textoOuNulo(_atividadeOcupacionalController),
      horasSonoMedias: double.tryParse(_horasSonoController.text.trim().replaceAll(',', '.')),
      horarioDormirHabitual: _textoOuNulo(_horarioDormirController),
      horarioAcordarHabitual: _textoOuNulo(_horarioAcordarController),
      qualidadeSonoPercebida: _qualidadeSonoSelecionada,
      despertaresNoturnos: int.tryParse(_despertaresController.text.trim()),
      possuiCondicaoSaude: _possuiCondicaoSaude,
      blocoAtleta: !_praticaEsporteEstruturado
          ? null
          : {
              'modalidade': _atletaModalidadeController.text.trim(),
              'horas_semana': _atletaHorasSemanaController.text.trim(),
              'objetivo_esportivo': _atletaObjetivoEsportivoController.text.trim(),
              'competicao_proxima': _atletaCompeticaoProxima,
            },
      blocoIdoso: !_mostrarBlocoIdoso
          ? null
          : {
              'perda_involuntaria_peso': _idosoPerdaPeso,
              'reducao_forca_mobilidade': _idosoReducaoForcaMobilidade,
              'dificuldade_alimentacao': _idosoDificuldadeAlimentacao,
            },
      blocoDiabetes: !_mostrarBlocoDiabetes
          ? null
          : {
              'tipo': _diabetesTipoController.text.trim(),
              'usa_insulina': _diabetesUsaInsulina,
              'usa_medicamento': _diabetesUsaMedicamento,
              'hba1c': _diabetesHba1cController.text.trim(),
            },
      blocoDoencaRenal: !_mostrarBlocoRenal
          ? null
          : {
              'estagio': _renalEstagioController.text.trim(),
              'tfg_egfr': _renalTfgController.text.trim(),
              'faz_dialise': _renalFazDialise,
            },
      blocoRecomposicao: !_mostrarBlocoRecomposicao
          ? null
          : {
              'percentual_gordura_atual': _recomposicaoPercentualAtualController.text.trim(),
              'percentual_desejado': _recomposicaoPercentualDesejadoController.text.trim(),
              'treinamento_resistido': _recomposicaoTreinamentoResistido,
            },
      medicamentos: _medicamentos,
      suplementos: _suplementos,
      exames: _exames,
    );

    final rascunho = AnamneseRascunho(
      objetivoCodigo: _objetivoSelecionado!,
      alturaCm: double.parse(_alturaController.text.trim().replaceAll(',', '.')),
      sexoBiologico: _sexoSelecionado!,
      pesoKg: double.parse(_pesoController.text.trim().replaceAll(',', '.')),
      idade: _idade,
      problemasSaudeSelecionados: _problemasSaude.where((item) => _problemasSaudeSelecionados.contains(item.id)).toList(),
      alergiasSelecionadas: _alergias.where((item) => _alergiasSelecionadas.contains(item.id)).toList(),
      atividades: _atividadesSelecionadas,
      complementares: complementares,
    );

    setState(() => _indoParaConfirmacao = true);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => ConfirmarAnamnesePage(rascunho: rascunho, repository: _repository, metaRepository: widget._metaRepository),
        ))
        .whenComplete(() {
      if (mounted) setState(() => _indoParaConfirmacao = false);
    });
  }

  String? _textoOuNulo(TextEditingController controller) {
    final texto = controller.text.trim();
    return texto.isEmpty ? null : texto;
  }

  List<String> _listaDeTexto(TextEditingController controller) {
    final texto = controller.text.trim();
    if (texto.isEmpty) return const [];
    return texto.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
  }

  void _mostrarErro(String mensagem) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensagem), backgroundColor: AppColors.error));
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _carregar, child: Text(i18n.tr('nutricao.save_button'))),
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
                  i18n.tr('nutricao.anamnese_carencia_mensagem', params: {'data': _formatarData(_dataProximaLiberacao!)}),
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
              // RELATÓRIO 20260922_0002 (Item 1) — Sexo Biológico movido pra
              // ANTES do Motivo da Avaliação (pedido explícito do
              // fundador); continua exibindo o valor que já vem do Perfil
              // ([_sexoSelecionado], preenchido em [_carregar] a partir de
              // [DadosFisicosAtuais.sexoBiologico]).
              _buildSecaoSexoBiologico(context),
              const SizedBox(height: 24),
              _buildSecaoMotivoAvaliacao(context),
              const SizedBox(height: 24),
              _buildSecaoDadosFisicos(context),
              const SizedBox(height: 24),
              _buildSecaoComposicaoCorporal(context),
              const SizedBox(height: 24),
              _buildSecaoHistoricoPeso(context),
              const SizedBox(height: 24),
              _buildSecaoObjetivo(context),
              const SizedBox(height: 24),
              _buildSecaoAlimentacao(context),
              const SizedBox(height: 24),
              _buildSecaoRotinaDiaria(context),
              const SizedBox(height: 24),
              _buildBotaoBuscarSmartwatch(context),
              const SizedBox(height: 24),
              _buildSecaoRotina(context),
              const SizedBox(height: 24),
              _buildSecaoSono(context),
              const SizedBox(height: 24),
              _buildSecaoCondicoes(context),
              if (_mostrarBlocoDiabetes) ...[const SizedBox(height: 24), _buildBlocoDiabetes(context)],
              if (_mostrarBlocoRenal) ...[const SizedBox(height: 24), _buildBlocoRenal(context)],
              if (_mostrarBlocoRecomposicao) ...[const SizedBox(height: 24), _buildBlocoRecomposicao(context)],
              if (_mostrarBlocoIdoso) ...[const SizedBox(height: 24), _buildBlocoIdoso(context)],
              const SizedBox(height: 24),
              _buildBlocoAtleta(context),
              const SizedBox(height: 24),
              ListaRepetivelWidget(
                titulo: i18n.tr('nutricao.medicamentos_label'),
                vazioTexto: i18n.tr('nutricao.medicamentos_empty'),
                addButtonTexto: i18n.tr('nutricao.medicamentos_add_button'),
                modalTitulo: i18n.tr('nutricao.medicamentos_modal_title'),
                itens: _medicamentos,
                habilitado: !_indoParaConfirmacao,
                camposExtras: [
                  CampoExtra(chave: 'dose', label: i18n.tr('nutricao.medicamentos_modal_dose_label'), tipo: TextInputType.number),
                  CampoExtra(chave: 'unidade', label: i18n.tr('nutricao.medicamentos_modal_unidade_label')),
                  CampoExtra(chave: 'frequencia', label: i18n.tr('nutricao.medicamentos_modal_frequencia_label')),
                ],
                onAdicionar: (item) => setState(() => _medicamentos.add(item)),
                onRemover: (item) => setState(() => _medicamentos.remove(item)),
              ),
              const SizedBox(height: 24),
              ListaRepetivelWidget(
                titulo: i18n.tr('nutricao.suplementos_label'),
                vazioTexto: i18n.tr('nutricao.suplementos_empty'),
                addButtonTexto: i18n.tr('nutricao.suplementos_add_button'),
                modalTitulo: i18n.tr('nutricao.suplementos_modal_title'),
                itens: _suplementos,
                habilitado: !_indoParaConfirmacao,
                camposExtras: [
                  CampoExtra(chave: 'dose', label: i18n.tr('nutricao.medicamentos_modal_dose_label'), tipo: TextInputType.number),
                  CampoExtra(chave: 'unidade', label: i18n.tr('nutricao.medicamentos_modal_unidade_label')),
                  CampoExtra(chave: 'objetivo', label: i18n.tr('nutricao.suplementos_modal_objetivo_label')),
                ],
                onAdicionar: (item) => setState(() => _suplementos.add(item)),
                onRemover: (item) => setState(() => _suplementos.remove(item)),
              ),
              const SizedBox(height: 24),
              ListaRepetivelWidget(
                titulo: i18n.tr('nutricao.exames_label'),
                vazioTexto: i18n.tr('nutricao.exames_empty'),
                addButtonTexto: i18n.tr('nutricao.exames_add_button'),
                modalTitulo: i18n.tr('nutricao.exames_modal_title'),
                itens: _exames,
                habilitado: !_indoParaConfirmacao,
                camposExtras: [
                  CampoExtra(chave: 'resultado', label: i18n.tr('nutricao.exames_modal_resultado_label')),
                  CampoExtra(chave: 'unidade', label: i18n.tr('nutricao.medicamentos_modal_unidade_label')),
                ],
                onAdicionar: (item) => setState(() => _exames.add(item)),
                onRemover: (item) => setState(() => _exames.remove(item)),
              ),
              const SizedBox(height: 24),
              _buildSecaoAlergias(context),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _indoParaConfirmacao ? null : _irParaConfirmacao,
                child: _indoParaConfirmacao
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(i18n.tr('nutricao.save_button')),
              ),
            ],
          ),
        );
    }
  }

  /// Bloco 1 — motivo da avaliação.
  Widget _buildSecaoMotivoAvaliacao(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.motivo_avaliacao_label'), style: Theme.of(context).textTheme.titleMedium),
        RadioGroup<String>(
          groupValue: _motivoAvaliacaoSelecionado,
          onChanged: (valor) {
            if (_indoParaConfirmacao) return;
            setState(() => _motivoAvaliacaoSelecionado = valor);
          },
          child: Column(
            children: [
              for (final motivo in _motivosAvaliacao)
                RadioListTile<String>(contentPadding: EdgeInsets.zero, value: motivo, title: Text(i18n.tr('nutricao.motivo_avaliacao_$motivo'))),
            ],
          ),
        ),
        if (_motivoAvaliacaoSelecionado == 'outro')
          TextFormField(
            controller: _motivoAvaliacaoOutroController,
            decoration: InputDecoration(hintText: i18n.tr('nutricao.motivo_avaliacao_outro_hint'), border: const OutlineInputBorder()),
            enabled: !_indoParaConfirmacao,
          ),
      ],
    );
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
          enabled: !_indoParaConfirmacao,
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
          enabled: !_indoParaConfirmacao,
        ),
      ],
    );
  }

  /// RELATÓRIO 20260922_0002 (Item 1) — "Esse campo deve exibir a
  /// informação que já vem do Perfil do Usuário": [_sexoSelecionado] é
  /// preenchido em [_carregar] a partir de `perfis_usuarios` (via
  /// [DadosFisicosAtuais.sexoBiologico]), o mesmo valor de sempre — só a
  /// POSIÇÃO na tela mudou (antes do Motivo da Avaliação agora).
  Widget _buildSecaoSexoBiologico(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('perfil_fisico.sexo_biologico_label'), style: Theme.of(context).textTheme.titleMedium),
        RadioGroup<String>(
          groupValue: _sexoSelecionado,
          onChanged: (valor) {
            if (_indoParaConfirmacao) return;
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
          Text(i18n.tr('nutricao.sugestao_balanca_titulo'), style: Theme.of(context).textTheme.titleSmall),
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
                onPressed: _indoParaConfirmacao
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

  /// Bloco 3 (docs/motor_metabolico.txt) — composição corporal, todos
  /// opcionais ("quando disponível").
  Widget _buildSecaoComposicaoCorporal(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.composicao_corporal_label'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_percentualGorduraController, i18n.tr('nutricao.percentual_gordura_label')),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_massaMagraController, i18n.tr('nutricao.massa_magra_label')),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_massaGordaController, i18n.tr('nutricao.massa_gorda_label')),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_massaMuscularController, i18n.tr('nutricao.massa_muscular_label')),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_circCinturaController, i18n.tr('nutricao.circunferencia_cintura_label')),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_circAbdominalController, i18n.tr('nutricao.circunferencia_abdominal_label')),
      ],
    );
  }

  /// Bloco 4 — histórico recuperado automaticamente (RPC
  /// `anamnese_historico_peso`), nunca reperguntado; só a pergunta
  /// adicional da Seção 10 vira input.
  Widget _buildSecaoHistoricoPeso(BuildContext context) {
    final historico = _historicoPeso;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.historico_peso_label'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (historico == null || !historico.temAlgumDado)
          Text(i18n.tr('nutricao.historico_peso_vazio'), style: Theme.of(context).textTheme.bodySmall)
        else ...[
          if (historico.pesoAtual != null) Text(i18n.tr('nutricao.historico_peso_atual', params: {'peso': '${historico.pesoAtual}'})),
          if (historico.pesoAnterior != null) Text(i18n.tr('nutricao.historico_peso_anterior', params: {'peso': '${historico.pesoAnterior}'})),
          if (historico.peso30Dias != null) Text(i18n.tr('nutricao.historico_peso_30_dias', params: {'peso': '${historico.peso30Dias}'})),
          if (historico.peso3Meses != null) Text(i18n.tr('nutricao.historico_peso_3_meses', params: {'peso': '${historico.peso3Meses}'})),
          if (historico.peso6Meses != null) Text(i18n.tr('nutricao.historico_peso_6_meses', params: {'peso': '${historico.peso6Meses}'})),
          if (historico.peso12Meses != null) Text(i18n.tr('nutricao.historico_peso_12_meses', params: {'peso': '${historico.peso12Meses}'})),
          if (historico.maiorPeso != null) Text(i18n.tr('nutricao.historico_peso_maior', params: {'peso': '${historico.maiorPeso}'})),
          if (historico.menorPeso != null) Text(i18n.tr('nutricao.historico_peso_menor', params: {'peso': '${historico.menorPeso}'})),
          if (historico.variacaoPercentual != null)
            Text(i18n.tr('nutricao.historico_peso_variacao', params: {'percentual': '${historico.variacaoPercentual}'})),
        ],
        const SizedBox(height: 12),
        Text(i18n.tr('nutricao.alteracao_peso_pergunta'), style: Theme.of(context).textTheme.bodyMedium),
        RadioGroup<String>(
          groupValue: _houveAlteracaoPeso,
          onChanged: (valor) {
            if (_indoParaConfirmacao) return;
            setState(() => _houveAlteracaoPeso = valor);
          },
          child: Column(
            children: [
              for (final opcao in ['sim', 'nao', 'nao_sabe'])
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: opcao,
                  title: Text(i18n.tr('nutricao.alteracao_peso_$opcao')),
                ),
            ],
          ),
        ),
      ],
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
            if (_indoParaConfirmacao) return;
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
        if (_objetivoSelecionado == 'outro')
          TextFormField(
            controller: _objetivoOutroController,
            decoration: InputDecoration(hintText: i18n.tr('nutricao.objetivo_outro_hint'), border: const OutlineInputBorder()),
            enabled: !_indoParaConfirmacao,
          ),
        const SizedBox(height: 16),
        ResumoSelecaoMultipla(
          label: i18n.tr('nutricao.objetivos_secundarios_label'),
          quantidadeSelecionada: _objetivosSecundariosSelecionados.length,
          onEditar: () async {
            final resultado = await abrirSeletorMultiplo(
              context: context,
              titulo: i18n.tr('nutricao.objetivos_secundarios_label'),
              itens: [
                for (final codigo in _objetivos.where((o) => o != 'outro' && o != _objetivoSelecionado))
                  CatalogoItem(id: codigo, nome: i18n.tr('nutricao.objetivo_$codigo')),
              ],
              selecionadosIniciais: _objetivosSecundariosSelecionados,
            );
            if (resultado != null) {
              setState(() {
                _objetivosSecundariosSelecionados
                  ..clear()
                  ..addAll(resultado);
              });
            }
          },
        ),
        const SizedBox(height: 16),
        Text(i18n.tr('nutricao.meta_quantitativa_label'), style: Theme.of(context).textTheme.titleSmall),
        Text(
          i18n.tr('nutricao.meta_quantitativa_aviso'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_metaPesoController, i18n.tr('nutricao.meta_peso_desejado_label')),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_metaPercentualGorduraController, i18n.tr('nutricao.meta_percentual_gordura_desejado_label')),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_metaMassaController, i18n.tr('nutricao.meta_massa_desejada_label')),
        const SizedBox(height: 8),
        TextFormField(
          controller: _metaOutroIndicadorController,
          decoration: InputDecoration(labelText: i18n.tr('nutricao.meta_outro_indicador_label'), border: const OutlineInputBorder()),
          enabled: !_indoParaConfirmacao,
        ),
      ],
    );
  }

  /// Bloco 5 — padrão alimentar. "Consumo" (energia/macros) deliberadamente
  /// fora daqui — já existe o diário alimentar (Seção 18 do documento: não
  /// duplicar informação de outro módulo).
  Widget _buildSecaoAlimentacao(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.alimentacao_label'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextFormField(
          controller: _numeroRefeicoesController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: i18n.tr('nutricao.numero_refeicoes_label'), border: const OutlineInputBorder()),
          enabled: !_indoParaConfirmacao,
        ),
        const SizedBox(height: 8),
        _campoTextoOpcional(_horariosRefeicoesController, i18n.tr('nutricao.horarios_refeicoes_label')),
        const SizedBox(height: 8),
        _campoTextoOpcional(_refeicoesForaController, i18n.tr('nutricao.refeicoes_fora_label')),
        const SizedBox(height: 8),
        _campoTextoOpcional(_preferenciasController, i18n.tr('nutricao.preferencias_alimentares_label')),
        const SizedBox(height: 8),
        _campoTextoOpcional(_alimentosEvitadosController, i18n.tr('nutricao.alimentos_evitados_label')),
        const SizedBox(height: 8),
        _campoTextoOpcional(_restricoesController, i18n.tr('nutricao.restricoes_alimentares_label')),
        const SizedBox(height: 8),
        _campoTextoOpcional(_intolerenciasController, i18n.tr('nutricao.intolerancias_label')),
        const SizedBox(height: 8),
        _campoTextoOpcional(_padraoAlimentarController, i18n.tr('nutricao.padrao_alimentar_label')),
        const SizedBox(height: 16),
        _buildSecaoRestricoesCulturais(context),
        const SizedBox(height: 16),
        Text(i18n.tr('nutricao.refeicoes_habituais_label'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          i18n.tr('nutricao.refeicoes_habituais_aviso'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
        ),
        const SizedBox(height: 8),
        // `AnimatedBuilder` sobre o próprio controller (que já é um
        // `Listenable`) — reconstrói o número de linhas de refeição
        // automaticamente conforme o usuário digita em "Refeições/dia",
        // sem precisar de um `ValueNotifier` paralelo.
        AnimatedBuilder(
          animation: _numeroRefeicoesController,
          builder: (context, _) {
            final numero = int.tryParse(_numeroRefeicoesController.text.trim()) ?? 0;
            return RefeicoesHabituaisWidget(
              numeroRefeicoes: numero,
              resultadoNotifier: _refeicoesHabituaisNotifier,
              habilitado: !_indoParaConfirmacao,
            );
          },
        ),
      ],
    );
  }

  /// RELATÓRIO 20260922_0002 (Item 1) — "mesma mecânica visual e de
  /// preenchimento da lista de Alergias": mesmos widgets
  /// ([ResumoSelecaoMultipla]/[abrirSeletorMultiplo]), catálogo estático
  /// (o backend guarda `text[]` livre, sem tabela-catálogo) — ao confirmar
  /// a seleção, os `id`s viram o texto traduzido correspondente.
  Widget _buildSecaoRestricoesCulturais(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResumoSelecaoMultipla(
          label: i18n.tr('nutricao.restricoes_culturais_label'),
          quantidadeSelecionada: _restricoesCulturaisSelecionadas.length,
          onEditar: () async {
            final resultado = await abrirSeletorMultiplo(
              context: context,
              titulo: i18n.tr('nutricao.restricoes_culturais_label'),
              itens: [
                for (final codigo in _restricoesCulturaisCodigos)
                  CatalogoItem(id: codigo, nome: i18n.tr('nutricao.restricao_cultural_$codigo')),
              ],
              selecionadosIniciais: _restricoesCulturaisSelecionadas,
            );
            if (resultado != null) {
              setState(() {
                _restricoesCulturaisSelecionadas
                  ..clear()
                  ..addAll(resultado);
              });
            }
          },
        ),
        if (_restricoesCulturaisSelecionadas.contains('outros'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextFormField(
              controller: _restricoesCulturaisOutroController,
              decoration: InputDecoration(
                labelText: i18n.tr('nutricao.restricao_cultural_outros_hint'),
                border: const OutlineInputBorder(),
              ),
              enabled: !_indoParaConfirmacao,
            ),
          ),
      ],
    );
  }

  /// Converte os `id`s selecionados em texto pro `text[]` que o backend
  /// espera — "outros" vira o texto livre digitado (se houver), nunca a
  /// palavra literal "outros".
  List<String> _restricoesCulturaisComoTexto() {
    final resultado = <String>[];
    for (final codigo in _restricoesCulturaisSelecionadas) {
      if (codigo == 'outros') {
        final texto = _restricoesCulturaisOutroController.text.trim();
        if (texto.isNotEmpty) resultado.add(texto);
      } else {
        resultado.add(i18n.tr('nutricao.restricao_cultural_$codigo'));
      }
    }
    return resultado;
  }

  /// Seção 5 — rotina diária (pergunta única, complementar ao NEAT) +
  /// atividade ocupacional.
  Widget _buildSecaoRotinaDiaria(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.rotina_diaria_pergunta'), style: Theme.of(context).textTheme.titleMedium),
        RadioGroup<String>(
          groupValue: _rotinaDiariaSelecionada,
          onChanged: (valor) {
            if (_indoParaConfirmacao) return;
            setState(() => _rotinaDiariaSelecionada = valor);
          },
          child: Column(
            children: [
              for (final opcao in _rotinasDiarias)
                RadioListTile<String>(contentPadding: EdgeInsets.zero, value: opcao, title: Text(i18n.tr('nutricao.rotina_diaria_$opcao'))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _campoTextoOpcional(_atividadeOcupacionalController, i18n.tr('nutricao.atividade_ocupacional_label')),
      ],
    );
  }

  /// RELATÓRIO 20260922_0002 (Item 2) — um único botão cobrindo as 3 seções
  /// pedidas na tarefa (Atividade/Sono/Carga de Treino), já que
  /// `processar_medias_smartwatch` devolve as 3 numa chamada só — a tela de
  /// revisão que abre em seguida ([RevisaoSmartwatchPage]) tem uma seção
  /// dedicada pra cada uma. Some da tela quando a janela não pôde ser
  /// calculada (ver [_carregar]) — nunca trava o preenchimento manual.
  Widget _buildBotaoBuscarSmartwatch(BuildContext context) {
    if (_janelaSmartwatch == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryGold.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.primaryGold.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n.tr('nutricao.smartwatch_botao_titulo'), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            i18n.tr('nutricao.smartwatch_botao_aviso'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (_indoParaConfirmacao || _buscandoSmartwatch) ? null : _buscarDadosRelogio,
            icon: _buscandoSmartwatch
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.watch_outlined),
            label: Text(i18n.tr('nutricao.smartwatch_botao_label')),
          ),
        ],
      ),
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
                '${i18n.tr('nutricao.atividades_minutos', params: {
                      'minutos': atividade.minutos.toString()
                    })} · ${i18n.tr('nutricao.intensidade_${atividade.intensidade}')}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _indoParaConfirmacao ? null : () => setState(() => _atividadesSelecionadas.remove(atividade)),
              ),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _indoParaConfirmacao ? null : () => _abrirModalAdicionarAtividade(diaSemana),
            icon: const Icon(Icons.add),
            label: Text(i18n.tr('nutricao.rotina_dia_add_button')),
          ),
        ),
      ],
    );
  }

  /// Bloco 7 — Sono e recuperação.
  Widget _buildSecaoSono(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.sono_label'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_horasSonoController, i18n.tr('nutricao.sono_horas_medias_label')),
        const SizedBox(height: 8),
        TextFormField(
          controller: _horarioDormirController,
          decoration: InputDecoration(labelText: i18n.tr('nutricao.sono_horario_dormir_label'), hintText: 'HH:mm', border: const OutlineInputBorder()),
          enabled: !_indoParaConfirmacao,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _horarioAcordarController,
          decoration: InputDecoration(labelText: i18n.tr('nutricao.sono_horario_acordar_label'), hintText: 'HH:mm', border: const OutlineInputBorder()),
          enabled: !_indoParaConfirmacao,
        ),
        const SizedBox(height: 8),
        Text(i18n.tr('nutricao.sono_qualidade_label'), style: Theme.of(context).textTheme.bodyMedium),
        RadioGroup<String>(
          groupValue: _qualidadeSonoSelecionada,
          onChanged: (valor) {
            if (_indoParaConfirmacao) return;
            setState(() => _qualidadeSonoSelecionada = valor);
          },
          child: Column(
            children: [
              for (final opcao in _qualidadesSono)
                RadioListTile<String>(contentPadding: EdgeInsets.zero, value: opcao, title: Text(i18n.tr('nutricao.sono_qualidade_$opcao'))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _despertaresController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: i18n.tr('nutricao.sono_despertares_label'), border: const OutlineInputBorder()),
          enabled: !_indoParaConfirmacao,
        ),
      ],
    );
  }

  /// Bloco 8 — "Não tenho" explícito primeiro (RESTRIÇÃO da tarefa), lista
  /// exata só aparece se "Sim, tenho".
  Widget _buildSecaoCondicoes(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.condicoes_pergunta'), style: Theme.of(context).textTheme.titleMedium),
        RadioGroup<bool>(
          groupValue: _possuiCondicaoSaude,
          onChanged: (valor) {
            if (_indoParaConfirmacao) return;
            setState(() {
              _possuiCondicaoSaude = valor;
              if (valor == false) _problemasSaudeSelecionados.clear();
            });
          },
          child: Column(
            children: [
              RadioListTile<bool>(contentPadding: EdgeInsets.zero, value: false, title: Text(i18n.tr('nutricao.condicoes_nao_tenho'))),
              RadioListTile<bool>(contentPadding: EdgeInsets.zero, value: true, title: Text(i18n.tr('nutricao.condicoes_tenho'))),
            ],
          ),
        ),
        if (_possuiCondicaoSaude == true) ...[
          const SizedBox(height: 8),
          if (_problemasSaude.isEmpty)
            Text(i18n.tr('nutricao.problemas_saude_empty'), style: Theme.of(context).textTheme.bodySmall)
          else
            ResumoSelecaoMultipla(
              label: i18n.tr('nutricao.condicoes_selecionar_label'),
              quantidadeSelecionada: _problemasSaudeSelecionados.length,
              onEditar: () async {
                final resultado = await abrirSeletorMultiplo(
                  context: context,
                  titulo: i18n.tr('nutricao.condicoes_selecionar_label'),
                  itens: _problemasSaude,
                  selecionadosIniciais: _problemasSaudeSelecionados,
                );
                if (resultado != null) {
                  setState(() {
                    _problemasSaudeSelecionados
                      ..clear()
                      ..addAll(resultado);
                  });
                }
              },
            ),
        ],
      ],
    );
  }

  Widget _buildBlocoAtleta(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(i18n.tr('nutricao.bloco_atleta_pergunta_ativar'), style: Theme.of(context).textTheme.titleMedium)),
            Switch(
              value: _praticaEsporteEstruturado,
              onChanged: _indoParaConfirmacao ? null : (valor) => setState(() => _praticaEsporteEstruturado = valor),
            ),
          ],
        ),
        if (_praticaEsporteEstruturado) ...[
          _campoTextoOpcional(_atletaModalidadeController, i18n.tr('nutricao.bloco_atleta_modalidade_label')),
          const SizedBox(height: 8),
          _campoNumericoOpcional(_atletaHorasSemanaController, i18n.tr('nutricao.bloco_atleta_horas_semana_label')),
          const SizedBox(height: 8),
          _campoTextoOpcional(_atletaObjetivoEsportivoController, i18n.tr('nutricao.bloco_atleta_objetivo_esportivo_label')),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _atletaCompeticaoProxima,
            title: Text(i18n.tr('nutricao.bloco_atleta_competicao_label')),
            onChanged: _indoParaConfirmacao ? null : (valor) => setState(() => _atletaCompeticaoProxima = valor ?? false),
          ),
        ],
      ],
    );
  }

  Widget _buildBlocoIdoso(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.bloco_idoso_titulo'), style: Theme.of(context).textTheme.titleMedium),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _idosoPerdaPeso,
          title: Text(i18n.tr('nutricao.bloco_idoso_perda_peso_label')),
          onChanged: _indoParaConfirmacao ? null : (valor) => setState(() => _idosoPerdaPeso = valor ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _idosoReducaoForcaMobilidade,
          title: Text(i18n.tr('nutricao.bloco_idoso_forca_mobilidade_label')),
          onChanged: _indoParaConfirmacao ? null : (valor) => setState(() => _idosoReducaoForcaMobilidade = valor ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _idosoDificuldadeAlimentacao,
          title: Text(i18n.tr('nutricao.bloco_idoso_dificuldade_alimentacao_label')),
          onChanged: _indoParaConfirmacao ? null : (valor) => setState(() => _idosoDificuldadeAlimentacao = valor ?? false),
        ),
      ],
    );
  }

  Widget _buildBlocoDiabetes(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.bloco_diabetes_titulo'), style: Theme.of(context).textTheme.titleMedium),
        _campoTextoOpcional(_diabetesTipoController, i18n.tr('nutricao.bloco_diabetes_tipo_label')),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _diabetesUsaInsulina,
          title: Text(i18n.tr('nutricao.bloco_diabetes_insulina_label')),
          onChanged: _indoParaConfirmacao ? null : (valor) => setState(() => _diabetesUsaInsulina = valor ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _diabetesUsaMedicamento,
          title: Text(i18n.tr('nutricao.bloco_diabetes_medicamento_label')),
          onChanged: _indoParaConfirmacao ? null : (valor) => setState(() => _diabetesUsaMedicamento = valor ?? false),
        ),
        _campoTextoOpcional(_diabetesHba1cController, i18n.tr('nutricao.bloco_diabetes_hba1c_label')),
      ],
    );
  }

  Widget _buildBlocoRenal(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.bloco_renal_titulo'), style: Theme.of(context).textTheme.titleMedium),
        _campoTextoOpcional(_renalEstagioController, i18n.tr('nutricao.bloco_renal_estagio_label')),
        const SizedBox(height: 8),
        _campoTextoOpcional(_renalTfgController, i18n.tr('nutricao.bloco_renal_tfg_label')),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _renalFazDialise,
          title: Text(i18n.tr('nutricao.bloco_renal_dialise_label')),
          onChanged: _indoParaConfirmacao ? null : (valor) => setState(() => _renalFazDialise = valor ?? false),
        ),
      ],
    );
  }

  Widget _buildBlocoRecomposicao(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i18n.tr('nutricao.bloco_recomposicao_titulo'), style: Theme.of(context).textTheme.titleMedium),
        _campoNumericoOpcional(_recomposicaoPercentualAtualController, i18n.tr('nutricao.bloco_recomposicao_percentual_atual_label')),
        const SizedBox(height: 8),
        _campoNumericoOpcional(_recomposicaoPercentualDesejadoController, i18n.tr('nutricao.bloco_recomposicao_percentual_desejado_label')),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _recomposicaoTreinamentoResistido,
          title: Text(i18n.tr('nutricao.bloco_recomposicao_treinamento_resistido_label')),
          onChanged: _indoParaConfirmacao ? null : (valor) => setState(() => _recomposicaoTreinamentoResistido = valor ?? false),
        ),
      ],
    );
  }

  Widget _buildSecaoAlergias(BuildContext context) {
    if (_alergias.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n.tr('nutricao.alergias_label'), style: Theme.of(context).textTheme.titleMedium),
          Text(i18n.tr('nutricao.alergias_empty'), style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }
    return ResumoSelecaoMultipla(
      label: i18n.tr('nutricao.alergias_label'),
      quantidadeSelecionada: _alergiasSelecionadas.length,
      onEditar: () async {
        final resultado = await abrirSeletorMultiplo(
          context: context,
          titulo: i18n.tr('nutricao.alergias_label'),
          itens: _alergias,
          selecionadosIniciais: _alergiasSelecionadas,
        );
        if (resultado != null) {
          setState(() {
            _alergiasSelecionadas
              ..clear()
              ..addAll(resultado);
          });
        }
      },
    );
  }

  Widget _campoTextoOpcional(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      enabled: !_indoParaConfirmacao,
    );
  }

  Widget _campoNumericoOpcional(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      enabled: !_indoParaConfirmacao,
    );
  }

  /// dd/mm/aaaa — mesmo padrão simples de `meta_bem_estar_page.dart`.
  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }
}

/// Modal "Adicionar Atividade" — dropdown de modalidade (ALFABÉTICA — já
/// vem ordenada de `buscarTiposAtividades`, `.order('nome_exibicao')`) com
/// busca + Intensidade obrigatória (RESTRIÇÃO explícita da tarefa).
class _ModalAdicionarAtividade extends StatefulWidget {
  const _ModalAdicionarAtividade({required this.opcoes, required this.diaSemana});

  final List<TipoAtividadeItem> opcoes;
  final int diaSemana;

  @override
  State<_ModalAdicionarAtividade> createState() => _ModalAdicionarAtividadeState();
}

class _ModalAdicionarAtividadeState extends State<_ModalAdicionarAtividade> {
  final _minutosController = TextEditingController();
  final _buscaController = TextEditingController();
  TipoAtividadeItem? _tipoSelecionado;
  String _intensidadeSelecionada = 'moderada';
  String? _erroMinutos;

  List<TipoAtividadeItem> get _opcoesFiltradas {
    final busca = _buscaController.text.trim().toLowerCase();
    if (busca.isEmpty) return widget.opcoes;
    return widget.opcoes.where((o) => o.nomeExibicao.toLowerCase().contains(busca)).toList();
  }

  @override
  void dispose() {
    _minutosController.dispose();
    _buscaController.dispose();
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
        intensidade: _intensidadeSelecionada,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(i18n.tr('nutricao.atividades_modal_title_dia', params: {'dia': i18n.tr('nutricao.dia_semana_${widget.diaSemana}')})),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _buscaController,
              decoration: InputDecoration(
                labelText: i18n.tr('nutricao.atividades_modal_busca_hint'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_opcoesFiltradas.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(i18n.tr('nutricao.atividades_modal_busca_vazio')),
              )
            else
              DropdownButtonFormField<TipoAtividadeItem>(
                initialValue: _opcoesFiltradas.contains(_tipoSelecionado) ? _tipoSelecionado : null,
                decoration: InputDecoration(labelText: i18n.tr('nutricao.atividades_modal_tipo_label')),
                items: [
                  for (final opcao in _opcoesFiltradas) DropdownMenuItem(value: opcao, child: Text(opcao.nomeExibicao)),
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
            const SizedBox(height: 16),
            Text(i18n.tr('nutricao.atividades_modal_intensidade_label'), style: Theme.of(context).textTheme.bodyMedium),
            RadioGroup<String>(
              groupValue: _intensidadeSelecionada,
              onChanged: (valor) => setState(() => _intensidadeSelecionada = valor ?? 'moderada'),
              child: Row(
                children: [
                  for (final intensidade in _intensidades)
                    Expanded(
                      child: RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: intensidade,
                        title: Text(i18n.tr('nutricao.intensidade_$intensidade')),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n.tr('nutricao.atividades_modal_cancel'))),
        FilledButton(onPressed: _confirmar, child: Text(i18n.tr('nutricao.atividades_modal_confirm'))),
      ],
    );
  }
}
