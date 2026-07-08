-- cadastro_controller.dart envia nickname/pais/geo_ranking_id do formulário de
-- cadastro para perfis_usuarios, mas essas colunas não existiam no schema
-- inicial (20260706191827_core_schema.sql), que só previa nome/cep/logradouro/
-- bairro/cidade/estado.

alter table perfis_usuarios
  add column nickname text,
  add column pais text,
  add column geo_ranking_id text;
