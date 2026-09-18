import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/anamnese_models.dart';
import '../../data/repositories/anamnese_repository.dart';
import '../../data/repositories/meta_bem_estar_repository.dart';
import 'resultado_motor_metabolico_page.dart';

/// Seção 11 (docs/motor_metabolico.txt, RELATÓRIO 20260918_0001,
/// RESTRIÇÃO explícita da tarefa: "Garantir a tela final de 'Confirme seus
/// dados' antes de enviar para o motor") — só-leitura, revisão final de
/// tudo que foi preenchido em [AnamneseSelfServicePage]. A GRAVAÇÃO de
/// verdade (`AnamneseRepository.salvarAnamnese`) só acontece quando o
/// usuário toca "Confirmar e Enviar" aqui — nunca antes, nunca na tela
/// anterior.
///
/// `pushReplacement` pro Resultado (não `push`) — mantém a mesma
/// profundidade de pilha que a tela anterior já tinha antes desta tarefa
/// (Anamnese → Resultado), então `ResultadoMotorMetabolicoPage._concluir`
/// (que faz `pop()` duas vezes) continua funcionando sem precisar mudar.
class ConfirmarAnamnesePage extends StatefulWidget {
  const ConfirmarAnamnesePage({
    super.key,
    required this.rascunho,
    AnamneseRepository? repository,
    MetaBemEstarRepository? metaRepository,
  })  : _repository = repository,
        _metaRepository = metaRepository;

  final AnamneseRascunho rascunho;
  final AnamneseRepository? _repository;
  final MetaBemEstarRepository? _metaRepository;

  @override
  State<ConfirmarAnamnesePage> createState() => _ConfirmarAnamnesePageState();
}

class _ConfirmarAnamnesePageState extends State<ConfirmarAnamnesePage> {
  late final AnamneseRepository _repository = widget._repository ?? AnamneseRepository();
  bool _enviando = false;

  Future<void> _confirmarEEnviar() async {
    setState(() => _enviando = true);
    final rascunho = widget.rascunho;
    try {
      await _repository.salvarAnamnese(
        objetivoCodigo: rascunho.objetivoCodigo,
        alturaCm: rascunho.alturaCm,
        sexoBiologico: rascunho.sexoBiologico,
        pesoKg: rascunho.pesoKg,
        problemasSaudeIds: rascunho.problemasSaudeSelecionados.map((item) => item.id).toList(),
        alergiaIds: rascunho.alergiasSelecionadas.map((item) => item.id).toList(),
        atividades: rascunho.atividades,
        complementares: rascunho.complementares,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResultadoMotorMetabolicoPage(repository: widget._metaRepository),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(i18n.tr('nutricao.save_error')), backgroundColor: AppColors.error),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rascunho = widget.rascunho;
    final c = rascunho.complementares;

    return Scaffold(
      appBar: AppBar(title: Text(i18n.tr('nutricao.confirmar_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              i18n.tr('nutricao.confirmar_subtitle'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
            ),
            const SizedBox(height: 24),
            _secao(context, i18n.tr('nutricao.confirmar_secao_dados_fisicos'), [
              if (rascunho.idade != null) _linha(i18n.tr('nutricao.confirmar_idade_label'), '${rascunho.idade}'),
              _linha(
                i18n.tr('nutricao.confirmar_sexo_label'),
                rascunho.sexoBiologico == 'M'
                    ? i18n.tr('perfil_fisico.sexo_biologico_masculino')
                    : i18n.tr('perfil_fisico.sexo_biologico_feminino'),
              ),
              _linha(i18n.tr('nutricao.confirmar_peso_label'), '${rascunho.pesoKg} kg'),
              _linha(i18n.tr('nutricao.confirmar_altura_label'), '${rascunho.alturaCm} cm'),
              if (c.percentualGordura != null) _linha(i18n.tr('nutricao.percentual_gordura_label'), '${c.percentualGordura}%'),
            ]),
            _secao(context, i18n.tr('nutricao.confirmar_secao_objetivo'), [
              _linha(i18n.tr('nutricao.objetivo_label'), i18n.tr('nutricao.objetivo_${rascunho.objetivoCodigo}')),
              if (c.objetivosSecundarios.isNotEmpty)
                _linha(
                  i18n.tr('nutricao.objetivos_secundarios_label'),
                  c.objetivosSecundarios.map((codigo) => i18n.tr('nutricao.objetivo_$codigo')).join(', '),
                ),
            ]),
            _secao(context, i18n.tr('nutricao.confirmar_secao_rotina'), [
              if (c.rotinaDiaria != null) _linha(i18n.tr('nutricao.rotina_diaria_pergunta'), i18n.tr('nutricao.rotina_diaria_${c.rotinaDiaria}')),
              _linha(
                i18n.tr('nutricao.atividades_label'),
                rascunho.atividades.isEmpty ? i18n.tr('nutricao.atividades_empty') : '${rascunho.atividades.length}',
              ),
            ]),
            _secao(context, i18n.tr('nutricao.confirmar_secao_condicoes'), [
              _linha(
                i18n.tr('nutricao.condicoes_pergunta'),
                c.possuiCondicaoSaude == true ? i18n.tr('nutricao.condicoes_tenho') : i18n.tr('nutricao.condicoes_nao_tenho'),
              ),
              if (rascunho.problemasSaudeSelecionados.isNotEmpty)
                _linha(
                  i18n.tr('nutricao.problemas_saude_label'),
                  rascunho.problemasSaudeSelecionados.map((item) => item.nome).join(', '),
                ),
              if (rascunho.alergiasSelecionadas.isNotEmpty)
                _linha(i18n.tr('nutricao.alergias_label'), rascunho.alergiasSelecionadas.map((item) => item.nome).join(', ')),
            ]),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _enviando ? null : _confirmarEEnviar,
              child: _enviando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(i18n.tr('nutricao.confirmar_botao')),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _enviando ? null : () => Navigator.of(context).pop(),
              child: Text(i18n.tr('nutricao.confirmar_voltar')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secao(BuildContext context, String titulo, List<Widget> linhas) {
    if (linhas.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          ...linhas,
        ],
      ),
    );
  }

  Widget _linha(String label, String valor) {
    // `Text.rich` (não `RichText` cru) — `find.textContaining` do
    // flutter_test só reconhece `Text`/`Text.rich`/`EditableText`, nunca um
    // `RichText` solto (achado testando esta tela).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: valor),
          ],
        ),
      ),
    );
  }
}
