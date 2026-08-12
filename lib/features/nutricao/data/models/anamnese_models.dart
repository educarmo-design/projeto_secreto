// N09 (RELATÓRIO 20260811_0007) — Anamnese Nutricional Versionada,
// self-service. Modelos leves, espelho tipado das colunas fixas, mesmo
// espírito de `TreinoModel`/`HealthPayloadModel`: sem mapa genérico solto
// pela UI.

/// Um item de catálogo simples id/nome — reusado para `problemas_saude` e
/// `alergias` (que, apesar de ter `nome_exibicao` em vez de `nome` na
/// coluna, representa o mesmo conceito pra esta tela).
class CatalogoItem {
  final String id;
  final String nome;

  const CatalogoItem({required this.id, required this.nome});

  factory CatalogoItem.fromJson(Map<String, dynamic> json, {String campoNome = 'nome'}) {
    return CatalogoItem(id: json['id'] as String, nome: json[campoNome] as String);
  }
}

/// Uma modalidade de `tipos_atividades_fisicas` — `id` é `smallint` no
/// banco (int no Dart, sem perda: smallint cabe inteiro em int nativo).
class TipoAtividadeItem {
  final int id;
  final String nomeExibicao;

  const TipoAtividadeItem({required this.id, required this.nomeExibicao});

  factory TipoAtividadeItem.fromJson(Map<String, dynamic> json) {
    return TipoAtividadeItem(
      id: json['id'] as int,
      nomeExibicao: json['nome_exibicao'] as String,
    );
  }
}

/// Uma atividade escolhida na Rotina de Atividades da anamnese — o "N:N com
/// atributo" (`anamneses_atividades.minutos_diarios`) em memória, antes de
/// gravar. `nomeExibicao` vem junto só para a UI não precisar re-consultar
/// o catálogo pra mostrar o chip/linha.
class AtividadeSelecionada {
  final int atividadeId;
  final String nomeExibicao;
  final int minutosDiarios;

  const AtividadeSelecionada({
    required this.atividadeId,
    required this.nomeExibicao,
    required this.minutosDiarios,
  });

  /// Igualdade por valor — necessária para o `Set`/comparação de
  /// "já adicionada" em [AnamneseSelfServicePage] (evitar duplicar a mesma
  /// modalidade) e para `verify()` de testes comparar listas por conteúdo,
  /// não por identidade de instância.
  @override
  bool operator ==(Object other) =>
      other is AtividadeSelecionada &&
      other.atividadeId == atividadeId &&
      other.nomeExibicao == nomeExibicao &&
      other.minutosDiarios == minutosDiarios;

  @override
  int get hashCode => Object.hash(atividadeId, nomeExibicao, minutosDiarios);
}

/// A anamnese `status_vigencia = 'ativo'` do usuário logado, já com as 3
/// relações N:N resolvidas — usada para PRÉ-PREENCHER a tela quando o
/// usuário volta para atualizar (o app nunca faz UPDATE nela; salvar de
/// novo cria uma linha nova e o trigger do banco versiona a antiga para
/// "historico" automaticamente, ver [AnamneseRepository.salvarAnamnese]).
class AnamneseAtiva {
  final String objetivoCodigo;
  final List<String> problemasSaudeIds;
  final List<String> alergiaIds;
  final List<AtividadeSelecionada> atividades;

  const AnamneseAtiva({
    required this.objetivoCodigo,
    required this.problemasSaudeIds,
    required this.alergiaIds,
    required this.atividades,
  });
}
