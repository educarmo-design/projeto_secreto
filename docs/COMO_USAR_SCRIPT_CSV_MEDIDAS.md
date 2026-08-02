# 📋 Como Usar: Script de Geração de CSV de Medidas Pendentes

**Script:** `scripts/gerar_csv_medidas_pendentes.ts`  
**Linguagem:** TypeScript (Deno)  
**Propósito:** Consultar banco de dados e gerar arquivo CSV com alimentos pendentes de categorização

---

## 🚀 Modo Rápido (Copy-Paste)

```bash
# 1. Defina variáveis de ambiente (uma vez)
export SUPABASE_URL="https://seu-projeto.supabase.co"
export SUPABASE_ANON_KEY="eyJhbGc..."

# 2. Rode o script
cd /caminho/para/projeto_secreto
deno run --allow-all scripts/gerar_csv_medidas_pendentes.ts

# 3. Abra o arquivo gerado
# → docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA_GERADA_2026-08-02T14-35-22.csv
```

---

## 📖 Modo Detalhado

### **Pré-requisitos**

1. **Deno instalado:**
   ```bash
   deno --version
   # Expected: deno X.X.X
   ```

2. **Supabase CLI (opcional, para pegar as chaves):**
   ```bash
   supabase projects list  # Listar projetos conectados
   ```

3. **Variáveis de ambiente definidas:**
   - `SUPABASE_URL`: URL do seu projeto Supabase (ex: `https://meu-projeto.supabase.co`)
   - `SUPABASE_ANON_KEY`: Chave anônima do Supabase (segura para cliente)

---

### **Como Obter as Variáveis de Ambiente**

#### **Opção A: Via Supabase Dashboard**

1. Ir para https://supabase.com/dashboard
2. Selecionar o projeto
3. Settings → API → copiar:
   - `Project URL` (SUPABASE_URL)
   - `anon` key (SUPABASE_ANON_KEY)

#### **Opção B: Via Supabase CLI**

```bash
supabase projects list --json | jq '.[] | {name, id, api_url}'
```

---

### **Passos Completos**

#### **1. Terminal 1: Iniciar Supabase Local (opcional, se desenvolvendo localmente)**

```bash
cd projeto_secreto
supabase start

# Resultado:
# API_URL: http://127.0.0.1:54321
# ANON_KEY: eyJhbGc...
```

#### **2. Definir Variáveis de Ambiente**

**No Linux/Mac:**
```bash
export SUPABASE_URL="http://127.0.0.1:54321"
export SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

**No Windows (PowerShell):**
```powershell
$env:SUPABASE_URL = "http://127.0.0.1:54321"
$env:SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

**No Windows (cmd.exe):**
```cmd
set SUPABASE_URL=http://127.0.0.1:54321
set SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### **3. Rodar o Script**

```bash
deno run --allow-all scripts/gerar_csv_medidas_pendentes.ts
```

**Saída Esperada:**
```
📊 Consultando alimentos_referencia...
✅ Encontrados 16 alimentos categorizados
⏳ Encontrados 5 alimentos PENDENTES de categorização

✅ CSV gerado com sucesso!
📄 Arquivo: docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA_GERADA_2026-08-02T14-35-22.csv

📊 Resumo:
   - Total de alimentos: 21
   - Categorizados: 16 ✅
   - Pendentes: 5 ⏳

📋 Próximos passos:
   1. Abrir docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA_GERADA_2026-08-02T14-35-22.csv em Excel
   2. Preencher coluna "categoria_consumo_CONFIRMADA" para cada alimento pendente
   ...
```

#### **4. Abrir CSV e Preencher**

```bash
# Linux/Mac
open docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA_GERADA_*.csv

# Windows
explorer docs\TABELA_TACO_PESOS_PENDENTES_AUDITORIA_GERADA_*.csv

# Google Sheets
# → Clique em "File" → "Open with" → "Google Sheets"
```

---

## 📝 Como Preencher o CSV

### **Estrutura do Arquivo**

```csv
id,nome_taco,aliases,fonte,categoria_consumo_CONFIRMADA,unidade_medida_CONFIRMADA,medida_padrao_nome_CONFIRMADA,medida_padrao_qtd_CONFIRMADA,calorias_100g,...,REVISADO_POR_FUNDADOR,DATA_REVISAO,NOTAS
```

### **Seções**

1. **INSTRUÇÕES** (primeiras 5 linhas, read-only)
2. **REFERÊNCIA** (alimentos já categorizados, não editar)
3. **PENDENTES** (alimentos a categorizar, editar aqui!)

### **Exemplo: Categorizar uma Maçã**

**Antes:**
```csv
"abc-123","Maçã, vermelha, crua","maça, maca, maçã vermelha","taco","","","","",52,0.3,13.8,0.2,"N","","Auditar: preencher categoria_consumo"
```

**Depois:**
```csv
"abc-123","Maçã, vermelha, crua","maça, maca, maçã vermelha","taco","unidade","g","Unidade","180",52,0.3,13.8,0.2,"S","2026-08-02","Validado na TACO — maçã média ~180g"
```

### **Regras de Preenchimento**

| Campo | Valores Esperados | Exemplo |
|---|---|---|
| `categoria_consumo_CONFIRMADA` | `unidade`, `fatia`, `peso_livre`, `liquido_frio`, `liquido_quente` | `unidade` |
| `unidade_medida_CONFIRMADA` | `g` ou `ml` | `g` para sólidos, `ml` para líquidos |
| `medida_padrao_nome_CONFIRMADA` | Rótulo amigável | `Unidade`, `Fatia`, `Copo Pequeno`, `Xícara` |
| `medida_padrao_qtd_CONFIRMADA` | Número em g (sólidos) ou ml (líquidos) | `180` para maçã, `250` para suco |
| `REVISADO_POR_FUNDADOR` | `S` ou `N` | `S` quando validado |
| `DATA_REVISAO` | YYYY-MM-DD | `2026-08-02` |
| `NOTAS` | Observações livres | `Validado na TACO` |

### **Exemplos Prontos**

```csv
# Fruta (unidade)
"id","Maçã, vermelha, crua","maça","taco","unidade","g","Unidade","180",52,0.3,13.8,0.2,"S","2026-08-02","TACO 4ª ed., maçã média"

# Carne (peso_livre, sem medida padrão)
"id","Filé de peixe, fresco","peixe","taco","peso_livre","g","Porção média","150",96,20,0,1.2,"S","2026-08-02","Fresco, cru"

# Sopa (líquido frio é raro, mas possível)
"id","Sopa de legumes","sopa","taco","liquido_frio","ml","Tigela média","300",45,2,8,1.5,"S","2026-08-02","Sopa pronta, caldo leve"

# Achocolatado (líquido frio)
"id","Achocolatado em pó","achocolate","taco","liquido_frio","ml","Copo com leite","250",150,4,30,4,"S","2026-08-02","Preparado com leite integral"
```

---

## 🔄 Workflow Completo (Do Script ao Banco)

```
1. Rodar script:
   $ deno run --allow-all scripts/gerar_csv_medidas_pendentes.ts
   ↓
2. Abrir CSV em Excel/Sheets
   ↓
3. Preencher linhas PENDENTES:
   - categoria_consumo_CONFIRMADA
   - medida_padrao_qtd_CONFIRMADA
   - Marcar REVISADO_POR_FUNDADOR='S'
   ↓
4. Salvar CSV como texto
   ↓
5. Criar nova migração baseada nas linhas preenchidas:
   $ supabase migration new add_alimentos_auditorios_[data]
   ↓
6. Escrever migration com UPDATEs dos alimentos confirmados
   ↓
7. Testar localmente:
   $ supabase migration up
   ↓
8. Fazer PR + merge
   ↓
9. Deploy em produção
   ↓
10. App automáticamente renderiza novas categorias! 🎉
```

---

## 🐛 Troubleshooting

### **Erro: `SUPABASE_URL ou SUPABASE_ANON_KEY não definidos`**

```bash
# Solução 1: Definir variáveis
export SUPABASE_URL="..."
export SUPABASE_ANON_KEY="..."

# Solução 2: Verificar se foram definidas
echo $SUPABASE_URL
echo $SUPABASE_ANON_KEY
```

### **Erro: `failed to connect to postgres`**

```bash
# Verificar se Supabase está rodando
supabase status

# Se não, iniciar:
supabase start

# Se estiver usando produção, verificar conexão de internet
```

### **Erro: `Permission Denied` ao escrever arquivo**

```bash
# Verificar permissões do diretório
ls -la docs/

# Dar permissão:
chmod 755 docs/
```

### **O CSV não tem dados de "Pendentes"**

✅ **Isso é SUCESSO!** Significa que todos os alimentos já estão categorizados. Parabéns!

---

## 📊 Interpretando a Saída

### **Resumo Esperado**

```
Total de alimentos: 21
Categorizados: 16 ✅
Pendentes: 5 ⏳
```

- **16 categorizados**: Alimentos que já passaram por auditoria
- **5 pendentes**: Alimentos que precisa de revisão

---

## 🔗 Referências

- **Supabase:** https://supabase.io/docs/reference/javascript/createclient
- **Deno:** https://deno.land/manual/getting_started/installation
- **TACO (Tabela Brasileira):** http://www.unicamp.br/nepa/taco/

---

## ✅ Checklist Pós-Execução

- [ ] Script rodou sem erros
- [ ] CSV foi gerado em `docs/TABELA_TACO_PESOS_PENDENTES_AUDITORIA_GERADA_*.csv`
- [ ] Abri o CSV em Excel/Sheets
- [ ] Verifiquei seção "REFERÊNCIA" (alimentos categorizados)
- [ ] Verifiquei seção "PENDENTES" (alimentos a categorizar)
- [ ] Preenchi todos os "PENDENTES" com dados válidos
- [ ] Marcei REVISADO_POR_FUNDADOR='S' para cada linha
- [ ] Salvei o CSV
- [ ] Passei para próxima fase (criar migration baseada no CSV)

---

**Dúvidas?** Consulte `docs/RELATORIO_TECNICO_REFACTORING_PESOS_ALIMENTOS.md` para arquitetura completa.
