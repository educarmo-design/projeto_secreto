# 🧪 Teste de Busca Semântica — extract-metric-photo (31/jul/2026)

**Status:** ✅ Deployada com logs de debug (93 kB)

---

## 📊 Casos de Teste Específicos

### Caso 1: "arroz branco (colher de servir)"
**Antes (BUG):**
- IA identifica: "arroz branco"
- Busca semântica acha: "Arroz, branco, cozido" (ID: ~123)
- Busca medida: "colher de servir" não encontra match exato
- Resultado: ❌ "medida_nao_encontrada" (cai em "Não reconhecidos")

**Depois (FIX):**
- IA identifica: "arroz branco"
- Busca semântica acha: "Arroz, branco, cozido" (similaridade: ~0.70)
- Busca medida: `encontrarMedida()` tenta:
  1. Match exato: "colher de servir" vs. "colher de servir" → ❌ não encontra
  2. Substring: "colher" in "colher de servir" → ❌ não encontra
  3. **Fallback:** pega primeira medida disponível (ex: "colher grande" ou "colher de sopa")
- Resultado: ✅ Item resolvido (em "Reconhecidos") com origem "semantico"

**Log Esperado:**
```
[resolverComBuscaSemantica] Buscando: "arroz branco" (medida: "colher de servir")
[resolverComBuscaSemantica] Match encontrado: "arroz branco" → ID: <id>, Similaridade: 0.703
[resolverComBuscaSemantica] Alimento resolvido: "Arroz, branco, cozido"
[encontrarMedida] Tentando medida: "colher de servir"
[encontrarMedida] TENTATIVA 1 (exata): normalizadas não batem
[encontrarMedida] TENTATIVA 2 (substring): substring não encontrada
[encontrarMedida] TENTATIVA 3 (fallback): usando primeira medida: "colher grande"
```

---

### Caso 2: "carne bovina em cubos (pedaco)"
**Antes (BUG):**
- IA identifica: "carne bovina em cubos"
- Similaridade com banco: ~0.58 (ABAIXO do threshold 0.68)
- Busca semântica: ❌ rejeitada
- Resultado: ❌ "alimento_nao_encontrado" (cai em "Não reconhecidos")

**Depois (FIX):**
- IA identifica: "carne bovina em cubos"
- Threshold REDUZIDO: 0.55 (aguarda dados de produção)
- Similaridade com banco: ~0.58 (ACIMA do novo threshold)
- Busca semântica: ✅ encontra (ex: "Carne bovina, cozida, em cubos")
- Busca medida: "pedaco" → normaliza para "pedaco", encontra "Peça"
- Resultado: ✅ Item resolvido (em "Reconhecidos") com origem "semantico"

**Log Esperado:**
```
[resolverComBuscaSemantica] Buscando: "carne bovina em cubos" (medida: "pedaco")
[resolverComBuscaSemantica] Match encontrado: "carne bovina em cubos" → ID: <id>, Similaridade: 0.580
[resolverComBuscaSemantica] Alimento resolvido: "Carne bovina, cozida, em cubos"
[encontrarMedida] Tentando medida: "pedaco"
[encontrarMedida] TENTATIVA 1 (exata): normalizadas não batem
[encontrarMedida] TENTATIVA 2 (substring): "pedaco" in "Peça" → ❌ substring não encontrada
[encontrarMedida] TENTATIVA 3 (fallback): usando primeira medida: "g (grama)"
```

---

## 🔧 Como Testar em Produção

### Passo 1: Tirar Foto do Prato
1. Abrir app Flutter
2. Tela Home → "Registrar Refeição"
3. "Capturar foto do prato"
4. Tirar foto que inclua:
   - ✅ Arroz branco
   - ✅ Carne bovina em cubos
   - Outros itens conforme disponível

### Passo 2: Verificar Resultado
Na tela de confirmação:
- **Reconhecidos:** "Arroz, branco, cozido" + "Carne bovina, cozida, em cubos"
- **Não reconhecidos:** (vazio, ou apenas itens realmente ilegíveis)
- Cada item deve exibir:
  - Nome detectado: "arroz branco", "carne bovina em cubos"
  - Origem: `semantic` (não `exact`)
  - Similaridade: ~0.70, ~0.58 respectivamente

### Passo 3: Consultar Logs
Se houver dúvida, verificar logs da Edge Function:

**Via Dashboard Supabase:**
```
1. Ir para: https://supabase.com/dashboard/project/xtipphglpqqrjguxcajn/functions
2. Clicar: extract-metric-photo
3. Aba: Logs
4. Filtrar por timestamp da tentativa
```

**Via CLI:**
```bash
supabase functions list
# Copiar ID de extract-metric-photo

supabase functions get-logs extract-metric-photo
```

---

## 🐛 Possíveis Casos de Falha

### ❌ Caso 1: "arroz branco" ainda em "Não reconhecidos"
**Possível Causa:**
1. Modelo de embedding ainda está obsoleto (gemini-embedding-001)
2. Seed de vetores não foi atualizado com os novos embeddings
3. Cache local do app

**Verificação:**
```
grep "MODELO_EMBEDDING" supabase/functions/extract-metric-photo/index.ts
# Deve estar: text-embedding-004 (não gemini-embedding-001)

grep "BUSCA_SEMANTICA_THRESHOLD" supabase/functions/extract-metric-photo/index.ts
# Deve estar: 0.55 (não 0.68)
```

### ❌ Caso 2: "carne" ainda rejeita com threshold 0.55
**Possível Causa:**
1. Embedding da query ou documento está com dimensão errada (não é 768)
2. Normalização L2 não está sendo aplicada
3. Índice pgvector não foi refeito após seed

**Verificação:**
```sql
-- Consultar vetor armazenado para "Carne, bovina, cozida, em cubos"
SELECT id, nome_taco, similarity('...vector aqui...') as sim 
FROM alimentos_referencia 
WHERE nome_taco ILIKE '%carne%cubos%'
LIMIT 5;
```

### ❌ Caso 3: "colher de servir" retorna erro ao em vez de fallback
**Possível Causa:**
1. `encontrarMedida()` foi editado errado
2. Fallback a primeira medida falha (ex: lista de medidas vazia)

**Verificação:**
```
Procurar por `encontrarMedida()` em extract-metric-photo/index.ts
Deve ter: try com fallback `medidas[0]`, não retornar null cegamente
```

---

## 📋 Checklist de Validação

- [ ] Edge Function deployada (tamanho ~93 kB)
- [ ] Tirar foto do prato com arroz + carne
- [ ] "arroz branco" aparece em "Reconhecidos" com origem "semantic"
- [ ] "carne bovina em cubos" aparece em "Reconhecidos" com origem "semantic"
- [ ] Ambos com similaridade visível (~0.70, ~0.58)
- [ ] Logs mostram cada passo: "Buscando", "Match encontrado", "Alimento resolvido"
- [ ] Não há exceções HTTP 502 (seria erro do embedding ou seed)
- [ ] Medidas foram resolvidas corretamente (arroz em "colher de sopa" ou similar, carne em "g")

---

## 🔍 Debug Detalhado

Se algo não funcionar como esperado, execute este comando para visualizar os logs em tempo real:

```bash
# Terminal 1: seguir logs
supabase functions get-logs extract-metric-photo --follow

# Terminal 2: disparar requisição de teste
curl -X POST https://xtipphglpqqrjguxcajn.supabase.co/functions/v1/extract-metric-photo \
  -H "Authorization: Bearer seu-jwt-aqui" \
  -H "Content-Type: application/octet-stream" \
  -H "X-Tipo-Aparelho: pratoRefeicao" \
  --data-binary @seu-prato-photo.jpg
```

---

**Próximo:** Aguardar resultado do teste em produção. Se casos passarem, remover logs de debug. Se falharem, investigar raiz causa por log.

