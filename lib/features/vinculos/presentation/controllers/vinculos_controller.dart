import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../data/models/convite_vinculo_model.dart';
import '../../data/services/manage_professional_link_gateway_service.dart';
import '../../data/services/vinculos_service.dart';

@immutable
class VinculosPendentesState {
  final List<ConviteVinculoModel> convites;
  final bool carregando;

  /// Não-nulo quando a última chamada a `aceitar`/`recusar` falhou. Os
  /// convites listados, nesse caso, continuam sendo os do último carregamento
  /// bem-sucedido — nada é removido da lista até o servidor confirmar.
  final String? erro;

  /// Id do vínculo sendo aceito/recusado agora — só ele mostra spinner no
  /// card correspondente, os demais continuam clicáveis.
  final String? processandoVinculoId;

  const VinculosPendentesState({
    this.convites = const [],
    this.carregando = true,
    this.erro,
    this.processandoVinculoId,
  });

  VinculosPendentesState copyWith({
    List<ConviteVinculoModel>? convites,
    bool? carregando,
    String? erro,
    bool limparErro = false,
    String? processandoVinculoId,
    bool limparProcessando = false,
  }) {
    return VinculosPendentesState(
      convites: convites ?? this.convites,
      carregando: carregando ?? this.carregando,
      erro: limparErro ? null : (erro ?? this.erro),
      processandoVinculoId:
          limparProcessando ? null : (processandoVinculoId ?? this.processandoVinculoId),
    );
  }
}

/// Orquestra a UI de Consentimento do Paciente (Adendo v4, F.3): lista os
/// convites `pendente` e envia `aceitar`/`recusar` para
/// `manage-professional-link`, nunca escrevendo em
/// `vinculos_profissional_paciente` diretamente — a tabela não concede
/// INSERT/UPDATE ao `authenticated` (20260713100000/140000), de propósito.
///
/// Mesma forma de [EsteiraTrialController]: a leitura (`carregarConvitesFn`)
/// e a escrita (`gateway`) são injetáveis, para que os testes troquem por
/// fakes sem montar um `SupabaseClient`/servidor de verdade.
class VinculosController extends ValueNotifier<VinculosPendentesState> {
  VinculosController({
    Future<List<ConviteVinculoModel>> Function()? carregarConvitesFn,
    ManageProfessionalLinkGatewayService? gateway,
    Map<String, String> Function()? authHeadersProvider,
  })  : _carregarConvitesFn = carregarConvitesFn ?? VinculosService().carregarConvitesPendentes,
        _gateway = gateway ?? ManageProfessionalLinkGatewayService(),
        _authHeadersProvider = authHeadersProvider ?? _authHeadersFromSupabase,
        super(const VinculosPendentesState()) {
    carregarConvites();
  }

  final Future<List<ConviteVinculoModel>> Function() _carregarConvitesFn;
  final ManageProfessionalLinkGatewayService _gateway;
  final Map<String, String> Function() _authHeadersProvider;

  static Map<String, String> _authHeadersFromSupabase() {
    final session = Supabase.instance.client.auth.currentSession;
    return {
      'apikey': AppConfig.supabaseAnonKey,
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  /// Sem try/catch: `VinculosService.carregarConvitesPendentes` já nunca
  /// lança (mesmo padrão de `SeniorDashboardService`) — uma falha de
  /// RLS/rede vira lista vazia lá dentro, e aqui isso só significa "sem
  /// convites", não um erro para mostrar.
  Future<void> carregarConvites() async {
    value = value.copyWith(carregando: true, limparErro: true);
    final convites = await _carregarConvitesFn();
    value = VinculosPendentesState(convites: convites, carregando: false);
  }

  Future<bool> aceitar(String vinculoId) =>
      _executarAcao(vinculoId, AcaoVinculoPaciente.aceitar);

  Future<bool> recusar(String vinculoId) =>
      _executarAcao(vinculoId, AcaoVinculoPaciente.recusar);

  Future<bool> _executarAcao(String vinculoId, AcaoVinculoPaciente acao) async {
    value = value.copyWith(processandoVinculoId: vinculoId, limparErro: true);

    final resultado = await _gateway.executar(
      acao: acao,
      vinculoId: vinculoId,
      authHeaders: _authHeadersProvider(),
    );

    if (!resultado.success) {
      value = value.copyWith(
        limparProcessando: true,
        erro: resultado.errorMessage ?? 'Erro desconhecido.',
      );
      return false;
    }

    // Sucesso em aceitar OU recusar: os dois tiram o vínculo do status
    // 'pendente' (vira 'ativo' ou 'encerrado'), então em ambos os casos ele
    // sai desta lista — sem precisar recarregar tudo do servidor.
    value = VinculosPendentesState(
      convites: value.convites.where((c) => c.vinculoId != vinculoId).toList(),
      carregando: false,
    );
    return true;
  }
}
