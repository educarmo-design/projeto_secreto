import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/perfil_usuario_repository.dart';

enum _CargaStatus { carregando, sucesso, erro }

/// Tela de Perfil do Usuário (RELATÓRIO 20260810_0006, decisão do
/// fundador) — nascida para editar `altura_cm`. RELATÓRIO 20260916_0001
/// (SSOT, docs/motor_metabolico.txt): a altura PAROU de ser editável aqui —
/// `perfis_usuarios.altura_cm` foi removida, a única forma de mudar a
/// altura oficial agora é preencher uma anamnese nova
/// (`lib/features/nutricao/`). Esta tela mostra a altura da última
/// anamnese como TEXTO (não mais um campo editável) e continua editando
/// data de nascimento/sexo biológico, que não fizeram parte da remoção.
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

  _CargaStatus _status = _CargaStatus.carregando;
  bool _salvando = false;

  /// `null` até o usuário escolher uma data nova ou uma já cadastrada ser
  /// carregada — distingue "ainda não mexeu no campo" (não reenviar nada
  /// no salvar) de "escolheu uma data".
  DateTime? _dataNascimentoSelecionada;

  /// N07 (RELATÓRIO 20260812_0008) — mesma convenção de
  /// [_dataNascimentoSelecionada]: `null` = "ainda não informado", não
  /// "erro".
  SexoBiologico? _sexoBiologicoSelecionado;

  /// RELATÓRIO 20260916_0001 — altura da ÚLTIMA ANAMNESE (SSOT), somente
  /// leitura nesta tela. `null` = usuário nunca preencheu uma anamnese com
  /// altura ainda (não é erro).
  double? _alturaCmDaAnamnese;

  /// RELATÓRIO 20260812_0011 — última leitura de peso (do wearable, nunca
  /// digitada nesta tela) usada só pra calcular o IMC exibido ao lado da
  /// altura. `null` = nenhum peso sincronizado ainda (não é erro).
  PesoRecente? _pesoRecente;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  /// IMC = peso (kg) / altura (m)². `null` com segurança total de tipos
  /// sempre que faltar QUALQUER um dos dois insumos — RELATÓRIO
  /// 20260812_0011, achado da auditoria: esta conversão simplesmente não
  /// existia em lugar nenhum do app antes daquela tarefa (o único IMC
  /// exibido era o valor bruto pré-calculado no sync, em
  /// `historico_telemetria_page.dart`). RELATÓRIO 20260916_0001: a altura
  /// não é mais digitada nesta tela — vem de [_alturaCmDaAnamnese], fixa
  /// até o próximo `_carregar()` (não recalcula "ao vivo" por dígito, já
  /// que não há mais campo editável).
  double? get _imcCalculado {
    final pesoKg = _pesoRecente?.pesoKg;
    final alturaCm = _alturaCmDaAnamnese;
    if (pesoKg == null || alturaCm == null || alturaCm <= 0) return null;

    final alturaM = alturaCm / 100; // cm -> m, a conversão que faltava.
    return pesoKg / (alturaM * alturaM);
  }

  Future<void> _carregar() async {
    setState(() => _status = _CargaStatus.carregando);
    try {
      final alturaCm = await _repository.buscarAlturaCmDaUltimaAnamnese();
      final dataNascimento = await _repository.buscarDataNascimento();
      final sexoBiologico = await _repository.buscarSexoBiologico();
      final pesoRecente = await _repository.buscarUltimoPesoKg();
      if (!mounted) return;
      setState(() {
        _alturaCmDaAnamnese = alturaCm;
        _dataNascimentoSelecionada = dataNascimento;
        _sexoBiologicoSelecionado = sexoBiologico;
        _pesoRecente = pesoRecente;
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

  Widget _buildAlturaSomenteLeitura(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: i18n.tr('perfil_fisico.altura_label'),
        border: const OutlineInputBorder(),
        enabled: false,
      ),
      child: Text(
        _alturaCmDaAnamnese == null
            ? i18n.tr('perfil_fisico.altura_leitura_vazio')
            : '${_formatarAltura(_alturaCmDaAnamnese!)} cm',
      ),
    );
  }

  static String _formatarAltura(double alturaCm) {
    return alturaCm == alturaCm.roundToDouble()
        ? alturaCm.toStringAsFixed(0)
        : alturaCm.toStringAsFixed(1);
  }

  Widget _buildImcAoVivo(BuildContext context) {
    final imc = _imcCalculado;
    final estilo = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText);

    if (_pesoRecente == null) {
      return Text(i18n.tr('perfil_fisico.imc_sem_peso'), style: estilo);
    }
    if (imc == null) {
      return Text(i18n.tr('perfil_fisico.imc_aguardando_altura'), style: estilo);
    }

    return Text(
      i18n.tr('perfil_fisico.imc_valor', params: {
        'imc': imc.toStringAsFixed(1),
        'data': _formatarData(_pesoRecente!.dataReferencia),
      }),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  /// dd/mm/aaaa — sem `intl`, só concatenação com zero à esquerda (mesmo
  /// padrão simples já usado nesta tela para evitar dependência nova).
  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // N03 — validação de UX, espelhando a CHECK constraint
    // `perfis_usuarios_maioridade` do banco (a barreira real). Se o campo
    // nunca foi preenchido (usuário antigo, sem data de nascimento salva
    // ainda), não bloqueia o salvamento — só valida quando há uma data
    // selecionada.
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

    setState(() => _salvando = true);
    try {
      if (dataNascimento != null) {
        await _repository.atualizarDataNascimento(dataNascimento);
      }
      final sexoBiologico = _sexoBiologicoSelecionado;
      if (sexoBiologico != null) {
        await _repository.atualizarSexoBiologico(sexoBiologico);
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
                // RELATÓRIO 20260916_0001 — SSOT: altura não é mais editável
                // aqui, só exibida (a única forma de mudar é preencher uma
                // Anamnese nova).
                _buildAlturaSomenteLeitura(context),
                const SizedBox(height: 8),
                _buildImcAoVivo(context),
                const SizedBox(height: 16),
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
                // N07 (RELATÓRIO 20260812_0008) — insumo do Motor
                // Metabólico (Mifflin-St Jeor). Regra 14: RadioGroup cru,
                // mesmo padrão de `anamnese_self_service_page.dart`.
                Text(
                  i18n.tr('perfil_fisico.sexo_biologico_label'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                RadioGroup<SexoBiologico>(
                  groupValue: _sexoBiologicoSelecionado,
                  onChanged: (valor) {
                    if (_salvando) return;
                    setState(() => _sexoBiologicoSelecionado = valor);
                  },
                  child: Column(
                    children: [
                      RadioListTile<SexoBiologico>(
                        contentPadding: EdgeInsets.zero,
                        value: SexoBiologico.masculino,
                        title: Text(i18n.tr('perfil_fisico.sexo_biologico_masculino')),
                      ),
                      RadioListTile<SexoBiologico>(
                        contentPadding: EdgeInsets.zero,
                        value: SexoBiologico.feminino,
                        title: Text(i18n.tr('perfil_fisico.sexo_biologico_feminino')),
                      ),
                    ],
                  ),
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
