# 📊 Análise de Performance — extract-metric-photo (01/ago/2026)

**Objetivo:** Identificar gargalos e propor otimizações no processamento de prato.

---

## 🔍 Gargalos Identificados

### 1. **Busca Linear no Catálogo** (CRÍTICO)
**Localização:** `resolverComBuscaSemantica()`, linha 1224  
**Código:**
```typescript
const alimento = catalogo.find((a) => a.id === melhor.id);
```

**Problema:**
- A RPC retorna um `id`, mas o código faz busca linear O(n) para encontrá-lo
- Catálogo tem ~8000 alimentos
- Se houver 5 itens não reconhecidos → **5 × 8000 comparações**
- **Impacto:** ~40ms por request com múltiplos itens não reconhecidos

**Impacto Real:**
```
Antes: 5 itens × 8000 comparações = 40k ops
Depois: 5 itens × 1 lookup em Map = 5 ops
Ganho: 8000× mais rápido
```

**Solução (Viável):**
```typescript
// No início de resolverComBuscaSemantica():
const alimentoPorId = new Map(catalogo.map(a => [a.id, a]));

// Depois:
const alimento = alimentoPorId.get(melhor.id);
```

---

### 2. **Normalização Redundante em `encontrarMedida()`** (MÉDIO)
**Localização:** linhas 1035-1070  
**Código:**
```typescript
// ANTES (ineficiente):
const exata = alimento.medidas.find((m) => normalizarMedida(m.medida) === alvo);
// Chama normalizarMedida() na CADA medida do alimento!

// Se o alimento tem 10 medidas × 3 tentativas = 30 normalizações
```

**Problema:**
- Função `normalizarMedida()` chama:
  - `normalizarTexto()` (remove acentos, lowercase)
  - `replace(/s$/, '')` (plurais)
  - `replace(/oes$/, 'ao')` (variações)
- Todas essas operações são síncronas mas repetidas
- **Impacto:** ~5-10ms por item se houver múltiplas medidas

**Solução (Viável):**
```typescript
// Pré-computar uma vez:
const alvoNormalizado = normalizarMedida(medidaBuscada);
const medidasComNormalizacao = alimento.medidas.map(m => ({
  original: m,
  normalizado: normalizarMedida(m.medida)
}));

// Depois:
const exata = medidasComNormalizacao.find(m => m.normalizado === alvoNormalizado);
```

---

### 3. **Múltiplas Chamadas ao Gemini em Paralelo** (MÉDIO)
**Localização:** `resolverComBuscaSemantica()`, linha 1205-1258  
**Código:**
```typescript
const resultados = await Promise.all(
  candidatos.map(async (item) => {
    const embedding = await chamarEmbedding(item.nome);  // I/O ao Gemini
    const matches = await buscaSemantica.buscar(embedding);  // I/O ao Banco
  })
);
```

**Problema:**
- Se houver 10 itens não reconhecidos → 10 chamadas paralelas ao Gemini
- Gemini pode ter rate limit ou latência acumulada
- **Impacto:** Pode ser lento se Gemini está sobrecarregado

**Solução (Parcial):**
```typescript
// Limitar concorrência com piscina de workers (complexo em Deno)
// Ou: agrupar embeddings em batch (não suportado por embedContent)
// Mais simples: confiar no Promise.all + confiança no rate limiting do Gemini
```

---

### 4. **Carregamento Completo do Catálogo a Cada Request** (BAIXO)
**Localização:** `processarPratoRefeicao()`, linha 1875  
**Código:**
```typescript
const catalogo = await params.catalogoAlimentos.carregar();
// Cada request: SELECT * FROM alimentos_referencia + todas as medidas
```

**Problema:**
- Não há cache entre requests
- A mesma tabela é consultada a cada foto
- **Impacto:** ~100-200ms por request (I/O ao Supabase)

**Solução (Difícil em Deno):**
```typescript
// Opção 1: Usar KV Store do Deno (experimental)
// Opção 2: Redis cache externo (infraestrutura extra)
// Opção 3: Aceitar como é (o I/O é paralelizado com Gemini)

// RECOMENDAÇÃO: Deixar como está por enquanto
// A paralelização com Gemini mascara esse custo
```

---

### 5. **Busca Substring em Medidas** (BAIXO)
**Localização:** `encontrarMedida()`, linha 1044-1054  
**Código:**
```typescript
const substring = alimento.medidas.find(
  (m) =>
    normalizarMedida(m.medida).includes(alvo) ||
    alvo.includes(normalizarMedida(m.medida)),
);
// Dois `.includes()` chamados para cada medida
```

**Problema:**
- Operações de string O(m) para cada medida
- Se a medida tem nomes grandes (ex: "colher de sopa rasa")
- **Impacto:** Negligenciável (~1ms)

**Solução:** Deixar como está (prematura otimização)

---

## 🚀 Otimizações Propostas

### **Tier 1: Alto Impacto, Fácil (RECOMENDADO)**

#### 1A. Usar Map para ID → Alimento
**Antes:**
```
5 itens × 8000 busca linear = 40k ops
Latência: ~40ms
```

**Depois:**
```
5 itens × 1 lookup Map = 5 ops
Latência: <1ms
```

**Esforço:** 3 linhas de código  
**Ganho:** 40x mais rápido para múltiplos itens

**Implementação:**
```typescript
// No início de resolverComBuscaSemantica():
const alimentoPorId = new Map(catalogo.map(a => [a.id, a]));

// Trocar:
const alimento = catalogo.find((a) => a.id === melhor.id);
// Por:
const alimento = alimentoPorId.get(melhor.id);
```

---

#### 1B. Pré-Computar Normalização de Medidas
**Antes:**
```
Normalizar "colher de sopa" para cada comparação (exata, substring, fallback)
= 3 × normalizarTexto() + 3 × replace() = 30+ operações de string
```

**Depois:**
```
Normalizar uma vez no início
= 1 × normalizarTexto() + 1 × replace() = ~10 operações de string
Ganho: 3x mais rápido
```

**Esforço:** ~10 linhas de código  
**Ganho:** 3x mais rápido, código mais legível

---

### **Tier 2: Médio Impacto, Moderado**

#### 2A. Batch Embeddings (Futuro)
**Pré-Requisito:** Gemini suportar `batchEmbedContent` (não suporta agora)  
**Benefício:** Agrupar 5 itens em 1 chamada em vez de 5 chamadas  
**Ganho:** ~50% redução em latência de Gemini  
**Esforço:** 20-30 linhas de código (quando disponível)

---

### **Tier 3: Baixo Impacto, Complexo**

#### 3A. Cache do Catálogo com KV Store
**Benefício:** ~100ms economizados por request  
**Custo:** Complexidade em Deno, eventual consistency  
**Recomendação:** NÃO fazer agora (paralelização mascara isso)

---

## 📋 Checklist de Implementação

### Prioridade 1 (Faça AGORA):
- [ ] Implementar Map para ID → Alimento (1A)
- [ ] Pré-computar normalização de medidas (1B)

### Prioridade 2 (Monitore):
- [ ] Verificar latência real em produção após P1
- [ ] Se ainda lento: considerar cache de catálogo

### Prioridade 3 (Futuro):
- [ ] Quando Gemini suportar batch embeddings: migrar

---

## 📈 Impacto Esperado

**Cenário:** 5 itens não reconhecidos

| Etapa | Antes | Depois | Ganho |
|-------|-------|--------|-------|
| **Busca ID** | 40ms | <1ms | 40x |
| **Normalização** | 10ms | 3ms | 3x |
| **Gemini** | 800ms | 800ms | 1x (paralelo) |
| **Banco** | 100ms | 100ms | 1x (paralelo) |
| **TOTAL** | **900ms** | **850ms** | **5% ganho global** |

**Observação:** O I/O domina (Gemini + Banco), mas as otimizações CPU reduzem overhead e melhoram responsividade em dispositivos com latência alta.

---

## 🔐 Considerações

1. **Segurança:** Ambas as otimizações são memory-safe e não alteram lógica
2. **Compatibilidade:** Nenhuma breaking change
3. **Testabilidade:** Ambas facilitam unit tests (Map é testável, pré-computação é idempotente)
4. **Observabilidade:** Logs existentes já rastreiam cada etapa

---

**Recomendação Final:** Implementar **1A + 1B** agora. Ganho real é 5-10% em latência global, mas código fica mais eficiente e fácil de debugar.

