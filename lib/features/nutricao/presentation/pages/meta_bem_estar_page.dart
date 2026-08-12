import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/meta_bem_estar_repository.dart';

const _carenciaDias = 30;

enum _CargaStatus { carregando, erro, bloqueadaCarencia, bloqueadaProfissional, formulario }

/// N11 (RELATÓRIO 20260812_0010) — Meta de Bem-Estar self-service. Toda
/// gravação passa pelo Motor de Exceções (N08, RPC `validar_e_salvar_meta`
/// com `p_is_profissional: false`) — diferente da Prescrição Profissional
/// (N10, Painel Web), aqui uma meta fora da faixa de segurança é
/// BLOQUEADA (Trava ANVISA), nunca só um aviso.
///
/// Regra 14 (Parte 0): "Validação = completa funcionalmente, crua
/// visualmente" — sem carrossel/ilustração.
///
/// Duas travas de UX (a barreira REAL das duas é o banco, ver o RPC):
///   - Carência: 1x a cada 30 dias — bloqueia a tela inteira ANTES de
///     deixar preencher, mostrando quando libera de novo.
///   - Prioridade B2B: se um profissional já tem uma meta ATIVA pra este
///     usuário, a tela nem mostra o formulário — mostra a meta vigente e
///     explica que só o profissional pode mudá-la.
class MetaBemEstarPage extends StatefulWidget {
  const MetaBemEstarPage({super.key, MetaBemEstarRepository? repository})
      : _repository = repository;

  final MetaBemEstarRepository? _repository;

  @override
  State<MetaBemEstarPage> createState() => _MetaBemEstarPageState();
}

class _MetaBemEstarPageState extends State<MetaBemEstarPage> {
  late final MetaBemEstarRepository _repository =
      widget._repository ?? MetaBemEstarRepository();

  final _formKey = GlobalKey<FormState>();
  final _caloriasController = TextEditingController();
  final _proteinaController = TextEditingController();
  final _carboController = TextEditingController();
  final _gorduraController = TextEditingController();

  _CargaStatus _status = _CargaStatus.carregando;
  bool _salvando = false;
  double? _sugestaoCalorias;
  DateTime? _dataProximaLiberacao;
  MetaResumo? _metaDoProfissional;

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
      // Prioridade B2B primeiro — se o profissional tem uma meta ativa,
      // nem importa a carência: a tela trava do mesmo jeito.
      final metaProfissional = await _repository.buscarMetaAtivaDoProfissional();
      if (metaProfissional != null) {
        if (!mounted) return;
        setState(() {
          _metaDoProfissional = metaProfissional;
          _status = _CargaStatus.bloqueadaProfissional;
        });
        return;
      }

      final ultimaMetaPropria = await _repository.buscarMinhaUltimaMetaPropria();
      if (ultimaMetaPropria != null) {
        final liberaEm = ultimaMetaPropria.dataCriacao.add(const Duration(days: _carenciaDias));
        if (liberaEm.isAfter(DateTime.now())) {
          if (!mounted) return;
          setState(() {
            _dataProximaLiberacao = liberaEm;
            _status = _CargaStatus.bloqueadaCarencia;
          });
          return;
        }
      }

      final sugestao = await _repository.buscarSugestaoCalorias();
      if (!mounted) return;
      setState(() {
        _sugestaoCalorias = sugestao;
        _status = _CargaStatus.formulario;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CargaStatus.erro);
    }
  }

  void _usarSugestao() {
    final sugestao = _sugestaoCalorias;
    if (sugestao == null) return;
    setState(() => _caloriasController.text = sugestao.round().toString());
  }

  String? _validarCalorias(String? valor) {
    final texto = valor?.trim() ?? '';
    if (texto.isEmpty) {
      return i18n.tr('nutricao.meta_calorias_validation_empty');
    }
    final numero = int.tryParse(texto);
    if (numero == null || numero <= 0) {
      return i18n.tr('nutricao.meta_calorias_validation_invalid');
    }
    return null;
  }

  int? _parseOpcional(String texto) {
    final limpo = texto.trim();
    return limpo.isEmpty ? null : int.tryParse(limpo);
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _salvando = true);
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
      // A meta acabou de consumir a cota do mês — recarrega pra tela virar
      // "bloqueadaCarencia" sozinha, sem precisar sair e voltar.
      await _carregar();
    } on MetaBloqueadaException catch (erro) {
      if (!mounted) return;
      await _mostrarModalBloqueio(erro);
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
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Trava ANVISA (Hard Block) — modal vermelho, mesmo pros casos de
  /// corrida (`N08_PRIORIDADE_PROFISSIONAL`/`N08_CARENCIA_MENSAL` que a
  /// tela já deveria ter barrado antes de mostrar o formulário, mas o
  /// banco é sempre a fonte da verdade final).
  Future<void> _mostrarModalBloqueio(MetaBloqueadaException erro) async {
    final titulo = switch (erro.motivo) {
      MotivoBloqueioN08.travaClinica => i18n.tr('nutricao.meta_bloqueio_clinico_titulo'),
      MotivoBloqueioN08.prioridadeProfissional => i18n.tr('nutricao.meta_bloqueio_profissional_titulo'),
      MotivoBloqueioN08.carenciaMensal => i18n.tr('nutricao.meta_bloqueio_carencia_titulo'),
      MotivoBloqueioN08.outro => i18n.tr('nutricao.meta_save_error'),
    };
    final mensagem = switch (erro.motivo) {
      MotivoBloqueioN08.travaClinica => i18n.tr('nutricao.meta_bloqueio_clinico_mensagem'),
      MotivoBloqueioN08.prioridadeProfissional => i18n.tr('nutricao.meta_bloqueio_profissional_mensagem'),
      MotivoBloqueioN08.carenciaMensal => i18n.tr('nutricao.meta_bloqueio_carencia_mensagem'),
      MotivoBloqueioN08.outro => erro.mensagemOriginal,
    };

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.block, color: AppColors.error, size: 32),
        title: Text(titulo, style: const TextStyle(color: AppColors.error)),
        content: Text(mensagem),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(i18n.tr('nutricao.meta_bloqueio_confirmar')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('nutricao.meta_bem_estar_title'))),
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
                  i18n.tr('nutricao.meta_load_error'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _carregar,
                  child: Text(i18n.tr('nutricao.meta_save_button')),
                ),
              ],
            ),
          ),
        );
      case _CargaStatus.bloqueadaCarencia:
        return _buildBloqueio(
          context,
          icone: Icons.lock_clock_outlined,
          titulo: i18n.tr('nutricao.meta_carencia_titulo'),
          mensagem: i18n.tr(
            'nutricao.meta_carencia_mensagem',
            params: {'data': _formatarData(_dataProximaLiberacao!)},
          ),
        );
      case _CargaStatus.bloqueadaProfissional:
        return _buildBloqueio(
          context,
          icone: Icons.medical_services_outlined,
          titulo: i18n.tr('nutricao.meta_acompanhamento_titulo'),
          mensagem: i18n.tr('nutricao.meta_acompanhamento_mensagem'),
          meta: _metaDoProfissional,
        );
      case _CargaStatus.formulario:
        return _buildFormulario(context);
    }
  }

  Widget _buildBloqueio(
    BuildContext context, {
    required IconData icone,
    required String titulo,
    required String mensagem,
    MetaResumo? meta,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: AppColors.mutedText),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.mutedText),
            ),
            if (meta != null) ...[
              const SizedBox(height: 24),
              Text(
                '${meta.caloriasAlvo} kcal',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                'P ${meta.proteinaG ?? '—'}g · C ${meta.carboG ?? '—'}g · G ${meta.gorduraG ?? '—'}g',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.mutedText),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormulario(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            Text(
              i18n.tr('nutricao.meta_bem_estar_subtitle'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.mutedText),
            ),
            const SizedBox(height: 24),
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
              enabled: !_salvando,
            ),
            if (_sugestaoCalorias != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _salvando ? null : _usarSugestao,
                  child: Text(
                    i18n.tr(
                      'nutricao.meta_usar_sugestao_button',
                      params: {'calorias': _sugestaoCalorias!.round().toString()},
                    ),
                  ),
                ),
              ),
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
              enabled: !_salvando,
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
              enabled: !_salvando,
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
              enabled: !_salvando,
            ),
            const SizedBox(height: 8),
            Text(
              i18n.tr('nutricao.meta_bem_estar_aviso'),
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
                  : Text(i18n.tr('nutricao.meta_save_button')),
            ),
          ],
        ),
      ),
    );
  }

  /// dd/mm/aaaa — mesmo padrão simples de `perfil_usuario_page.dart`.
  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }
}
