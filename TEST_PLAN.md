# 📋 Plano de Testes — Deploy F10/F15/F45/F46

**Data:** 2026-07-31  
**Commits:** 5 (188eeb1 → 4c9b945)  
**Ambiente:** Staging/Production

---

## 🎯 Checklist de Testes

### **1. F10 Passo 3 — Confirmação do Prato (UI Fix)**

#### 1.1 Teste de Overflow
- [ ] **Abrir App Mobile** (Flutter) → Tela "Confirmar Prato"
- [ ] **Dispositivo:** Galaxy S24 (tela pequena, 360px width)
- [ ] **Ação:** Selecionar foto com múltiplos itens (arroz + feijão + carne)
- [ ] **Esperado:** Texto de macros ("61 kcal • 3.8g prot...") **NÃO estoura** na tela
- [ ] **Validação:** Sem "RIGHT OVERFLOWED BY X PIXELS" no console
- **Status:** ✅ / ❌

#### 1.2 Teste de Responsividade
- [ ] **Dispositivo:** iPad (tela grande, 1024px width)
- [ ] **Esperado:** Layout expande normalmente, sem quebra
- **Status:** ✅ / ❌

#### 1.3 Teste de Interação
- [ ] **Botão "Confirmar":** Funciona sem erros
- [ ] **Botões de quantidade:** +/- mudam valores
- [ ] **Botão de remover:** Remove itens da lista
- **Status:** ✅ / ❌

---

### **2. F15 — Histórico Clínico (Seed Data)**

#### 2.1 Verificar Dados Inseridos
```bash
# No Supabase SQL Editor:
SELECT COUNT(*) FROM eventos_anomalias_saude 
WHERE origem = 'seed_demo_f15';
# Esperado: 7 eventos
```
- **Status:** ✅ / ❌ (Resultado: ___)

#### 2.2 Abrir Painel B2B
- [ ] **Login:** `educarmo@gmail.com` / senha
- [ ] **Ir para:** "Meus Pacientes"
- [ ] **Selecionar:** Ana Paula Ferreira (idx=1)
- [ ] **Aba "Insights" / "Caixa Preta":** Mostrar anomalias?
  - ✅ Queda de HRV (15.5 vs. 25 mín)
  - ✅ Pico de FC (98 vs. 85 máx)
- **Status:** ✅ / ❌

#### 2.3 Verificar Exames (Desvio Conhecido)
```bash
# No Supabase SQL Editor:
SELECT COUNT(*) FROM resultados_exames 
WHERE usuario_id_anonimo = '<ana-uuid>'
AND tipo_exame IN ('Glicose', 'Colesterol LDL', 'Testosterona');
# Esperado: 2-3 exames (ou 0 se PostgREST schema cache issue)
```
- **Status:** ✅ (inserido) / ⚠️ (schema cache) / ❌ (erro)

---

### **3. F45 — Carga Completa da TACO**

#### 3.1 Verificar Alimentos Carregados
```bash
# Supabase SQL:
SELECT COUNT(*) FROM alimentos_referencia;
# Esperado: ≥38 alimentos (antes: 5, agora: ~43)

SELECT COUNT(*) FROM alimentos_medidas_caseiras;
# Esperado: ≥266 (antes: ~15, agora: ~281)
```
- **Alimentos:** ✅ / ❌ (Resultado: ___)
- **Medidas:** ✅ / ❌ (Resultado: ___)

#### 3.2 Testar Reconhecimento de Alimentos
- [ ] **App Mobile → Foto do Prato:** Tirar foto com:
  - Arroz
  - Feijão
  - Carne
  - Couve
- [ ] **Esperado:** Todos os alimentos são reconhecidos (não "Medida não cadastrada")
- [ ] **Confiança:** >60% para cada item
- **Status:** ✅ / ❌

#### 3.3 Verificar Aliases
```bash
# Supabase SQL:
SELECT aliases FROM alimentos_referencia 
WHERE nome_taco LIKE 'Arroz%' LIMIT 1;
# Esperado: ["arroz", "arroz branco", "arroz cozido", ...]
```
- **Status:** ✅ / ❌

---

### **4. F46 — Embeddings Semânticos**

#### 4.1 Verificar Embeddings Gerados
```bash
# Supabase SQL:
SELECT COUNT(*) FROM alimentos_referencia 
WHERE embedding IS NOT NULL;
# Esperado: 38 (todos preenchidos)

SELECT embedding::text FROM alimentos_referencia 
WHERE nome_taco = 'Arroz, branco, cozido' LIMIT 1;
# Esperado: "[0.123, 0.456, ..., -0.789]" (768 dimensões)
```
- **Embeddings:** ✅ / ❌ (Resultado: ___)
- **Formato:** Valido (array 768 dims) ✅ / ❌

#### 4.2 Testar Edge Function `search-food`
```bash
# Terminal:
curl -X POST https://[SUPABASE_URL]/functions/v1/search-food \
  -H "Authorization: Bearer [JWT]" \
  -H "Content-Type: application/json" \
  -d '{"query": "arroz soltinho"}'
```

**Esperado:**
```json
{
  "results": [
    {
      "nome_taco": "Arroz, branco, cozido",
      "similarity": 0.82
    }
  ],
  "cache_hit": false
}
```

- **Resposta HTTP:** 200 ✅ / ❌
- **Campo `results`:** Preenchido ✅ / ❌
- **Similarity:** >0.68 ✅ / ❌
- **Cache hit:** false (primeira busca) ✅ / ❌

#### 4.3 Testar Cache de Sinônimos
```bash
# Executar mesmo query novamente:
curl -X POST ... -d '{"query": "arroz soltinho"}'
```

**Esperado:**
```json
{
  "results": [...],
  "cache_hit": true
}
```

- **Cache hit:** true (segunda busca) ✅ / ❌
- **Tempo resposta:** <20ms (cache hit) ✅ / ❌

#### 4.4 Teste de Modelo Correto
```bash
# Verificar logs da Edge Function:
# "Modelo Gemini: text-embedding-004"
```
- **Modelo correto:** text-embedding-004 ✅ / ❌
- **Sem mock:** Verdadeiro embedding da API ✅ / ❌

---

### **5. Testes de Integração**

#### 5.1 Fluxo Completo: Foto → Reconhecimento → Confirmação
- [ ] **App Mobile:**
  1. Tirar foto do prato (com múltiplos itens)
  2. Esperar reconhecimento via Gemini
  3. Verificar se alimentos são reconhecidos (não "Medida não cadastrada")
  4. Editar quantidades se necessário
  5. Confirmar e salvar
- [ ] **Esperado:** Sucesso sem erros
- **Status:** ✅ / ❌

#### 5.2 Painel B2B: Histórico Clínico Completo
- [ ] **B2B → Paciente Ana Paula:**
  1. Abrir "Exames" → Ver Glicose/Colesterol (se inseridos)
  2. Abrir "Insights/Caixa Preta" → Ver anomalias de HRV/FC
  3. Verificar datas e valores realistas
- **Status:** ✅ / ❌

#### 5.3 Performance: Busca Semântica <500ms
- [ ] **Executar:** `curl ... search-food` (cache miss)
- [ ] **Tempo:** <500ms total
- **Status:** ✅ (dentro do SLA) / ❌ (timeout/lento)

---

## 📊 Relatório de Resultados

### **Resumo Executivo**
- **Total de Testes:** ___ / 35
- **Passou:** ___ ✅
- **Falhou:** ___ ❌
- **Taxa de Sucesso:** ___%

### **Desvios Conhecidos**
- ⚠️ **F15 Exames:** PostgREST schema cache issue (não bloqueia MVP)
- ✅ Resto: Funcional

### **Bloqueadores Críticos**
- [ ] Nenhum identificado
- [ ] (listar se encontrado)

### **Melhorias Futuras**
- [ ] F46+1: Criar índices vetoriais (500+ alimentos)
- [ ] F47: QA de Recuperação de Senha
- [ ] F15: Resolver schema cache issue de exames

---

## 🚀 Instruções para Execução

### **Pré-requisitos**
1. ✅ Deployed em staging/production (main branch)
2. ✅ Supabase cloud com migrations aplicadas
3. ✅ App mobile compilado e instalado
4. ✅ JWT válido para APIs

### **Tester Responsável**
- Nome: _______________
- Data: 2026-07-31
- Ambiente: [ ] Staging [ ] Production

### **Sign-off**
- [ ] Todos os testes passaram
- [ ] Pronto para produção
- [ ] Desvios documentados e aceitos

**Assinado:** _______________  
**Data:** _______________

---

## 📝 Notas Adicionais

```
[Espaço para anotações, screenshots, logs de erro, etc.]
```

