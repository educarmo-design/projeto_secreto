import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/esteira_trial_controller.dart';

class _MissaoExameDefinicao {
  final int dia;
  final String exameKey;
  final int pontos;

  const _MissaoExameDefinicao({
    required this.dia,
    required this.exameKey,
    required this.pontos,
  });
}

/// Semana 1 da Esteira: um exame antigo por dia, Dias 1-6. Cada envio bem
/// sucedido chama [EsteiraTrialController.registrarMissaoExameConcluida],
/// que junto com a meta de movimento libera o Gatilho do Dia 7.
const List<_MissaoExameDefinicao> _missoesSemana1 = [
  _MissaoExameDefinicao(
    dia: 1,
    exameKey: 'gamification.missoes_exames_exame_dia_1',
    pontos: 150,
  ),
  _MissaoExameDefinicao(
    dia: 2,
    exameKey: 'gamification.missoes_exames_exame_dia_2',
    pontos: 150,
  ),
  _MissaoExameDefinicao(
    dia: 3,
    exameKey: 'gamification.missoes_exames_exame_dia_3',
    pontos: 180,
  ),
  _MissaoExameDefinicao(
    dia: 4,
    exameKey: 'gamification.missoes_exames_exame_dia_4',
    pontos: 180,
  ),
  _MissaoExameDefinicao(
    dia: 5,
    exameKey: 'gamification.missoes_exames_exame_dia_5',
    pontos: 200,
  ),
  _MissaoExameDefinicao(
    dia: 6,
    exameKey: 'gamification.missoes_exames_exame_dia_6',
    pontos: 220,
  ),
];

/// Lista competitiva de missões diárias (Dias 1-6): convida o usuário a
/// anexar exames antigos em PDF, um por dia, cada um valendo pontos na
/// Liga Cidade. Cada card só desbloqueia quando `diaAtual` alcança o dia
/// da missão — "de forma fracionada", nunca tudo de uma vez.
class MissoesExamesPage extends StatefulWidget {
  const MissoesExamesPage({
    super.key,
    required this.controller,
    this.httpClient,
    this.selecionarArquivo,
    this.obterSessaoAtual,
  });

  final EsteiraTrialController controller;

  /// Injetável para testes; em produção cada instância da página cria e
  /// fecha seu próprio client.
  final http.Client? httpClient;

  /// Injetável para testes — evita abrir o seletor nativo do
  /// `file_picker` (que depende de canais de plataforma indisponíveis em
  /// `flutter test`). Em produção abre o seletor real via
  /// [_selecionarArquivoPadrao]. Retorna `null` quando o usuário cancela.
  final Future<PlatformFile?> Function()? selecionarArquivo;

  /// Injetável para testes — evita depender do singleton
  /// `Supabase.instance`, que precisa de `Supabase.initialize()` para
  /// existir. Em produção lê a sessão real via [_obterSessaoAtualPadrao].
  final Session? Function()? obterSessaoAtual;

  @override
  State<MissoesExamesPage> createState() => _MissoesExamesPageState();
}

class _MissoesExamesPageState extends State<MissoesExamesPage> {
  late final http.Client _httpClient = widget.httpClient ?? http.Client();
  late final Future<PlatformFile?> Function() _selecionarArquivo =
      widget.selecionarArquivo ?? _selecionarArquivoPadrao;
  late final Session? Function() _obterSessaoAtual =
      widget.obterSessaoAtual ?? _obterSessaoAtualPadrao;

  static Session? _obterSessaoAtualPadrao() =>
      Supabase.instance.client.auth.currentSession;

  static const Duration _uploadTimeout = Duration(seconds: 30);

  final Map<int, bool> _enviando = {};
  final Map<int, String?> _erros = {};

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  static Future<PlatformFile?> _selecionarArquivoPadrao() async {
    final resultado = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    return resultado != null && resultado.files.isNotEmpty
        ? resultado.files.first
        : null;
  }

  /// Fluxo RAM volátil (Zero Storage Pipeline): `file_picker` com
  /// `withData: true` entrega os bytes do PDF direto na memória, sem
  /// gravar nada em disco; os bytes vivem só na variável local [bytes] e
  /// são descartados assim que o upload termina — sucesso ou falha.
  Future<void> _anexarExame(int dia) async {
    if (_enviando[dia] == true) return;

    setState(() {
      _enviando[dia] = true;
      _erros[dia] = null;
    });

    Uint8List? bytes;
    try {
      final arquivo = await _selecionarArquivo();
      bytes = arquivo?.bytes;

      if (bytes == null) {
        // Usuário cancelou o seletor de arquivos.
        if (mounted) setState(() => _enviando[dia] = false);
        return;
      }

      final session = _obterSessaoAtual();
      final response = await _httpClient
          .post(
            Uri.parse(AppConfig.examUploadEndpoint),
            headers: {
              'apikey': AppConfig.supabaseAnonKey,
              if (session != null)
                'Authorization': 'Bearer ${session.accessToken}',
              'Content-Type': 'application/pdf',
              'X-Missao-Dia': dia.toString(),
              'X-Arquivo-Nome': arquivo!.name,
            },
            body: bytes,
          )
          .timeout(_uploadTimeout);

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _enviando[dia] = false;
          _erros[dia] = i18n.tr('gamification.missoes_exames_erro_upload');
        });
        return;
      }

      await widget.controller.registrarMissaoExameConcluida(dia);
      if (!mounted) return;
      setState(() => _enviando[dia] = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando[dia] = false;
        _erros[dia] = i18n.tr('gamification.missoes_exames_erro_upload');
      });
    } finally {
      bytes = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.darkBg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(i18n.tr('gamification.missoes_exames_title')),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<EsteiraTrialState>(
          valueListenable: widget.controller,
          builder: (context, state, _) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  i18n.tr('gamification.missoes_exames_subtitle'),
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 16,
                      color: AppColors.primaryGold,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        i18n.tr('gamification.missoes_exames_zero_storage_note'),
                        style: const TextStyle(
                          color: AppColors.primaryGold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                for (final missao in _missoesSemana1) ...[
                  _MissaoExameCard(
                    missao: missao,
                    diaAtual: state.diaAtual,
                    concluida: state.missoesExamesConcluidas.contains(missao.dia),
                    enviando: _enviando[missao.dia] ?? false,
                    erro: _erros[missao.dia],
                    onAnexar: () => _anexarExame(missao.dia),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MissaoExameCard extends StatelessWidget {
  const _MissaoExameCard({
    required this.missao,
    required this.diaAtual,
    required this.concluida,
    required this.enviando,
    required this.erro,
    required this.onAnexar,
  });

  final _MissaoExameDefinicao missao;
  final int diaAtual;
  final bool concluida;
  final bool enviando;
  final String? erro;
  final VoidCallback onAnexar;

  bool get _bloqueada => missao.dia > diaAtual;

  @override
  Widget build(BuildContext context) {
    final corDestaque = concluida
        ? AppColors.success
        : (_bloqueada ? Colors.white24 : AppColors.primaryGold);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: corDestaque.withValues(alpha: _bloqueada ? 0.2 : 0.6),
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: corDestaque.withValues(alpha: 0.15),
            ),
            child: concluida
                ? const Icon(Icons.check_rounded, color: AppColors.success)
                : _bloqueada
                    ? const Icon(
                        Icons.lock_outline,
                        color: Colors.white38,
                        size: 18,
                      )
                    : Text(
                        '${missao.dia}',
                        style: const TextStyle(
                          color: AppColors.primaryGold,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n.tr(
                    'gamification.missoes_exames_dia_label',
                    params: {'dia': missao.dia.toString()},
                  ),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  i18n.tr(
                    'gamification.missoes_exames_card_titulo',
                    params: {'exame': i18n.tr(missao.exameKey)},
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  i18n.tr(
                    'gamification.missoes_exames_card_pontos',
                    params: {'pontos': missao.pontos.toString()},
                  ),
                  style: const TextStyle(
                    color: AppColors.primaryGold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                if (concluida)
                  Text(
                    i18n.tr('gamification.missoes_exames_concluida'),
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (_bloqueada)
                  Text(
                    i18n.tr(
                      'gamification.missoes_exames_bloqueada',
                      params: {'dia': missao.dia.toString()},
                    ),
                    style: const TextStyle(color: Colors.white38),
                  )
                else
                  FilledButton.icon(
                    onPressed: enviando ? null : onAnexar,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryGold,
                      foregroundColor: Colors.black,
                    ),
                    icon: enviando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.attach_file, size: 18),
                    label: Text(
                      enviando
                          ? i18n.tr('gamification.missoes_exames_uploading')
                          : i18n.tr('gamification.missoes_exames_upload_button'),
                    ),
                  ),
                if (erro != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    erro!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
