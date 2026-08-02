# ⚡ Guia Rápido de Teste — 15 minutos

## 🚀 Testes Críticos (Sim/Não)

### **1. Mobile App — F10 Passo 3 (2 min)**
```
✅ TESTE: Tirar foto do prato → Verificar se macronutrientes NÃO estouram
   Dispositivo: Galaxy S24 ou pequeno
   Esperado: Texto "61 kcal • 3.8g prot..." cabe na tela
```

### **2. Painel B2B — F15 Anomalias (2 min)**
```
✅ TESTE: Login B2B → Selecionar "Ana Paula" → Abrir "Insights"
   Esperado: Ver anomalias (HRV, FC, Pressão)
   Resultado: SIM [ ] / NÃO [ ]
```

### **3. Banco — F45 Carga TACO (2 min)**
```
✅ TESTE: Supabase SQL Editor:
   SELECT COUNT(*) FROM alimentos_referencia;
   Esperado: ≥38 alimentos (antes era 5)
   Resultado: _________
```

### **4. Edge Function — F46 Busca (5 min)**
```
✅ TESTE: Terminal:
   curl -X POST https://[URL]/functions/v1/search-food \
     -H "Authorization: Bearer [JWT]" \
     -d '{"query": "arroz soltinho"}'
   
   Esperado: 
   - HTTP 200
   - results array preenchido
   - similarity > 0.68
   - cache_hit: false (primeira busca)
   
   Resultado: ✅ PASSOU [ ] / ❌ FALHOU [ ]
```

### **5. Cache de Sinônimos — F46 (2 min)**
```
✅ TESTE: Executar mesma query novamente
   Esperado: 
   - cache_hit: true
   - Tempo < 20ms
   
   Resultado: ✅ PASSOU [ ] / ❌ FALHOU [ ]
```

---

## 📊 Resultado Final

| Feature | Status | Notas |
|---|---|---|
| **F10 UI** | ✅/❌ | Overflow corrigido? |
| **F15 Anomalias** | ✅/❌ | Dados aparecem no B2B? |
| **F45 TACO** | ✅/❌ | 38+ alimentos? |
| **F46 Embeddings** | ✅/❌ | API funciona? |
| **F46 Cache** | ✅/❌ | Cache hit funciona? |

**Status Geral:** 
- [ ] ✅ TUDO OK — Pronto para produção
- [ ] ⚠️ PARCIAL — Desvios conhecidos, aceitável
- [ ] ❌ BLOQUEADO — Aguardando fix

---

## 🔴 Se Algo Falhar

### **Falha: "Medida não cadastrada" ainda aparece**
- **Causa:** TACO não foi carregada
- **Fix:** Verificar se `seed_taco_completa.ts` rodou com sucesso
- **Comando:** `npx tsx web_painel/scripts/seed_taco_completa.ts`

### **Falha: F46 retorna 404 ou erro**
- **Causa:** Edge Function não deployada
- **Fix:** `supabase functions deploy search-food`

### **Falha: Cache hit sempre false**
- **Causa:** Tabela `cache_sinonimos_alimentos` sem permissões
- **Fix:** Verificar GRANT em migrations

### **Falha: Embeddings vazios**
- **Causa:** seed_food_embeddings não rodou ou falhou
- **Fix:** Rodar script novamente com chave Gemini válida

---

## 📞 Suporte Rápido

| Problema | Solução |
|---|---|
| "Text-embedding-004 not found" | ✅ CORRIGIDO em commit 4c9b945 |
| "Schema cache issue" resultados_exames | ⚠️ CONHECIDO, não bloqueia |
| Overflow ainda visível | ❌ Reportar bug, check Flutter layout |

---

**Tester:** ___________  
**Data:** ___________  
**Resultado:** ✅ / ⚠️ / ❌  

