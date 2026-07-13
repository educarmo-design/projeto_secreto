import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../data/services/esteira_trial_gateway_service.dart';

/// Snapshot of where the user stands on the "Esteira dos 14 Dias Free" (A
/// Cenoura) trial ladder — devolvido inteiramente pelo servidor (Edge
/// Function `calculate-recovery-mode`). [EsteiraTrialController] só guarda
/// aqui a última resposta recebida; nenhum campo abaixo é calculado no
/// cliente.
@immutable
class EsteiraTrialState {
  /// 1-14. Enquanto [modoRecuperacaoAtivo] é `true`, o servidor mantém este
  /// valor travado no dia em que o congelamento começou.
  final int diaAtual;
  final bool modoRecuperacaoAtivo;
  final bool metaMovimentoCumprida;

  /// Quais das 6 missões diárias de upload de exame (Dias 1-6) já foram
  /// concluídas.
  final Set<int> missoesExamesConcluidas;

  /// True até a primeira resposta do servidor chegar — [diaAtual] fica em 1
  /// (valor neutro) durante essa janela.
  final bool carregando;

  /// Não-nulo quando a última chamada a `calculate-recovery-mode` falhou —
  /// os demais campos, nesse caso, são só o último valor conhecido (ou o
  /// default), não uma leitura fresca do servidor.
  final String? erro;

  const EsteiraTrialState({
    this.diaAtual = 1,
    this.modoRecuperacaoAtivo = false,
    this.metaMovimentoCumprida = false,
    this.missoesExamesConcluidas = const {},
    this.carregando = true,
    this.erro,
  });

  factory EsteiraTrialState.deServidor(EsteiraTrialGatewayState servidor) {
    return EsteiraTrialState(
      diaAtual: servidor.diaAtual,
      modoRecuperacaoAtivo: servidor.modoRecuperacaoAtivo,
      metaMovimentoCumprida: servidor.metaMovimentoCumprida,
      missoesExamesConcluidas: servidor.missoesExamesConcluidas,
      carregando: false,
    );
  }

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
/// Etapa 0.5 (F21 — Correção de Arquitetura): este controller costumava
/// calcular o dia do trial e a janela de "Modo Recuperação Humano"
/// localmente, com uma âncora de data persistida em
/// `flutter_secure_storage` no próprio aparelho — o que violava a Regra de
/// arquitetura inegociável do PRD Mestre (§0.5): "toda regra de negócio
/// sensível é calculada server-side". Um usuário com acesso de depuração ao
/// próprio aparelho podia adiantar o Dia 7 ou nunca sair do Modo
/// Recuperação simplesmente editando essa data local.
///
/// O controller não calcula mais nada: cada método público aqui só envia a
/// intenção (`consultar`/`ativar_recuperacao`/`desativar_recuperacao`/
/// `registrar_meta_movimento`/`registrar_missao_exame`) para a Edge
/// Function `calculate-recovery-mode` via [EsteiraTrialGatewayService], e
/// adota o [EsteiraTrialState] que ela devolve.
///
/// Etapa 1: a Edge Function passou a calcular o estado de verdade (antes
/// era um stub HTTP 501) — ver
/// `supabase/functions/calculate-recovery-mode/index.ts`. O construtor não
/// recebe mais `dataCadastro`: a data de início do trial agora é semeada
/// pelo próprio servidor a partir de `auth.users.created_at` na primeira
/// consulta de cada usuário, nunca de um valor que o cliente poderia
/// forjar.
class EsteiraTrialController extends ValueNotifier<EsteiraTrialState> {
  EsteiraTrialController({
    EsteiraTrialGatewayService? gatewayService,
    Map<String, String> Function()? authHeadersProvider,
  })  : _gateway = gatewayService ?? EsteiraTrialGatewayService(),
        _authHeadersProvider = authHeadersProvider ?? _authHeadersFromSupabase,
        super(const EsteiraTrialState()) {
    _executar(EsteiraTrialAcao.consultar);
  }

  final EsteiraTrialGatewayService _gateway;

  /// Injetável em teste para não depender de `Supabase.instance` estar
  /// inicializado (ver [_authHeadersFromSupabase]) — mesmo espírito de
  /// [gatewayService] acima: o controller nunca fala com a rede/Supabase
  /// diretamente, só através de dependências que podem ser trocadas por
  /// fakes.
  final Map<String, String> Function() _authHeadersProvider;

  static Map<String, String> _authHeadersFromSupabase() {
    final session = Supabase.instance.client.auth.currentSession;
    return {
      'apikey': AppConfig.supabaseAnonKey,
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  /// Regra de Congelamento (parte 1): pede ao servidor para travar o
  /// contador no dia atual — chamado quando o "Modo Recuperação Humano" é
  /// ativado (lesão/doença), normalmente a partir de um toggle em outra
  /// tela.
  Future<void> ativarModoRecuperacao() =>
      _executar(EsteiraTrialAcao.ativarRecuperacao);

  /// Regra de Congelamento (parte 2): pede ao servidor para retomar o
  /// contador de onde parou, estendendo o prazo do trial pelo número de
  /// dias que ficou congelado.
  Future<void> desativarModoRecuperacao() =>
      _executar(EsteiraTrialAcao.desativarRecuperacao);

  /// Marca a meta de movimento da Semana 1 como cumprida — junto com o
  /// upload de exame, libera o Gatilho do Dia 7.
  Future<void> registrarMetaMovimentoCumprida() =>
      _executar(EsteiraTrialAcao.registrarMetaMovimento);

  /// Marca a missão de upload de exame do [dia] (1-6) como concluída —
  /// chamado pela tela de missões após cada envio bem-sucedido.
  Future<void> registrarMissaoExameConcluida(int dia) =>
      _executar(EsteiraTrialAcao.registrarMissaoExame, dia: dia);

  Future<void> _executar(EsteiraTrialAcao acao, {int? dia}) async {
    final resultado = await _gateway.executar(
      acao: acao,
      authHeaders: _authHeadersProvider(),
      dia: dia,
    );

    final servidorState = resultado.state;
    if (!resultado.success || servidorState == null) {
      value = EsteiraTrialState(
        diaAtual: value.diaAtual,
        modoRecuperacaoAtivo: value.modoRecuperacaoAtivo,
        metaMovimentoCumprida: value.metaMovimentoCumprida,
        missoesExamesConcluidas: value.missoesExamesConcluidas,
        carregando: false,
        erro: resultado.errorMessage ?? 'Erro desconhecido.',
      );
      return;
    }

    value = EsteiraTrialState.deServidor(servidorState);
  }
}
