# 📋 Relatório Técnico: Refactoring de Estimação de Pesos de Alimentos

**Data:** 2026-08-02  
**Commits:** `d6608e3`, `9cefb97` (+ migration SQL + CSV)  
**Autor:** Claude Code + Fundador  
**Status:** ✅ Pronto para Teste

---

## 🎯 Missão Arquitetural

Mover inteligência de estimação de peso do **Edge Function (hardcode)** para o **PostgreSQL (Single Source of Truth)**, eliminando:
1. Dicionários chumbados que divergem entre backend e frontend
2. Lógica de pattern-matching que falha com alimentos novos
3. Acoplamento entre código e dados nutricionais

---

## 🗑️ LIXO REMOVIDO (Clean Code)

### **Arquivo: `supabase/functions/extract-metric-photo/index.ts`**

#### 1️⃣ Constante: `PESO_TIPICO_GRAMAS` (Removida)

**O quê era:**
```typescript
const PESO_TIPICO_GRAMAS: Record<string, number> = {
  'Azeitona, 1 unidade': 5,
  'Presunto, 1 fatia': 20,
  'Pão de queijo, 1 unidade': 50,
  // ... 80+ entradas
  'default': 100,
};
```

**Por que era ruim:**
- ✅ **Hardcoded em TypeScript** — mudanças exigem PR, CI/CD, deploy
- ❌ Sem auditoria — nenhum registro de quem validou cada peso
- ❌ Divergência DB/Code — alimento novos cadastrados no DB não têm entrada aqui
- ❌ Sem versionamento — histórico de mudanças perdido em git blame, sem semântica
- 📊 **80+ linhas de dados em formato code**

**Linhas de código removidas:** ~82 linhas

---

#### 2️⃣ Constante: `ALIMENTOS_LIQUIDOS` (Removida)

**O quê era:**
```typescript
const ALIMENTOS_LIQUIDOS = new Set([
  'suco', 'leite', 'café', 'chá', 'refrigerante', 'água', 'vinho',
  'cerveja', 'chope', 'chopp', 'soda', 'limonada', 'chá gelado',
  'achocolatado', 'bebida', 'iogurte líquido', 'leite condensado',
  'caldo', 'canja', 'sopa',
]);
```

**Por que era ruim:**
- ❌ Pattern-matching frágil — "suco" match "suco de laranja" mas não "purê de tomate"
- ❌ Sem contexto — cada item é string nua, sem tipo (frio/quente)
- ❌ Sem estrutura — nova categoria de líquido exige edição manual
- 🔧 **19 itens sem auditoria**

**Linhas de código removidas:** ~21 linhas

---

#### 3️⃣ Constante: `TAMANHO_COPOS_ML` (Removida)

**O quê era:**
```typescript
const TAMANHO_COPOS_ML: Record<string, number> = {
  'pequeno': 150,
  'médio': 250,
  'grande': 350,
  'xícara': 200,
  'xícara pequena': 150,
  'copo americano': 240,
  // ... 11 entradas
  'default': 250,
};
```

**Por que era ruim:**
- ❌ Fallback mágico — `'default': 250` silenciosamente usado se medida não casar
- ❌ Sem semanticidade — valores soltos, sem conexão com alimento específico
- ❌ Sem unidade — ml fixo, nunca ajustável por tipo de bebida

**Linhas de código removidas:** ~13 linhas

---

#### 4️⃣ Função: `ehAlimentoLiquido()` (Removida)

```typescript
function ehAlimentoLiquido(nomeAlimento: string): boolean {
  const nomeLower = nomeAlimento.toLowerCase();
  return Array.from(ALIMENTOS_LIQUIDOS).some((tipo) => nomeLower.includes(tipo));
}
```

**Por que era ruim:**
- ❌ Depende de `ALIMENTOS_LIQUIDOS` (hardcoded)
- ❌ Sem tipagem de subtipo — não diferencia frio/quente
- ❌ Include-match impreciso — "sopa" pode casar com "sopão que não é sopa"

**Linhas de código removidas:** 5 linhas

---

#### 5️⃣ Função: `estimarTamanhoRecipiente()` (Removida)

```typescript
function estimarTamanhoRecipiente(descricaoMedida: string): number {
  const descLower = descricaoMedida.toLowerCase();
  for (const [tipo, ml] of Object.entries(TAMANHO_COPOS_ML)) {
    if (descLower.includes(tipo)) return ml;
  }
  return TAMANHO_COPOS_ML['default']!;
}
```

**Por que era ruim:**
- ❌ Depende de `TAMANHO_COPOS_ML` (hardcoded)
- ❌ Loop de string matching — O(n) e frágil
- ❌ Sem alimento context — assume todos os "copos" medem igual, independente do líquido

**Linhas de código removidas:** 7 linhas

---

#### 6️⃣ Lógica em `encontrarMedida()` — Fallback 4 (Refatorada)

**Antes:**
```typescript
// 4. Fallback final: usar peso típico do alimento...
let pesoTipico = PESO_TIPICO_GRAMAS[alimento.nomeTaco];
if (!pesoTipico) {
  const chaveExpandida = Object.keys(PESO_TIPICO_GRAMAS).find(
    (chave) => chave.startsWith(alimento.nomeTaco),
  );
  pesoTipico = chaveExpandida ? PESO_TIPICO_GRAMAS[chaveExpandida] : PESO_TIPICO_GRAMAS['default']!;
}

const ehLiquido = ehAlimentoLiquido(alimento.nomeTaco);
if (ehLiquido) {
  const mlEstimado = estimarTamanhoRecipiente(medidaBuscada);
  // ...
  return { medida: `${mlEstimado}ml (est.)`, gramas: mlEstimado };
}

console.log(`[encontrarMedida] Fallback sólido: ...`);
return { medida: `${pesoTipico}g (est.)`, gramas: pesoTipico };
```

**Depois:**
```typescript
// 4. Fallback final: usar categoria e peso padrão do alimento (agora vem do DB)
if (!alimento.categoriaConsumo || !alimento.medidaPadraoQtd) {
  console.log(`[encontrarMedida] Fallback genérico (categoria nula): ...`);
  return { medida: '100g (est.)', gramas: 100 };
}

const qtdPadrao = alimento.medidaPadraoQtd;
const unidade = alimento.unidadeMedidaPadrao || 'g';

console.log(`[encontrarMedida] Fallback categorizado: ...`);
return { medida: `${qtdPadrao}${unidade} (est.)`, gramas: qtdPadrao };
```

**Mudanças:**
- ✅ `categoriaConsumo`, `medidaPadraoQtd` vêm de `AlimentoCatalogo` (do DB)
- ✅ Nulo em categoria → fallback seguro (100g)
- ✅ Conhecido → usa `medida_padrao_qtd` + `unidade_medida_padrao`
- ✅ Sem busca de dicionário — lookup direto via objeto

**Linhas de código removidas:** ~15 linhas de lógica

---

### **Totais Removidos: ~137 linhas de hardcode**

| Item | Linhas | Status |
|---|---|---|
| PESO_TIPICO_GRAMAS dict | 82 | 🗑️ Removido |
| ALIMENTOS_LIQUIDOS set | 21 | 🗑️ Removido |
| TAMANHO_COPOS_ML dict | 13 | 🗑️ Removido |
| ehAlimentoLiquido() | 5 | 🗑️ Removido |
| estimarTamanhoRecipiente() | 7 | 🗑️ Removido |
| Lógica fallback antiga | 15 | 🔄 Refatorada |
| **TOTAL** | **~137** | ✅ Eliminado |

---

## ✅ O QUE FOI ADICIONADO

### **1. Migração SQL** (`20260802120000_categorias_alimentos_pesos_padrao.sql`)

**Colunas adicionadas a `alimentos_referencia`:**
```sql
ALTER TABLE alimentos_referencia ADD COLUMN
  categoria_consumo VARCHAR(50),           -- liquido_frio, liquido_quente, unidade, fatia, peso_livre
  unidade_medida_padrao VARCHAR(5),       -- 'g' ou 'ml'
  medida_padrao_nome VARCHAR(100),        -- "Copo Pequeno", "Unidade", "Fatia Média"
  medida_padrao_qtd NUMERIC(8, 2);        -- 5, 20, 250, etc.
```

**Índice para performance:**
```sql
CREATE INDEX idx_alimentos_referencia_categoria
  ON alimentos_referencia (categoria_consumo)
  WHERE categoria_consumo IS NOT NULL;
```

**SEEDs confirmados** (apenas certezas, ver CSV para pendentes):
- Arroz, Feijão, Bife, Ovo, Alface (pré-existentes no seed)
- Pão de queijo, Azeitona, Presunto, Queijo, Coxinha, Pastel
- Café, Chá, Suco, Refrigerante, Leite

---

### **2. CSV de Auditoria** (`TABELA_TACO_PESOS_PENDENTES_AUDITORIA.csv`)

**Propósito:** Fundador revisa alimentos órfãos sem categorização, preenche, e submete para migration

**Estrutura:**
```csv
id, nome_taco, aliases, ..., categoria_consumo_SUGERIDA, medida_padrao_qtd_SUGERIDA, REVISADO_POR_FUNDADOR, NOTAS
```

**Exemplo de preenchimento esperado:**
```
, "Maçã", "maça, maca", ..., "unidade", "180", "S", "Maçã média validada via TACO"
, "Vinho", "vinho", ..., "liquido_frio", "150", "S", "Taça padrão"
```

---

### **3. Edge Function Refatorada**

**Interface `AlimentoCatalogo` enriquecida:**
```typescript
export interface AlimentoCatalogo {
  // ... campos anteriores
  categoriaConsumo?: string;
  unidadeMedidaPadrao?: string;
  medidaPadraoNome?: string;
  medidaPadraoQtd?: number;
}
```

**Query enriquecida:**
```typescript
const { data, error } = await client
  .from('alimentos_referencia')
  .select(
    'id, nome_taco, aliases, calorias_kcal_100g, ..., ' +
    'categoria_consumo, unidade_medida_padrao, medida_padrao_nome, medida_padrao_qtd, ' +
    'alimentos_medidas_caseiras(medida, gramas)',
  );
```

**Mapeamento (parsing):**
```typescript
return ((data ?? []) as LinhaAlimentoBruta[]).map((linha) => ({
  // ... campos anteriores
  categoriaConsumo: linha.categoria_consumo ?? undefined,
  unidadeMedidaPadrao: linha.unidade_medida_padrao ?? undefined,
  medidaPadraoNome: linha.medida_padrao_nome ?? undefined,
  medidaPadraoQtd: linha.medida_padrao_qtd ? Number(linha.medida_padrao_qtd) : undefined,
  // ...
}));
```

---

### **4. Flutter Model Atualizado**

**`ItemPratoExtraidoModel` novos campos:**
```dart
final String? categoriaConsumo;
final String? unidadeMedidaPadrao;
final String? medidaPadraoNome;
final double? medidaPadraoQtd;
```

**Parsing tolerante:**
```dart
categoriaConsumo: json['categoria_consumo'] as String?,
unidadeMedidaPadrao: json['unidade_medida_padrao'] as String?,
medidaPadraoNome: json['medida_padrao_nome'] as String?,
medidaPadraoQtd: (json['medida_padrao_qtd'] as num?)?.toDouble(),
```

**Robustez:** Todos opcionais (`?`) — se backend não retornar (alimento em auditoria), Flutter não quebra.

---

## 🛡️ Graceful Degradation

### **Cenário 1: Alimento com categoria conhecida**
```
Backend retorna: categoria_consumo='unidade', medida_padrao_qtd=5
Flutter exibe: "(5g est.)" com indicador de estimado
Usuário clica Editar → dialog permite customização
```

### **Cenário 2: Alimento SEM categoria (em auditoria)**
```
Backend retorna: categoria_consumo=null, medida_padrao_qtd=null
Flutter fallback: "(100g est.)" com ⚠️ "Quantidade estimada"
Usuário clica Editar → input livre, recalcula macros em tempo real
```

### **Cenário 3: Banco de dados retorna erro**
```
Edge Function erro ao carregar catálogo
Flutter não quebra: mantém item visível com status "erro ao carregar categoria"
Usuário pode editar manualmente, salvar com confiança reduzida
```

---

## 📊 Antes vs. Depois

| Aspecto | Antes | Depois |
|---|---|---|
| **Fonte da Verdade** | 3 dicts em code + DB | 1 tabela no DB |
| **Ciclo de vida** | PR → CI/CD → deploy | CSV auditado → migration → deploy |
| **Auditoria** | git blame (rudimentar) | migration comment + CSV rastreado |
| **Alimentos novos** | Precisa de PR no código | Apenas UPDATE/INSERT no DB |
| **Robustez** | null/erro não tratado | Graceful fallback a 100g |
| **Categorias** | Inferidas por pattern-match | Explícitas no schema |
| **Reutilização** | Edge Function only | Edge Function + Flutter + CLI/admin |
| **Performance** | Lookup em dicts (O(1)) | Query DB + cache local (O(n) uma vez) |
| **Lógica duplicada?** | Não | Não (centralizada no DB) |

---

## 🔄 Wire Contract (Backend → Frontend)

**Novo JSON adicionado a `ItemPratoCalculado`:**
```json
{
  "nome": "Azeitona, preta",
  "nome_identificado": "Azeitona",
  "medida": "5g (est.)",
  "quantidade": 1,
  "gramas_estimados": 5,
  "calorias": 13.25,
  ...,
  // ⭐ NOVOS CAMPOS (opcionais, robustez):
  "categoria_consumo": "unidade",
  "unidade_medida_padrao": "g",
  "medida_padrao_nome": "Unidade",
  "medida_padrao_qtd": 5
}
```

Se backend não retornar (alimento ainda sem categoria), Flutter assume categoria=null e cai para input livre.

---

## 🚀 Deployment Checklist

### **Pré-requisitos:**
- [ ] Migração SQL aplicada: `supabase migration up`
- [ ] CSV `TABELA_TACO_PESOS_PENDENTES_AUDITORIA.csv` entregue ao fundador para auditoria
- [ ] Fundador preencheu CSV e aprovou

### **Deploy:**
- [ ] `supabase functions deploy extract-metric-photo`
- [ ] Verificar RLS no DB (SELECT deve passar para `authenticated`)
- [ ] Test: fotografar prato com azeitona → deve retornar categoria_consumo='unidade'
- [ ] Test: fotografar alimento órfão → deve retornar categoria_consumo=null
- [ ] Flutter rodar com novos campos → sem crash

### **Pós-deploy:**
- [ ] Monitorar logs da Edge Function por erros de query
- [ ] Se alimento novo chegar: fundador audita CSV, submete migration
- [ ] Retenção: CSV vira histórico de mudanças (git track)

---

## 📝 Notas Arquiteturais

### **Por que não usar VIEW + computed column?**
Uma VIEW no Supabase que calcula `categoria_consumo` dinamicamente funcionaria, mas:
- ❌ Seria READ ONLY no cliente (RLS bloqueia UPDATE mesmo via service role)
- ❌ Custo: view + join + trigger a cada query
- ✅ **Simples:** colunas diretas, sem lógica — fundador faz UPDATE direto

### **Por que CSV, não importador automático?**
- ❌ Importador automático (Excel → DB) é caixa-preta, erros silenciosos
- ✅ **Auditável:** CSV é texto, diff no git, revisão manual garantida
- ✅ **Reversível:** reverter = excluir linhas do CSV, re-run migration

### **Por que nullable, não DEFAULT?**
```sql
-- ❌ NÃO:
categoria_consumo VARCHAR(50) DEFAULT 'peso_livre'
-- Problema: não diferencia "auditor não revisou" de "deliberadamente peso_livre"

-- ✅ SIM:
categoria_consumo VARCHAR(50)
-- null = pendente de revisão, é explícito
```

---

## 🎓 Lessons Learned

1. **Dados ≠ Código** — catálogos nutricionais são dados, devem viver em DB, não em TypeScript
2. **Auditoria desde o início** — CSV de revisão é parte obrigatória do deployment, não pós-fato
3. **Graceful degradation saves lives** — null é melhor que crash; 100g é melhor que NaN
4. **Indices matter** — busca por categoria_consumo é O(n) sobre alimentos_referencia; index = sublinear
5. **Migration comments são DAO** — future-you vai querer saber por que 3 dicts foram movidos em 2026-08-02

---

## 📞 Contato / Próximas Ações

- **Fundador:** Revisar CSV, preencher pesos/categorias pendentes
- **Backend:** Monitorar logs da função após deploy
- **QA:** Testar cenários 1-3 acima (categoria conhecida, nula, erro DB)
- **Produto:** Alimentos órfãos agora têm UX clara (edição + macros em tempo real)

---

**FIM DO RELATÓRIO**

*Lixo removido: ~137 linhas | Robustez adicionada: ∞*
