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
          /** CRM/CRN/CREFITO/CREF — texto livre, cada conselho tem formato próprio (20260722120000). NÃO cifrado (D2 só cobre nome/telefone/email). */
          registro_profissional: string | null;
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

      /** D3 RBAC dinâmico (20260811200000) — catálogo de papéis. */
      papeis: {
        Row: {
          id: string;
          nome_codigo: string;
          nome_exibicao: string;
        };
        Insert: Partial<Database['public']['Tables']['papeis']['Row']> & {
          nome_codigo: string;
          nome_exibicao: string;
        };
        Update: Partial<Database['public']['Tables']['papeis']['Row']>;
        Relationships: [];
      };

      /** D3 RBAC dinâmico (20260811200000) — catálogo de permissões granulares. */
      permissoes: {
        Row: {
          id: string;
          modulo: string;
          acao_codigo: string;
          descricao: string | null;
        };
        Insert: Partial<Database['public']['Tables']['permissoes']['Row']> & {
          modulo: string;
          acao_codigo: string;
        };
        Update: Partial<Database['public']['Tables']['permissoes']['Row']>;
        Relationships: [];
      };

      /**
       * D3 RBAC dinâmico (20260811200000) — a MATRIZ em si (papel x
       * permissão). SÓ SELECT para `authenticated`: toda escrita passa pela
       * RPC `admin_atualizar_permissao_papel` (ver `core/supabase.ts`).
       */
      papeis_permissoes: {
        Row: {
          papel_id: string;
          permissao_id: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };

      /** D3 RBAC dinâmico (20260811200000) — quais papéis cada usuário acumula. */
      usuario_papeis: {
        Row: {
          usuario_id: string;
          papel_id: string;
        };
        Insert: Partial<Database['public']['Tables']['usuario_papeis']['Row']> & {
          usuario_id: string;
          papel_id: string;
        };
        Update: Partial<Database['public']['Tables']['usuario_papeis']['Row']>;
        Relationships: [];
      };

      /**
       * Dicionário de modalidades de treino (`20260811160000`, RELATÓRIO
       * 20260811_0002) — escrita liberada a admin só em
       * `20260811220000_admin_escrita_tipos_atividades_fisicas.sql`
       * (RELATÓRIO 20260811_0005), pra `AdminAtividadesFisicas.tsx` funcionar.
       */
      tipos_atividades_fisicas: {
        Row: {
          id: string;
          nome_codigo: string;
          nome_exibicao: string;
        };
        Insert: Partial<Database['public']['Tables']['tipos_atividades_fisicas']['Row']> & {
          nome_codigo: string;
          nome_exibicao: string;
        };
        Update: Partial<Database['public']['Tables']['tipos_atividades_fisicas']['Row']>;
        Relationships: [];
      };

      /** N06 (20260811210000) — catálogo de alergias. */
      alergias: {
        Row: {
          id: string;
          nome_codigo: string;
          nome_exibicao: string;
          descricao: string | null;
        };
        Insert: Partial<Database['public']['Tables']['alergias']['Row']> & {
          nome_codigo: string;
          nome_exibicao: string;
        };
        Update: Partial<Database['public']['Tables']['alergias']['Row']>;
        Relationships: [];
      };

      /** N06 (20260811210000) — alergias declaradas por usuário (N:N). */
      usuario_alergias: {
        Row: {
          usuario_id: string;
          alergia_id: string;
          observacao: string | null;
          criado_em: string;
        };
        Insert: Partial<Database['public']['Tables']['usuario_alergias']['Row']> & {
          usuario_id: string;
          alergia_id: string;
        };
        Update: Partial<Database['public']['Tables']['usuario_alergias']['Row']>;
        Relationships: [];
      };

      /**
       * Catálogo TACO/USDA (`20260716120000_alimentos_referencia_taco.sql`).
       * Escrita de admin liberada em `20260811230000_n06_escrita_admin_
       * alimentos_e_vinculos.sql` (RELATÓRIO 20260811_0006), revertendo por
       * instrução explícita do fundador a trava original ("curadoria é
       * migration/service role"). RESSALVA que continua verdadeira: um
       * INSERT/UPDATE aqui NÃO recalcula o embedding semântico em
       * `cache_sinonimos_alimentos` (busca por sinônimo via Edge Function
       * `search-food`) — o alimento fica utilizável no cálculo de calorias
       * na hora, mas só entra na busca semântica após o job de re-embed.
       */
      alimentos_referencia: {
        Row: {
          id: string;
          nome_taco: string;
          aliases: string[];
          fonte: string;
          calorias_kcal_100g: number;
          proteinas_g_100g: number;
          carboidratos_g_100g: number;
          gorduras_g_100g: number;
          criado_em: string;
        };
        Insert: Partial<Database['public']['Tables']['alimentos_referencia']['Row']> & {
          nome_taco: string;
          calorias_kcal_100g: number;
          proteinas_g_100g: number;
          carboidratos_g_100g: number;
          gorduras_g_100g: number;
        };
        Update: Partial<Database['public']['Tables']['alimentos_referencia']['Row']>;
        Relationships: [];
      };

      /**
       * "Porções"/medidas caseiras por alimento (1:N — a mesma "colher de
       * sopa" pesa coisas diferentes por alimento, ver migration original).
       * Mesma liberação de escrita de admin de `alimentos_referencia`,
       * `20260811230000_n06_escrita_admin_alimentos_e_vinculos.sql`.
       */
      alimentos_medidas_caseiras: {
        Row: {
          id: number;
          alimento_id: string;
          medida: string;
          gramas: number;
        };
        Insert: Partial<Database['public']['Tables']['alimentos_medidas_caseiras']['Row']> & {
          alimento_id: string;
          medida: string;
          gramas: number;
        };
        Update: Partial<Database['public']['Tables']['alimentos_medidas_caseiras']['Row']>;
        Relationships: [];
      };

      /**
       * N06 (20260811210000) — configurações globais, chave/valor. Escopo de
       * negócio ainda não definido pelo fundador (spike 20260811_0004);
       * infraestrutura genérica, admin-only.
       */
      configuracoes_sistema: {
        Row: {
          chave: string;
          valor: string | null;
          descricao: string | null;
          atualizado_em: string;
        };
        Insert: Partial<Database['public']['Tables']['configuracoes_sistema']['Row']> & {
          chave: string;
        };
        Update: Partial<Database['public']['Tables']['configuracoes_sistema']['Row']>;
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

      /**
       * N06 (20260811210000) — mesmo princípio de `meu_perfil_seguro`, mas
       * MULTI-linha e escopada a admin (`eh_admin()`), não a `auth.uid()`.
       * Substitui o `select nome, email from perfis_usuarios` quebrado de
       * `AdminDashboard.tsx` (devolvia ciphertext desde o D2). Lança erro
       * Postgrest se o chamador não for admin.
       */
      admin_perfis_seguro: {
        Args: { p_status_aprovacao?: string | null };
        Returns: {
          id: string;
          nome: string | null;
          telefone: string | null;
          email: string | null;
          nickname: string | null;
          eh_profissional: boolean;
          tipo_profissional: TipoProfissionalSaude | null;
          registro_profissional: string | null;
          status_aprovacao: StatusAprovacaoUsuario;
          is_admin: boolean;
          data_nascimento: string | null;
          idade: number | null;
          criado_em: string;
        }[];
      };

      /**
       * D3 RBAC dinâmico (20260811200000) — `true` se `p_usuario_id` tem,
       * por qualquer papel que acumule, a permissão `p_permissao_codigo`
       * (formato `"modulo.acao"`, ex.: `"alimentos.criar"`).
       */
      tem_permissao: {
        Args: { p_usuario_id: string; p_permissao_codigo: string };
        Returns: boolean;
      };

      /**
       * D3 RBAC dinâmico (20260811200000) — ÚNICA porta de escrita da
       * matriz `papeis_permissoes`; usada por `AdminMatrizPermissoes.tsx`.
       * Lança erro Postgrest se o chamador não for admin.
       */
      admin_atualizar_permissao_papel: {
        Args: { p_papel_id: string; p_permissao_id: string; p_habilitado: boolean };
        Returns: void;
      };

      /**
       * N06 (20260811230000, RELATÓRIO 20260811_0006) — lista todos os
       * vínculos profissional×paciente com nome decifrado (D2) dos dois
       * lados, escopado a admin. Base de `AdminVinculos.tsx`.
       */
      admin_listar_vinculos: {
        Args: Record<string, never>;
        Returns: {
          id: string;
          profissional_id: string;
          profissional_nome: string | null;
          paciente_id: string;
          paciente_nome: string | null;
          status: StatusVinculo;
          tipo_pagador: string;
          tipo_produto: string;
          data_inicio: string;
          data_saida: string | null;
          fim_carencia: string | null;
          criado_em: string;
        }[];
      };

      /**
       * N06 (20260811230000) — Admin encerra manualmente um vínculo (mesma
       * regra de `fim_carencia` de 30 dias da Edge Function
       * `manage-professional-link`). Idempotente.
       */
      admin_encerrar_vinculo: {
        Args: { p_vinculo_id: string };
        Returns: void;
      };

      /**
       * N06 (20260811230000) — Admin aprova manualmente um vínculo
       * `pendente` (pendente -> ativo). Sem efeito se não estiver pendente.
       */
      admin_aprovar_vinculo: {
        Args: { p_vinculo_id: string };
        Returns: void;
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

/**
 * Espelha o enum Postgres `status_vinculo`. Nasceu com só 3 valores
 * (`20260713100000_estruturas_b2b_v4.sql`); `'pendente'` foi adicionado
 * depois (`20260713170000_vinculo_pendente_e_backfill_legado.sql`) para
 * modelar o consentimento do paciente — este arquivo TypeScript escrito à
 * mão tinha ficado desatualizado (achado do spike 20260811_0004), corrigido
 * nesta tarefa (RELATÓRIO 20260811_0005).
 */
export type StatusVinculo = 'pendente' | 'ativo' | 'em_carencia' | 'encerrado';

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

/**
 * Espelha `papeis.nome_codigo` (D3 RBAC dinâmico, 20260811200000) —
 * deliberadamente DIFERENTE do enum `tipo_profissional_saude` acima (RBAC
 * novo, não substitui o gate binário antigo nesta tarefa — ver cabeçalho
 * da migration). Não é um enum Postgres de verdade (a coluna é `text`),
 * mas os 6 papéis padrão do seed são sempre estes.
 */
export type PapelCodigo = 'admin' | 'medico' | 'nutricionista' | 'personal' | 'fisioterapeuta' | 'atleta';

/** Estrutura livre de `planejamento_clinico.estrutura_plano_jsonb` para planos do tipo `treino_garmin` — ver GarminPrescriptionForm. */
export interface PlanoTreinoEstrutura {
  tipoTreino: 'corrida' | 'ciclismo';
  duracaoMinutos: number;
  zonaFcAlvoMin: number;
  zonaFcAlvoMax: number;
  dataAgenda: string;
  observacoes?: string;
}
