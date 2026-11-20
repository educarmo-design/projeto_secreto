#!/usr/bin/env bash
# verificar_segredos.sh — guarda do CI (N44 / S8.1, Parte 6 do Documento Mestre).
#
# Falha se qualquer arquivo VERSIONADO contiver uma chave PRIVILEGIADA do
# Supabase:
#   - `sb_secret_…`                       (chave secreta nova), ou
#   - um JWT cujo payload tem role=service_role (chave legada).
#
# O que NÃO falha, de propósito: `sb_publishable_…` e o JWT `anon` — são
# chaves públicas por desenho (vão dentro do app e do bundle do painel).
#
# Esta verificação NUNCA imprime o valor encontrado: só o nome do arquivo.
# Rodar localmente: bash .github/scripts/verificar_segredos.sh

set -u
cd "$(git rev-parse --show-toplevel)"

falhou=0

# 1) chave secreta nova — o prefixo sozinho já é inequívoco.
arquivos_secret=$(git ls-files -z | xargs -0 grep -lE 'sb_secret_[A-Za-z0-9_-]{16,}' 2>/dev/null || true)
if [ -n "$arquivos_secret" ]; then
  echo "::error::Chave secreta do Supabase (sb_secret_…) em arquivo versionado:"
  echo "$arquivos_secret" | sed 's/^/  - /'
  falhou=1
fi

# 2) JWT legado com role=service_role — decodifica só o payload, em memória.
#    Uma única passada com xargs acha os arquivos com formato de JWT; só esses
#    são decodificados (um grep por arquivo seria lento demais no Windows).
padrao_jwt='eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}'
while IFS= read -r arquivo; do
  while IFS= read -r token; do
    payload=$(printf '%s' "$token" | cut -d. -f2 | tr '_-' '/+')
    faltam=$(( (4 - ${#payload} % 4) % 4 ))
    [ "$faltam" -gt 0 ] && payload="${payload}$(printf '=%.0s' $(seq 1 "$faltam"))"
    if printf '%s' "$payload" | base64 -d 2>/dev/null | grep -q '"role"[[:space:]]*:[[:space:]]*"service_role"'; then
      echo "::error file=${arquivo}::JWT service_role (chave legada privilegiada) em arquivo versionado."
      falhou=1
    fi
  done < <(grep -oE "$padrao_jwt" "$arquivo" 2>/dev/null | sort -u)
done < <(git ls-files -z | xargs -0 grep -lE "$padrao_jwt" 2>/dev/null || true)

if [ "$falhou" -ne 0 ]; then
  echo "Falhou: remova a chave do arquivo, rotacione-a no Dashboard e use .env.local (nunca versionado)."
  exit 1
fi
echo "OK: nenhuma chave privilegiada do Supabase em arquivos versionados."
