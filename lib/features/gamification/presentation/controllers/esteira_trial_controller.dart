import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Snapshot of where the user stands on the "Esteira dos 14 Dias Free" (A
/// Cenoura) trial ladder. Immutable; rebuilt by [EsteiraTrialController]
/// every time the signup date, the freeze toggle, or a Semana 1 mission
/// flag changes.
@immutable
class EsteiraTrialState {
  /// 1-14, clamped. While [modoRecuperacaoAtivo] is true this stays fixed
  /// at whatever day it was on the moment the freeze started — see
  /// [EsteiraTrialController.ativarModoRecuperacao].
  final int diaAtual;
  final bool modoRecuperacaoAtivo;
  final bool metaMovimentoCumprida;

  /// Which of the 6 daily exam-upload missions (Dias 1-6) have already
  /// been completed.
  final Set<int> missoesExamesConcluidas;

  /// True until the persisted state has finished loading from secure
  /// storage — [diaAtual] defaults to 1 during this window.
  final bool carregando;

  const EsteiraTrialState({
    this.diaAtual = 1,
    this.modoRecuperacaoAtivo = false,
    this.metaMovimentoCumprida = false,
    this.missoesExamesConcluidas = const {},
    this.carregando = true,
  });

  bool get uploadExamesSemana1Cumprido => missoesExamesConcluidas.isNotEmpty;

  /// Semana 1 = metas de movimento cumpridas + ao menos um exame antigo
  /// anexado.
  bool get missoesSemana1Completas =>
      metaMovimentoCumprida && uploadExamesSemana1Cumprido;

  /// Gatilho do Dia 7: só liga a partir do 7º dia do trial *e* com a
  /// Semana 1 inteira cumprida — nunca antes de qualquer uma das duas
  /// condições, mesmo que o trial já tenha passado do Dia 7.
  bool get gatilhoDia7Ativo => diaAtual >= 7 && missoesSemana1Completas;

  int get diasRestantes => (14 - diaAtual).clamp(0, 13);
}

/// Drives the "Esteira dos 14 Dias Free" (A Cenoura): the day-by-day trial
/// countdown that gates the Dia 7 conversion teaser (`TeaserConversaoPage`)
/// and the Semana 1 exam-upload missions (`MissoesExamesPage`).
///
/// Regra de Congelamento: turning on "Modo Recuperação Humano" (injury or
/// illness) freezes the day counter in place instead of resetting it. This
/// is implemented by shifting an internal, persisted anchor date forward
/// by exactly the number of calendar days spent frozen, the instant
/// recovery mode is turned back off — the counter resumes exactly where it
/// left off, and the 14-day window stretches by the same amount, so the
/// user never loses trial days to being sick (desbloqueio posterior dentro
/// do trial).
class EsteiraTrialController extends ValueNotifier<EsteiraTrialState> {
  EsteiraTrialController({
    required DateTime dataCadastro,
    FlutterSecureStorage? secureStorage,
    DateTime Function()? relogio,
  })  : _dataCadastroReal = _dataOnly(dataCadastro),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _relogio = relogio ?? DateTime.now,
        _ancoraEfetiva = _dataOnly(dataCadastro),
        super(const EsteiraTrialState()) {
    _carregarEInicializar();
  }

  final DateTime _dataCadastroReal;
  final FlutterSecureStorage _secureStorage;
  final DateTime Function() _relogio;

  DateTime _ancoraEfetiva;
  bool _recuperacaoAtiva = false;
  DateTime? _congeladoDesde;
  bool _metaMovimentoCumprida = false;
  Set<int> _missoesExamesConcluidas = {};

  static const int _diasTotalTrial = 14;

  static const String _keyAncora = 'esteira_trial_ancora_efetiva';
  static const String _keyRecuperacaoAtiva = 'esteira_trial_recuperacao_ativa';
  static const String _keyCongeladoDesde = 'esteira_trial_congelado_desde';
  static const String _keyMetaMovimento = 'esteira_trial_meta_movimento';
  static const String _keyMissoesExames = 'esteira_trial_missoes_exames';

  Future<void> _carregarEInicializar() async {
    final ancoraSalva = await _secureStorage.read(key: _keyAncora);
    _ancoraEfetiva = ancoraSalva != null
        ? _dataOnly(DateTime.parse(ancoraSalva))
        : _dataCadastroReal;
    if (ancoraSalva == null) {
      await _secureStorage.write(
        key: _keyAncora,
        value: _ancoraEfetiva.toIso8601String(),
      );
    }

    _recuperacaoAtiva =
        (await _secureStorage.read(key: _keyRecuperacaoAtiva)) == 'true';

    final congeladoRaw = await _secureStorage.read(key: _keyCongeladoDesde);
    _congeladoDesde =
        congeladoRaw != null ? DateTime.parse(congeladoRaw) : null;

    _metaMovimentoCumprida =
        (await _secureStorage.read(key: _keyMetaMovimento)) == 'true';

    final missoesRaw = await _secureStorage.read(key: _keyMissoesExames);
    _missoesExamesConcluidas = missoesRaw != null
        ? (jsonDecode(missoesRaw) as List<dynamic>)
            .map((e) => e as int)
            .toSet()
        : <int>{};

    _recalcular();
  }

  /// Regra de Congelamento (parte 1): trava o contador no dia atual em vez
  /// de zerar. Chamado quando o "Modo Recuperação Humano" é ativado
  /// (lesão/doença) — normalmente a partir de um toggle em outra tela.
  Future<void> ativarModoRecuperacao() async {
    if (_recuperacaoAtiva) return;
    _recuperacaoAtiva = true;
    _congeladoDesde = _dataOnly(_relogio());
    await _persistirRecuperacao();
    _recalcular();
  }

  /// Regra de Congelamento (parte 2): ao desligar, empurra a âncora do
  /// trial para frente pelo número exato de dias que ficou congelado — o
  /// contador retoma de onde parou, sem pular nem zerar.
  Future<void> desativarModoRecuperacao() async {
    if (!_recuperacaoAtiva || _congeladoDesde == null) return;
    final diasCongelado =
        _dataOnly(_relogio()).difference(_congeladoDesde!).inDays;
    _ancoraEfetiva = _ancoraEfetiva.add(Duration(days: diasCongelado));
    _recuperacaoAtiva = false;
    _congeladoDesde = null;
    await _secureStorage.write(
      key: _keyAncora,
      value: _ancoraEfetiva.toIso8601String(),
    );
    await _persistirRecuperacao();
    _recalcular();
  }

  Future<void> _persistirRecuperacao() async {
    await _secureStorage.write(
      key: _keyRecuperacaoAtiva,
      value: _recuperacaoAtiva.toString(),
    );
    final congeladoDesde = _congeladoDesde;
    if (congeladoDesde != null) {
      await _secureStorage.write(
        key: _keyCongeladoDesde,
        value: congeladoDesde.toIso8601String(),
      );
    } else {
      await _secureStorage.delete(key: _keyCongeladoDesde);
    }
  }

  /// Marca a meta de movimento da Semana 1 como cumprida — junto com o
  /// upload de exame, libera o Gatilho do Dia 7.
  Future<void> registrarMetaMovimentoCumprida() async {
    if (_metaMovimentoCumprida) return;
    _metaMovimentoCumprida = true;
    await _secureStorage.write(key: _keyMetaMovimento, value: 'true');
    _recalcular();
  }

  /// Marca a missão de upload de exame do [dia] (1-6) como concluída —
  /// chamado pela tela de missões após cada envio bem-sucedido.
  Future<void> registrarMissaoExameConcluida(int dia) async {
    if (_missoesExamesConcluidas.contains(dia)) return;
    _missoesExamesConcluidas = {..._missoesExamesConcluidas, dia};
    await _secureStorage.write(
      key: _keyMissoesExames,
      value: jsonEncode(_missoesExamesConcluidas.toList()),
    );
    _recalcular();
  }

  void _recalcular() {
    final referencia = (_recuperacaoAtiva && _congeladoDesde != null)
        ? _congeladoDesde!
        : _dataOnly(_relogio());
    final diasDecorridos = referencia.difference(_ancoraEfetiva).inDays;
    final diaAtual = (diasDecorridos + 1).clamp(1, _diasTotalTrial);

    value = EsteiraTrialState(
      diaAtual: diaAtual,
      modoRecuperacaoAtivo: _recuperacaoAtiva,
      metaMovimentoCumprida: _metaMovimentoCumprida,
      missoesExamesConcluidas: _missoesExamesConcluidas,
      carregando: false,
    );
  }

  static DateTime _dataOnly(DateTime data) =>
      DateTime(data.year, data.month, data.day);
}
