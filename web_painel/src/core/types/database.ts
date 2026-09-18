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
          /** ENUM Postgres `sexo_biologico_enum` desde 20260812100000 — antes era `text` livre, nunca coletado (achado do RELATÓRIO 20260812_0008). */
          sexo_biologico: SexoBiologico | null;
          eh_profissional: boolean;
          tipo_profissional: TipoProfissionalSaude | null;
          /** CRM/CRN/CREFITO/CREF — texto livre, cada conselho tem formato próprio (20260722120000). NÃO cifrado (D2 só cobre nome/telefone/email). */
          registro_profissional: string | null;
          nickname: string | null;
          // altura_cm/peso_kg REMOVIDAS (RELATÓRIO 20260916_0001, SSOT):
          // peso/altura pararam de ser atributo permanente do perfil — a
          // fonte oficial agora é `anamneses.altura_cm`/`peso_kg` (snapshot
          // por versão da Anamnese, docs/motor_metabolico.txt).
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
          /** kg — bioimpedância, input do Motor Metabólico N07 (Katch-McArdle). `20260808120000`. */
          massa_magra_kg: number | null;
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
       * `met_estimado` (RELATÓRIO 20260811_0007, `20260811240000`) — MET da
       * modalidade, input do Motor N07 (futuro); `null` até o Admin cadastrar.
       */
      tipos_atividades_fisicas: {
        Row: {
          id: string;
          nome_codigo: string;
          nome_exibicao: string;
          met_estimado: number | null;
          /** RELATÓRIO 20260825_0003 — 'ambas' | 'android' | 'ios': em qual seção do enum `HealthWorkoutActivityType` o código vive. Só documentação (a FK usa `nome_codigo`), pra nunca mais depender de conferir o enum inteiro na mão de novo. */
          plataforma: 'ambas' | 'android' | 'ios';
        };
        Insert: Partial<Database['public']['Tables']['tipos_atividades_fisicas']['Row']> & {
          nome_codigo: string;
          nome_exibicao: string;
        };
        Update: Partial<Database['public']['Tables']['tipos_atividades_fisicas']['Row']>;
        Relationships: [];
      };

      /**
       * N09 (RELATÓRIO 20260811_0007, `20260811240000`) — catálogo de
       * problemas de saúde (comorbidades) autodeclarados na Anamnese
       * (self-service, app Flutter). Mais simples que `alergias` por pedido
       * do fundador: só id + nome.
       */
      problemas_saude: {
        Row: {
          id: string;
          nome: string;
        };
        Insert: Partial<Database['public']['Tables']['problemas_saude']['Row']> & {
          nome: string;
        };
        Update: Partial<Database['public']['Tables']['problemas_saude']['Row']>;
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
          /**
           * Categorização de consumo — migration `20260802120000_
           * categorias_alimentos_pesos_padrao.sql`. Faltavam neste arquivo
           * de tipos desde então (achado da investigação 20260823_0003:
           * era por isso que AdminAlimentos.tsx nunca expunha estes
           * campos, não só decisão de design).
           */
          categoria_consumo: 'liquido_frio' | 'liquido_quente' | 'unidade' | 'fatia' | 'peso_livre' | null;
          unidade_medida_padrao: 'g' | 'ml' | null;
          medida_padrao_nome: string | null;
          medida_padrao_qtd: number | null;
          /**
           * RELATÓRIO 20260823_0004 — migration `20260823100000_revisao_
           * alimentos_e_medidas_caseiras.sql`. `true` quando a curadoria
           * (bulk IA ou manual) não teve confiança total na classificação.
           */
          revisao_necessaria: boolean;
          observacao_revisao: string | null;
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
          /** RELATÓRIO 20260823_0004 — mesma semântica do campo irmão em `alimentos_referencia`, escopada a esta medida. */
          revisao_necessaria: boolean;
          observacao_revisao: string | null;
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

      /**
       * N10/N11 (RELATÓRIO 20260812_0010) — meta calórica/macros, prescrita
       * (`profissional_id` preenchido) ou self-service (`null`). SEM
       * `Insert`/`Update` de propósito: a tabela não tem policy de escrita
       * para `authenticated` — a ÚNICA porta de gravação é a RPC
       * `validar_e_salvar_meta` (Motor de Exceções N08), nunca um
       * `.insert()`/`.update()` direto. Ver `PrescricaoView.tsx`.
       */
      objetivos_alimentares: {
        Row: {
          id: string;
          usuario_id: string;
          profissional_id: string | null;
          tipo_dia: string;
          calorias_alvo: number;
          proteina_g: number | null;
          carbo_g: number | null;
          gordura_g: number | null;
          data_criacao: string;
          vencimento_em: string | null;
          status_vigencia: 'ativo' | 'historico';
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };

      /**
       * N09 (`20260811240000`) + RELATÓRIO 20260917_0001 (item 1 e 2).
       * INSERT-only por natureza (trigger `anamneses_trg_versionar` — nunca
       * edita uma linha existente, sempre versiona com um INSERT novo);
       * RLS só permite o próprio dono inserir (`anamneses_insert_own`) — o
       * profissional escreve exclusivamente via a RPC
       * `profissional_salvar_anamnese` (nunca um `.insert()` direto daqui),
       * por isso `Insert`/`Update` ficam `never`, mesmo padrão de
       * `objetivos_alimentares` acima.
       */
      /** N:N (`20260811240000`), estendida em `20260918100000` com detalhe por condição (Bloco 8). Só a RPC/o app (RLS own) escrevem. */
      anamneses_problemas_saude: {
        Row: {
          anamnese_id: string;
          problema_saude_id: string;
          data_diagnostico: string | null;
          status: 'ativo' | 'controlado' | 'resolvido' | 'em_investigacao' | null;
          profissional_responsavel: string | null;
          observacoes: string | null;
          evidencias_relacionadas: string | null;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };

      /** N:N (`20260811240000`) — alergias declaradas na anamnese. Só a RPC/o app (RLS own) escrevem. */
      anamneses_alergias: {
        Row: {
          anamnese_id: string;
          alergia_id: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };

      anamneses: {
        Row: {
          id: string;
          usuario_id: string;
          profissional_id: string | null;
          objetivo_codigo: ObjetivoCodigo;
          /** Só preenchido quando `objetivo_codigo = 'outro'` (item 2 — "Outros objetivos personalizados"). */
          objetivo_outro: string | null;
          data_preenchimento: string;
          status_vigencia: 'ativo' | 'historico';
          peso_kg: number | null;
          altura_cm: number | null;
          peso_data_medicao: string | null;
          peso_origem: string | null;
          /** Só preenchido pelo profissional (Anamnese Profissional) — livre, sem a trava fixa de 30 dias do self-service (RELATÓRIO 20260917_0001, item 2). */
          data_proxima_avaliacao: string | null;
          /** Gap Crítico (RELATÓRIO 20260917_0001, item 1) — JSON EXATO de `calcular_motor_metabolico_v1` no momento em que uma Meta foi salva para esta anamnese; `null` até a primeira meta ser salva. */
          resultado_motor_v1: MotorMetabolicoV1Resultado | null;
          resultado_motor_gravado_em: string | null;
          // ---- RELATÓRIO 20260918_0001 (compliance total, Blocos 1-16) ----
          numero_versao: number | null;
          dados_confirmados: boolean;
          confirmado_em: string | null;
          motivo_avaliacao: string | null;
          motivo_avaliacao_outro: string | null;
          objetivos_secundarios: ObjetivoCodigo[];
          meta_peso_desejado_kg: number | null;
          meta_percentual_gordura_desejado: number | null;
          meta_massa_desejada_kg: number | null;
          meta_prazo: string | null;
          meta_outro_indicador: string | null;
          percentual_gordura: number | null;
          massa_gorda_kg: number | null;
          massa_magra_kg: number | null;
          massa_muscular_kg: number | null;
          circunferencia_cintura_cm: number | null;
          circunferencia_abdominal_cm: number | null;
          metodo_avaliacao_composicao: string | null;
          fonte_composicao_corporal: string | null;
          houve_alteracao_peso_nao_planejada: 'sim' | 'nao' | 'nao_sabe' | null;
          numero_refeicoes_dia: number | null;
          horarios_refeicoes_habituais: string | null;
          regularidade_alimentar: string | null;
          refeicoes_fora_de_casa: string | null;
          consumo_ultraprocessados: string | null;
          preferencias_alimentares: string | null;
          alimentos_evitados: string | null;
          restricoes_alimentares: string[];
          intolerancias_alimentares: string[];
          padrao_alimentar_habitual: string | null;
          rotina_diaria:
            | 'predominantemente_sentado'
            | 'pouco_ativo'
            | 'moderadamente_ativo'
            | 'muito_ativo'
            | 'trabalho_fisicamente_intenso'
            | null;
          atividade_ocupacional: string | null;
          horas_sono_medias: number | null;
          horario_dormir_habitual: string | null;
          horario_acordar_habitual: string | null;
          qualidade_sono_percebida: 'muito_ruim' | 'ruim' | 'regular' | 'boa' | 'muito_boa' | null;
          despertares_noturnos: number | null;
          sono_observacoes: string | null;
          possui_condicao_saude: boolean | null;
          bloco_idoso: Record<string, unknown> | null;
          bloco_atleta: Record<string, unknown> | null;
          bloco_recomposicao: Record<string, unknown> | null;
          bloco_diabetes: Record<string, unknown> | null;
          bloco_doenca_renal: Record<string, unknown> | null;
          qualidade_dados: Record<string, unknown> | null;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };

      /**
       * `20260915120000` — rotina semanal opcional por anamnese, paralela a
       * `anamneses_atividades` (que não tem noção de dia da semana). Input
       * de `calcular_motor_metabolico_v1` (estratégia "decomposição") e
       * escrita pela nova RPC `profissional_salvar_anamnese` (Anamnese
       * Profissional) — o app Flutter grava aqui via `.insert()` direto
       * (RLS `..._insert_own`), então `Insert`/`Update` refletem isso.
       */
      anamneses_atividades_dias: {
        Row: {
          anamnese_id: string;
          /** `tipos_atividades_fisicas.id` é `smallint` no banco — este campo usa o tipo tecnicamente correto (diferente de `tipos_atividades_fisicas.id` acima, que já era `string` neste arquivo antes desta tarefa; não foi corrigido aqui, fora de escopo). */
          atividade_id: number;
          /** 0 = domingo .. 6 = sábado (`extract(dow from date)`). */
          dia_semana: number;
          minutos: number;
          /** Bloco 6 (RELATÓRIO 20260918_0001) — obrigatório, NOT NULL sem default no banco. */
          intensidade: 'leve' | 'moderada' | 'alta';
          horario: string | null;
          distancia_km: number | null;
          calorias_dispositivo: number | null;
          fonte: string;
        };
        Insert: Database['public']['Tables']['anamneses_atividades_dias']['Row'];
        Update: never;
        Relationships: [];
      };

      /** Bloco 9 (RELATÓRIO 20260918_0001) — só a RPC `profissional_salvar_anamnese`/o app Flutter (RLS own) escrevem; sem `Insert` direto pelo Painel Web. */
      anamneses_medicamentos: {
        Row: {
          id: string;
          anamnese_id: string;
          nome: string;
          dose: number | null;
          unidade: string | null;
          frequencia: string | null;
          horario: string | null;
          indicacao: string | null;
          data_inicio: string | null;
          data_termino: string | null;
          uso_atual: boolean;
          prescritor: string | null;
          criado_em: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };

      /** Bloco 10 (RELATÓRIO 20260918_0001) — mesmo padrão de `anamneses_medicamentos`. */
      anamneses_suplementos: {
        Row: {
          id: string;
          anamnese_id: string;
          nome: string;
          dose: number | null;
          unidade: string | null;
          frequencia: string | null;
          horario: string | null;
          objetivo: string | null;
          uso_atual: boolean;
          orientacao_profissional: string | null;
          criado_em: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };

      /** Bloco 11 (RELATÓRIO 20260918_0001) — mesmo padrão de `anamneses_medicamentos`. */
      anamneses_exames_laboratoriais: {
        Row: {
          id: string;
          anamnese_id: string;
          data_exame: string | null;
          nome_exame: string;
          resultado: string | null;
          unidade: string | null;
          referencia_laboratorio: string | null;
          origem: string | null;
          documento_origem: string | null;
          criado_em: string;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
    };
    Views: {
      /**
       * Ver `supabase/migrations/*_painel_web_profissional_rls.sql`: só
       * expõe os campos não-sensíveis de `perfis_usuarios` para os
       * pacientes vinculados ao profissional autenticado —
       * `nome`/`telefone`/`email`/endereço nunca aparecem aqui, mesmo que
       * a linha esteja visível. `sexo_biologico` adicionado em
       * `20260812100000` (RELATÓRIO 20260812_0008, N07) — mesma view,
       * mesma regra, um campo a mais.
       */
      perfis_pacientes_vinculados: {
        Row: {
          id: string;
          nickname: string | null;
          data_nascimento: string | null;
          geo_ranking_id: string | null;
          sexo_biologico: SexoBiologico | null;
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

      /**
       * N07 (RELATÓRIO 20260812_0008) — permite o próprio usuário, um
       * profissional com vínculo ATIVO, ou um admin, gravar
       * `sexo_biologico` de um paciente. Única porta de escrita
       * cross-usuário dessa coluna (a view `perfis_pacientes_vinculados`
       * continua só-leitura).
       */
      profissional_atualizar_sexo_biologico: {
        Args: { p_paciente_id: string; p_sexo_biologico: SexoBiologico };
        Returns: void;
      };

      /**
       * N07 (RELATÓRIO 20260812_0008) — Motor Metabólico: TMB
       * (Katch-McArdle com massa magra, senão Mifflin-St Jeor completa),
       * PAL decomposto (gasto_sedentario + gasto_atividade da anamnese
       * ativa), TEF isolado (informativo, nunca somado ao tdee). Nunca
       * lança erro por dado faltante — ver `formula_usada`/`avisos`.
       */
      calcular_motor_metabolico: {
        Args: { p_usuario_id: string };
        Returns: MotorMetabolicoResultado;
      };

      /**
       * N08 (RELATÓRIO 20260812_0010) — Motor de Exceções de dupla via.
       * `p_is_profissional=true` (N10, Painel Web) nunca bloqueia — devolve
       * `violacao_clinica`/`avisos` na resposta. `p_is_profissional=false`
       * (N11, App Flutter) pode lançar `PostgrestException` com mensagem
       * prefixada `N08_TRAVA_CLINICA`/`N08_PRIORIDADE_PROFISSIONAL`/
       * `N08_CARENCIA_MENSAL` — o INSERT nunca acontece nesses casos.
       */
      validar_e_salvar_meta: {
        Args: {
          p_payload: {
            usuario_id?: string;
            tipo_dia?: string;
            calorias_alvo: number;
            proteina_g?: number | null;
            carbo_g?: number | null;
            gordura_g?: number | null;
            vencimento_em?: string | null;
          };
          p_is_profissional: boolean;
        };
        Returns: ValidarESalvarMetaResultado;
      };

      /**
       * `20260916120000` — Motor Metabólico Centralizado V1. Função PURA
       * (ME-005/006 — nunca faz insert/update/delete); peso/altura vêm SSOT
       * da última anamnese com os dois campos preenchidos, nunca de
       * `perfis_usuarios`. Mesmo guard de acesso de `calcular_motor_
       * metabolico` (dono, profissional com vínculo ATIVO, ou admin).
       */
      calcular_motor_metabolico_v1: {
        Args: { p_usuario_id: string };
        Returns: MotorMetabolicoV1Resultado;
      };

      /**
       * RELATÓRIO 20260917_0001 (item 2) — Anamnese Profissional (Painel
       * Web): profissional com vínculo ATIVO preenche uma anamnese nova
       * pro paciente. SEM trava de carência — `data_proxima_avaliacao` é
       * livre. `atividades` é opcional (default `[]`), cada item vira uma
       * linha em `anamneses_atividades_dias`.
       */
      /**
       * RELATÓRIO 20260917_0001 (item 2) + RELATÓRIO 20260918_0001
       * (compliance total, Blocos 1-16) — payload espelha o mesmo conjunto
       * de campos que `AnamneseRepository.salvarAnamnese` (Flutter) grava,
       * ver a migration `20260918110000` para a lista completa de colunas.
       * `dados_confirmados` é sempre gravado como `true` pela RPC (o
       * submit do formulário profissional já É a confirmação — o Painel
       * Web não tem uma 2ª tela de revisão como o app, Seção 11).
       */
      profissional_salvar_anamnese: {
        Args: {
          p_paciente_id: string;
          p_payload: {
            objetivo_codigo: ObjetivoCodigo;
            objetivo_outro?: string | null;
            peso_kg?: number | null;
            altura_cm?: number | null;
            data_proxima_avaliacao?: string | null;
            motivo_avaliacao?: string | null;
            motivo_avaliacao_outro?: string | null;
            objetivos_secundarios?: ObjetivoCodigo[];
            meta_peso_desejado_kg?: number | null;
            meta_percentual_gordura_desejado?: number | null;
            meta_massa_desejada_kg?: number | null;
            meta_prazo?: string | null;
            meta_outro_indicador?: string | null;
            percentual_gordura?: number | null;
            massa_gorda_kg?: number | null;
            massa_magra_kg?: number | null;
            massa_muscular_kg?: number | null;
            circunferencia_cintura_cm?: number | null;
            circunferencia_abdominal_cm?: number | null;
            metodo_avaliacao_composicao?: string | null;
            fonte_composicao_corporal?: string | null;
            houve_alteracao_peso_nao_planejada?: 'sim' | 'nao' | 'nao_sabe' | null;
            numero_refeicoes_dia?: number | null;
            horarios_refeicoes_habituais?: string | null;
            regularidade_alimentar?: string | null;
            refeicoes_fora_de_casa?: string | null;
            consumo_ultraprocessados?: string | null;
            preferencias_alimentares?: string | null;
            alimentos_evitados?: string | null;
            restricoes_alimentares?: string[];
            intolerancias_alimentares?: string[];
            padrao_alimentar_habitual?: string | null;
            rotina_diaria?: string | null;
            atividade_ocupacional?: string | null;
            horas_sono_medias?: number | null;
            horario_dormir_habitual?: string | null;
            horario_acordar_habitual?: string | null;
            qualidade_sono_percebida?: string | null;
            despertares_noturnos?: number | null;
            sono_observacoes?: string | null;
            possui_condicao_saude?: boolean | null;
            bloco_idoso?: Record<string, unknown> | null;
            bloco_atleta?: Record<string, unknown> | null;
            bloco_recomposicao?: Record<string, unknown> | null;
            bloco_diabetes?: Record<string, unknown> | null;
            bloco_doenca_renal?: Record<string, unknown> | null;
            atividades?: { atividade_id: number; dia_semana: number; minutos: number; intensidade?: 'leve' | 'moderada' | 'alta' }[];
            condicoes_saude?: { problema_saude_id: string; data_diagnostico?: string | null; status?: string | null; observacoes?: string | null }[];
            alergias?: string[];
            medicamentos?: { nome: string; dose?: string | null; unidade?: string | null; frequencia?: string | null }[];
            suplementos?: { nome: string; dose?: string | null; unidade?: string | null; objetivo?: string | null }[];
            exames?: { nome_exame: string; resultado?: string | null; unidade?: string | null }[];
          };
        };
        Returns: { sucesso: true; anamnese_id: string };
      };

      /**
       * Bloco 4 (RELATÓRIO 20260918_0001) — "recupera automaticamente
       * informações históricas disponíveis". Função PURA (nunca persiste),
       * reconstrói o histórico de peso a partir das anamneses já
       * existentes.
       */
      anamnese_historico_peso: {
        Args: { p_usuario_id: string };
        Returns: {
          peso_atual: number | null;
          peso_anterior: number | null;
          peso_30_dias: number | null;
          peso_3_meses: number | null;
          peso_6_meses: number | null;
          peso_12_meses: number | null;
          maior_peso: number | null;
          menor_peso: number | null;
          variacao_percentual: number | null;
        };
      };
    };
    Enums: {
      tipo_profissional_saude: TipoProfissionalSaude;
      status_aprovacao_usuario: StatusAprovacaoUsuario;
      status_vinculo: StatusVinculo;
      sexo_biologico_enum: SexoBiologico;
    };
  };
}

/**
 * Espelha o enum Postgres `sexo_biologico_enum` (`20260812100000`,
 * RELATÓRIO 20260812_0008) — input do Motor Metabólico N07.
 */
export type SexoBiologico = 'M' | 'F';

/**
 * Espelha o CHECK constraint `anamneses_objetivo_codigo_check`
 * (RELATÓRIO 20260918_0001) — lista EXATA da Seção 4.1 do documento
 * docs/motor_metabolico.txt. Antes desta tarefa era uma lista menor/
 * divergente ('emagrecimento'/'manutencao'/'hipertrofia'/'outro').
 */
export type ObjetivoCodigo =
  | 'perder_peso'
  | 'manter_peso'
  | 'ganhar_peso'
  | 'reduzir_gordura_corporal'
  | 'ganhar_massa_muscular'
  | 'recomposicao_corporal'
  | 'melhorar_desempenho_esportivo'
  | 'outro';

/** Formato do JSONB devolvido por `calcular_motor_metabolico` — ver comentário da função na migration `20260812100000` para a matemática completa. */
export interface MotorMetabolicoResultado {
  tmb: number | null;
  gasto_sedentario: number | null;
  gasto_atividade: number | null;
  /** 10% da TMB — informativo, NUNCA somado em `tdee` (anti double-count). */
  tef: number | null;
  /** gasto_sedentario + gasto_atividade — nunca inclui o TEF. */
  tdee: number | null;
  formula_usada: 'katch_mcardle' | 'mifflin_st_jeor' | 'dados_insuficientes';
  insumos: {
    idade: number | null;
    sexo_biologico: SexoBiologico | null;
    altura_cm: number | null;
    peso_kg: number | null;
    massa_magra_kg: number | null;
  };
  avisos: string[];
}

/**
 * Formato do JSONB devolvido por `calcular_motor_metabolico_v1` — ver
 * comentário da função na migration `20260916120000` para a matemática
 * completa. Diferente de `MotorMetabolicoResultado` (V0): aqui o TDEE vem
 * por dia da semana (`tdee_por_dia`, chaveado "0" domingo .. "6" sábado),
 * além da média (`tdee_medio`, só preenchida quando os 7 dias têm dado).
 */
export interface MotorMetabolicoV1Resultado {
  motor_versao: 'v1';
  formula_tmb: { codigo: 'TMB-001'; nome: 'Mifflin-St Jeor'; versao: string };
  estrategia_tdee: 'decomposicao_parcial' | 'pal';
  parametros: { pal_padrao: number; pal_versao: string; tef_percentual: number };
  tmb: number | null;
  tef_estimado: number | null;
  tdee_por_dia: Record<string, { tdee: number | null; estrategia: 'decomposicao' | 'pal' | 'dados_insuficientes' }>;
  /** `null` a menos que os 7 dias tenham `tdee` calculado (Seção 13 — não enviesar média com dias faltantes). */
  tdee_medio: number | null;
  insumos: {
    idade: number | null;
    sexo_biologico: SexoBiologico | null;
    altura_cm: number | null;
    peso_kg: number | null;
    peso_data_medicao: string | null;
    /** `null` quando não há anamnese com peso+altura preenchidos — é essa que `validar_e_salvar_meta` usa pra saber onde gravar o snapshot (RELATÓRIO 20260917_0001, item 1). */
    anamnese_id: string | null;
  };
  avisos: string[];
  calculado_em: string;
}

/** Formato do JSONB devolvido por `validar_e_salvar_meta` em caso de sucesso — ver comentário da função na migration `20260812110000` para as regras completas do Motor de Exceções (N08). */
export interface ValidarESalvarMetaResultado {
  sucesso: true;
  id: string;
  /** `true` se alguma das 3 regras numéricas (gordura/calorias vs. TMB) foi violada — para profissional, isso NUNCA impede o `sucesso`; só sinaliza que `avisos` deve virar um banner. */
  violacao_clinica: boolean;
  avisos: string[];
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
