-- N16 (Documento Mestre v7.0, Parte V1.I) — Hidratação: registro em ml, por
-- copo (padrão 200 ml, CONFIGURÁVEL pelo usuário). O registro em si não
-- precisa de tabela nova: `coleta_diaria` (F34,
-- 20260730130000_coleta_diaria_eav.sql) já é o EAV genérico de leituras
-- frequentes — uma linha por registro de água, `atributo = 'agua_ml'`,
-- `valor_numerico` = mililitros, `unidade = 'ml'`, `origem = 'manual'`
-- (usuário sempre digita/toca, nunca vem de foto/OCR). RLS/GRANT já
-- cobrem a tabela inteira, nenhuma policy nova necessária.
--
-- O único dado novo é a PREFERÊNCIA de tamanho do copo — dado de perfil
-- (muda raramente), não uma métrica diária, mesmo raciocínio de
-- perfis_usuarios.altura_cm (20260811130000): mora em `perfis_usuarios`,
-- não em `coleta_diaria`.

alter table perfis_usuarios
  add column if not exists tamanho_copo_ml int not null default 200;

comment on column perfis_usuarios.tamanho_copo_ml is
  'N16 — tamanho do copo padrão (ml) usado pelo botão "+1 copo" da tela de hidratação; editável pelo usuário, começa em 200 ml. Faixa plausível (50–1000 ml) validada só client-side (RegistroHidratacaoPage), mesmo padrão de altura_cm — não é dado regulatório, não precisa de CHECK no banco.';
