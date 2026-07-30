/**
 * Tipos do schema Postgres/Supabase — escritos à mão (não há CLI do
 * Supabase disponível neste ambiente para gerar `supabase gen types
 * typescript`) espelhando exatamente as migrations em `supabase/migrations/`
 * do repositório. Cobre só as tabelas que o Painel Web efetivamente lê/
 * escreve; não é o schema inteiro do projeto (o app mobile usa várias
 * outras tabelas — `resultados_exames`, `diario_alimentar_diario` etc. —
 * fora do escopo deste painel).
 *
 * Ao rodar `supabase gen types typescript` de verdade no futuro, este
 * arquivo deve ser substituído pelo output gerado — mantenha a mesma forma
 * (`Database['public']['Tables'][...]`) para não quebrar os imports em
 * `core/supabase.ts` e nas features.
 */
export interface Database {
  public: {
    Tables: {
      perfis_usuarios: {
        Row: {
          id: string;
          nome: string | null;
          email: string | null;
          telefone: string | null;
          data_nascimento: string | null;
          sexo_biologico: string | null;
          eh_profissional: boolean;
          tipo_profissional: TipoProfissionalSaude | null;
          nickname: string | null;
          pais: string | null;
          cep: string | null;
          logradouro: string | null;
          bairro: string | null;
          cidade: string | null;
          estado: string | null;
          geo_ranking_id: string | null;
          /** Sala de Espera (20260714100000) — todo cadastro nasce `pendente`; só um admin muda isso. */
          status_aprovacao: StatusAprovacaoUsuario;
          is_admin: boolean;
          criado_em: string;
        };
        Insert: Partial<Database['public']['Tables']['perfis_usuarios']['Row']> & {
          id: string;
        };
        Update: Partial<Database['public']['Tables']['perfis_usuarios']['Row']>;
        Relationships: [];
      };

      metricas_saude_diarias: {
        Row: {
          id: number;
          usuario_id_anonimo: string;
          data_referencia: string;
          passos: number | null;
          distancia_metros: number | null;
          fc_repouso: number | null;
          hrv_medio: number | null;
          calorias_ativas: number | null;
          minutos_sono: number | null;
          peso_kg: number | null;
          percentual_gordura: number | null;
          pressao_sistolica: number | null;
          pressao_diastolica: number | null;
          glicose_jejum: number | null;
          saturacao_oxigenio: number | null;
          temperatura_corporal: number | null;
          origem: string | null;
          criado_em: string;
          atualizado_em: string;
        };
        Insert: Partial<Database['public']['Tables']['metricas_saude_diarias']['Row']> & {
          usuario_id_anonimo: string;
          data_referencia: string;
        };
        Update: Partial<Database['public']['Tables']['metricas_saude_diarias']['Row']>;
        Relationships: [];
      };

      eventos_anomalias_saude: {
        Row: {
          id: number;
          usuario_id_anonimo: string;
          tipo_anomalia: string;
          parametro: string;
          valor_detectado: number;
          valor_limite_min: number | null;
          valor_limite_max: number | null;
          em_treino: boolean;
          severidade: 'atencao' | 'critico' | string;
          origem: string | null;
          detectado_em: string;
        };
        Insert: Partial<Database['public']['Tables']['eventos_anomalias_saude']['Row']> & {
          usuario_id_anonimo: string;
          tipo_anomalia: string;
          parametro: string;
          valor_detectado: number;
          severidade: string;
        };
        Update: Partial<Database['public']['Tables']['eventos_anomalias_saude']['Row']>;
        Relationships: [];
      };

      planejamento_clinico: {
        Row: {
          id: string;
          profissional_id: string;
          paciente_id_anonimo: string;
          tipo_plano: string | null;
          estrutura_plano_jsonb: PlanoTreinoEstrutura | null;
          sincronizado_garmin: boolean;
          data_limite: string | null;
          criado_em: string;
        };
        Insert: Partial<Database['public']['Tables']['planejamento_clinico']['Row']> & {
          profissional_id: string;
          paciente_id_anonimo: string;
        };
        Update: Partial<Database['public']['Tables']['planejamento_clinico']['Row']>;
        Relationships: [];
      };

      progresso_gamificacao: {
        Row: {
          usuario_id_anonimo: string;
          ofensiva_atual: number;
          pontuacao_ranking: number;
          ultima_atividade_data: string | null;
          status_usuario: string;
          detalhes_recuperacao_jsonb: Record<string, unknown> | null;
        };
        Insert: Partial<Database['public']['Tables']['progresso_gamificacao']['Row']> & {
          usuario_id_anonimo: string;
        };
        Update: Partial<Database['public']['Tables']['progresso_gamificacao']['Row']>;
        Relationships: [];
      };

      /**
       * Motor de vínculos (Adendo v4, F.2) — a ÚNICA fonte de autorização
       * "profissional acompanha paciente" desde a unificação do Zero Trust
       * (20260713140000_saneamento_grants_e_unificacao_rls.sql).
       * `PatientList`/`PatientDetails` leem `status` diretamente daqui (ou,
       * no caso de `PatientList`, indiretamente via a view
       * `perfis_pacientes_vinculados`, que já filtra por `status = 'ativo'`
       * dentro dela mesma). Sem policy de INSERT/UPDATE/DELETE para
       * `authenticated` — ver a migration.
       */
      vinculos_profissional_paciente: {
        Row: {
          id: string;
          profissional_id: string;
          paciente_id: string;
          status: StatusVinculo;
          tipo_pagador: string;
          tipo_produto: string;
          data_inicio: string;
          data_saida: string | null;
          fim_carencia: string | null;
          criado_em: string;
          atualizado_em: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
    };
    Views: {
      /**
       * Ver `supabase/migrations/*_painel_web_profissional_rls.sql`: só
       * expõe os 4 campos não-sensíveis de `perfis_usuarios` para os
       * pacientes vinculados ao profissional autenticado —
       * `nome`/`telefone`/`email`/endereço nunca aparecem aqui, mesmo que
       * a linha esteja visível.
       */
      perfis_pacientes_vinculados: {
        Row: {
          id: string;
          nickname: string | null;
          data_nascimento: string | null;
          geo_ranking_id: string | null;
        };
        Relationships: [];
      };
    };
    Functions: {
      /**
       * D2 (server-side PII crypto) — RPC SECURITY DEFINER escopada a
       * `auth.uid()` que devolve a PRÓPRIA linha de `perfis_usuarios` com
       * `nome`/`telefone`/`email` já DECIFRADOS server-side. Substitui o
       * `select nome from perfis_usuarios` direto (que agora só devolveria
       * ciphertext). Ver `*_d2_pii_criptografia_repouso.sql`.
       */
      meu_perfil_seguro: {
        Args: Record<string, never>;
        Returns: {
          id: string;
          nome: string | null;
          telefone: string | null;
          email: string | null;
          nickname: string | null;
          eh_profissional: boolean;
          tipo_profissional: TipoProfissionalSaude | null;
          status_aprovacao: StatusAprovacaoUsuario;
          is_admin: boolean;
        }[];
      };
    };
    Enums: {
      tipo_profissional_saude: TipoProfissionalSaude;
      status_aprovacao_usuario: StatusAprovacaoUsuario;
      status_vinculo: StatusVinculo;
    };
  };
}

/** Espelha o enum Postgres `status_aprovacao_usuario` (20260714100000_add_approval_workflow.sql). */
export type StatusAprovacaoUsuario = 'pendente' | 'aprovado' | 'rejeitado';

/** Espelha o enum Postgres `status_vinculo` (20260713100000_estruturas_b2b_v4.sql). */
export type StatusVinculo = 'ativo' | 'em_carencia' | 'encerrado';

/**
 * Espelha o enum Postgres `tipo_profissional_saude`. `Auditoria_Seguradora`
 * é o valor adicionado pela migration deste ONDA 3 (ver
 * `supabase/migrations/*_painel_web_profissional_rls.sql`) — é o que
 * `PatientList.tsx` usa para decidir se o acesso é de um médico/nutri
 * (nominal-adjacent, dentro do vínculo clínico) ou de uma auditoria de
 * seguradora (estritamente anonimizado, ver Regra de Blindagem LGPD).
 */
export type TipoProfissionalSaude =
  | 'Medico'
  | 'Nutricionista'
  | 'Fisioterapeuta'
  | 'Personal_Trainer'
  | 'Auditoria_Seguradora';

/** Estrutura livre de `planejamento_clinico.estrutura_plano_jsonb` para planos do tipo `treino_garmin` — ver GarminPrescriptionForm. */
export interface PlanoTreinoEstrutura {
  tipoTreino: 'corrida' | 'ciclismo';
  duracaoMinutos: number;
  zonaFcAlvoMin: number;
  zonaFcAlvoMax: number;
  dataAgenda: string;
  observacoes?: string;
}
