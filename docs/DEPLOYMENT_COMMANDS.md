# 🚀 Comandos de Deployment: Reator de Categorias TACO

**Data:** 2026-08-02  
**Versão:** 1.0  
**Tamanho da mudança:** Migração SQL + Edge Function + Flutter Model

---

## 📋 Pré-requisitos

```bash
# Verificar acesso ao Supabase CLI
supabase --version
# Expected: Supabase CLI X.X.X

# Verificar flutter
flutter --version
# Expected: Flutter X.X.X

# Verificar status do repositório
git status
# Expected: working tree clean (ou staged apenas os nossos commits)
```

---

## **PASSO 1: Aplicar Migração SQL**

### 1.1 Listar migrações pendentes

```bash
supabase migration list
```

**Expected output:**
```
20260802120000_categorias_alimentos_pesos_padrao.sql PENDING
```

### 1.2 Aplicar migração ao banco local (teste primeiro)

```bash
supabase migration up
```

**Expected output:**
```
Applying migration 20260802120000_categorias_alimentos_pesos_padrao.sql...
✓ Migration applied successfully
```

### 1.3 Verificar colunas adicionadas

```bash
supabase db query "
  SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
  WHERE table_name = 'alimentos_referencia'
    AND column_name IN ('categoria_consumo', 'unidade_medida_padrao', 'medida_padrao_nome', 'medida_padrao_qtd')
  ORDER BY column_name;
"
```

**Expected output:**
```
 column_name              | data_type | is_nullable
 categoria_consumo        | varchar   | t
 medida_padrao_nome       | varchar   | t
 medida_padrao_qtd        | numeric   | t
 unidade_medida_padrao    | varchar   | t
(4 rows)
```

### 1.4 Verificar SEEDs foram inseridos

```bash
supabase db query "
  SELECT nome_taco, categoria_consumo, medida_padrao_qtd, unidade_medida_padrao
  FROM alimentos_referencia
  WHERE categoria_consumo IS NOT NULL
  ORDER BY nome_taco;
"
```

**Expected output:**
```
 nome_taco                      | categoria_consumo | medida_padrao_qtd | unidade_medida_padrao
 Alface, lisa, crua             | peso_livre        | 50.00             | g
 Arroz, branco, cozido          | peso_livre        | 100.00            | g
 Azeitona, preta                | unidade           | 5.00              | g
 Café, coado                    | liquido_quente    | 200.00            | ml
 Carne, bovina, contrafilé...   | peso_livre        | 100.00            | g
 Chá, coado                     | liquido_quente    | 200.00            | ml
 Coxinha                        | unidade           | 100.00            | g
 Feijão, carioca, cozido        | peso_livre        | 100.00            | g
 ...
(13 rows)
```

---

## **PASSO 2: Deploy da Edge Function**

### 2.1 Verificar status atual da função

```bash
supabase functions list
```

**Expected output:**
```
FUNCTION                   STATUS     CREATED AT
extract-metric-photo       deployed   2026-06-15T10:30:45.000Z
```

### 2.2 Build local (teste TypeScript)

```bash
cd supabase/functions/extract-metric-photo
deno check index.ts
```

**Expected output:**
```
✓ Runtime check passed
```

### 2.3 Deploy (produção)

```bash
supabase functions deploy extract-metric-photo
```

**Expected output:**
```
Deploying function extract-metric-photo...
✓ extract-metric-photo deployed successfully

Function URL: https://[PROJECT].supabase.co/functions/v1/extract-metric-photo
```

### 2.4 Verificar logs iniciais (sem foto)

```bash
# Esperar 30s após deploy, depois:
supabase functions logs extract-metric-photo --limit=5
```

**Expected output:**
```
[2026-08-02 14:35:22] extract-metric-photo deployed
```

---

## **PASSO 3: Flutter Build & Test**

### 3.1 Clean build

```bash
flutter clean
flutter pub get
```

### 3.2 Run (homolog)

```bash
flutter run --dart-define-from-file=config_local.json
```

**Expected output:**
```
Launching lib/main.dart on [device]...
✓ Built successfully
Running flutter app...
```

### 3.3 Verificar parsing do modelo

Após tela carregar (F10 Passo 3), verificar no log (debug):
```
flutter logs
```

**Expected:**
```
[INFO] ItemPratoExtraidoModel.fromJson: parsed categoria_consumo='unidade'
[INFO] ItemPratoExtraidoModel.fromJson: parsed medida_padrao_qtd=5.0
```

---

## **PASSO 4: Teste Manual (Golden Path)**

### 4.1 Fotografar alimento sem medida caseira

1. Abrir app
2. Navegar para F10 (Foto do Prato)
3. Fotografar **azeitona** isolada ou **pão de queijo** 
4. Confirmar que não quebra

### 4.2 Verificar resposta do backend

Na tela de confirmação, card deve exibir:
```
Azeitona, preta
(5g est.)            👈 categoria_consumo='unidade' foi usado

⚠️ Quantidade estimada
Peso típico: 5g      👈 medida_padrao_qtd=5 foi usado
Editar              👈 botão funcional, dialog abre
```

### 4.3 Editar peso

1. Clicar "Editar"
2. Mudar de 5 para 8
3. Clicar "Salvar"
4. Card deve mostrar `(8g edit.)` em verde
5. Totais de macros devem recompute (+60%)

### 4.4 Alimento órfão (sem categoria)

Se em `alimentos_referencia` houver alimento com `categoria_consumo IS NULL`:

1. Fotografar esse alimento
2. Verificar que não quebra
3. Card deve exibir `(100g est.)` genérico
4. Dialog de edição deve funcionar

---

## **PASSO 5: Auditoria e Cleanup**

### 5.1 Verificar que PESO_TIPICO_GRAMAS foi removido

```bash
grep -r "PESO_TIPICO_GRAMAS" supabase/functions/
```

**Expected:** Nenhuma saída (constante removida)

### 5.2 Verificar que ehAlimentoLiquido não existe mais

```bash
grep -r "ehAlimentoLiquido" supabase/functions/
```

**Expected:** Nenhuma saída (função removida)

### 5.3 Entregar CSV ao Fundador

```bash
# File exists e está pronto para preenchimento
ls -lh docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA.csv
```

**Expected:**
```
-rw-r--r-- 1 user group 2.5K Aug 02 14:40 docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA.csv
```

### 5.4 Relatório técnico gerado

```bash
# Arquivo existe e está documentado
ls -lh docs/RELATORIO_TECNICO_REFACTORING_PESOS_ALIMENTOS.md
```

**Expected:**
```
-rw-r--r-- 1 user group 12K Aug 02 14:40 docs/RELATORIO_TECNICO_REFACTORING_PESOS_ALIMENTOS.md
```

---

## **PASSO 6: Verificação Pós-Deploy (Produção)**

### 6.1 Health check da função

```bash
# Se você tiver token de acesso:
curl -X POST \
  https://[PROD_URL]/functions/v1/extract-metric-photo \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "X-Tipo-Aparelho: pratoRefeicao" \
  -H "X-Image-Mime: image/jpeg" \
  --data-binary @test_image.jpg \
  | jq '.itens[0] | {nome, categoria_consumo, medida_padrao_qtd}'
```

**Expected output:**
```json
{
  "nome": "Azeitona, preta",
  "categoria_consumo": "unidade",
  "medida_padrao_qtd": 5
}
```

### 6.2 Monitorar logs da função

```bash
# Real-time logs (produção)
supabase functions logs extract-metric-photo --tail=20
```

**Look for:**
```
[encontrarMedida] Fallback categorizado: "..." -> "5g (unidade)" para "Azeitona, preta"
```

Se algo der errado:
```
[erro] Falha ao carregar alimentos_referencia
```

---

## **TROUBLESHOOTING**

### ❌ Problema: `categoria_consumo` retorna null no Flutter

**Solução 1:** Verificar se migração foi aplicada
```bash
supabase db query "SELECT COUNT(*) FROM alimentos_referencia WHERE categoria_consumo IS NOT NULL;"
# Must return: 13 (ou número de SEEDs)
```

**Solução 2:** Verificar query de catálogo inclui coluna
```bash
# No código de edge-function, procurar por:
.select('...categoria_consumo, unidade_medida_padrao, ...')
# Deve estar lá
```

**Solução 3:** Limpar cache Flutter
```bash
flutter clean
flutter pub get
flutter run
```

---

### ❌ Problema: Função não depley

**Solução 1:** Build TypeScript localmente
```bash
cd supabase/functions/extract-metric-photo
deno check index.ts
# Se erro, corrigir e tentar denovo
```

**Solução 2:** Verificar syntax
```bash
grep -n "categoriaConsumo" index.ts
# Devem estar nos 3 lugares: interface, query select, mapeamento
```

---

### ❌ Problema: Flutter compila mas card não exibe categoria

**Solução:** Verificar JSON real retornado
```dart
// No code, printando json:
print('Item JSON: ${item.toString()}');
print('Categoria: ${item.original.categoriaConsumo}');

// Rodar com `flutter run --verbose` e verificar output
```

---

## **Rollback (Se Necessário)**

### Reverter migrations

```bash
supabase migration down --num=1
# Isso DESFAZ: 20260802120000_categorias_alimentos_pesos_padrao.sql

git reset --hard HEAD~3  # Voltar 3 commits
git push origin main -f  # ⚠️ Force push (coordenar com time)
```

### Redeploy Edge Function anterior

```bash
git checkout HEAD~3 supabase/functions/extract-metric-photo/index.ts
supabase functions deploy extract-metric-photo
```

---

## **Checklist Final**

- [ ] Migração SQL aplicada (`supabase migration up`)
- [ ] 13 alimentos têm categoria_consumo NOT NULL
- [ ] Edge Function build sem erros (`deno check`)
- [ ] Edge Function deployed (`supabase functions deploy`)
- [ ] Flutter build sem erros (`flutter build apk` ou similar)
- [ ] Teste manual: fotografar azeitona → card exibe "(5g est.)"
- [ ] Teste manual: editar peso → macros recompute
- [ ] Teste manual: alimento órfão → "(100g est.)" genérico
- [ ] CSV entregue ao fundador
- [ ] Relatório técnico revisado
- [ ] Logs da função monitorados por 24h

---

**Todos os passos completados? ✅ Deployment bem-sucedido!**

Para dúvidas, ver: `docs/RELATORIO_TECNICO_REFACTORING_PESOS_ALIMENTOS.md`
