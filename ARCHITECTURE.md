# Atleta+ | Arquitetura ONDA 2 (Aplicativo 1 - Gamificação)

## 📋 Overview

Aplicativo Flutter construído com **Clean Architecture** e padrão **Feature-First**, preparado para suportar múltiplos perfis de uso (Perfil 1: Atleta/Gamificação, Perfil 2: Guardião Clínico, Perfil 3: Médico Especialista).

**Stack Tecnológico:**
- **Framework:** Flutter 3.x+ com Dart 3.0+
- **Backend:** Supabase (PostgreSQL + Auth)
- **State Management:** Riverpod + Equatable
- **Routing:** GoRouter com Middleware de Perfil
- **Storage:** Flutter Secure Storage + Local Cache
- **Localization:** Intl + JSON files (pt, en, es)

---

## 🏗️ Estrutura de Diretórios (Clean Architecture)

```
lib/
├── main.dart                          # Entry point da aplicação
│
├── core/                              # Lógica compartilhada
│   ├── config/
│   │   └── app_config.dart           # Constantes e configurações globais
│   ├── i18n/
│   │   └── i18n_manager.dart         # Gerenciador de tradução (nativo, sem deps)
│   ├── router/
│   │   └── app_router.dart           # GoRouter + Middleware sensível ao perfil
│   ├── supabase/
│   │   └── supabase_client.dart      # Cliente Supabase + Secure Storage
│   └── theme/
│       └── app_theme.dart            # Temas Duolingo/Strava style
│
├── features/                          # Feature-First (isoladas)
│   ├── auth/
│   │   ├── models/
│   │   │   └── auth_models.dart      # AuthState, CepValidation, UserProfile
│   │   ├── repositories/
│   │   ├── services/
│   │   └── screens/
│   │
│   ├── dashboard/
│   │   ├── models/
│   │   ├── repositories/
│   │   ├── widgets/
│   │   └── screens/
│   │
│   └── gamification/
│       ├── models/
│       │   └── gamification_models.dart # League, Streak, Ranking, Challenge
│       ├── repositories/
│       │   └── gamification_repository.dart # Offline caching + sync
│       ├── services/
│       ├── widgets/
│       └── screens/
│
└── constants/                         # Constantes literais da app

assets/
├── i18n/
│   ├── pt.json                        # Português (Brasil)
│   ├── en.json                        # English
│   └── es.json                        # Español
└── images/                            # (opcional) SVG/PNG assets

supabase/
├── migrations/
│   └── 20260706191827_core_schema.sql # Schema isolado com anonymous_users JSONB
└── config.toml                        # Configuração local Supabase

pubspec.yaml                           # Dependências Flutter
```

---

## 🔐 Padrões Implementados

### 1. **Clean Architecture**
- **core/** → Código reutilizável (não depende de features)
- **features/** → Módulos isolados (cada um é um mini-app)
- **Camadas:** Presentation (Screens/Widgets) → Services/Repositories → Models

### 2. **Feature-First Organization**
Cada feature é autossuficiente e podem ser desenvolvidas em paralelo:
```
gamification/
├── models/          # Entities (Liga, Streak, Ranking)
├── repositories/    # Data access (local/remote)
├── services/        # Business logic (cálculos)
├── widgets/         # UI components reutilizáveis
└── screens/         # Full page UI
```

### 3. **Middleware Sensível ao Perfil (GoRouter)**
```dart
// Fluxo de redirecionamento automático:
1. Sem autenticação → /login
2. Autenticado sem perfil → /profile-selection
3. Perfil Atleta → rotas gamificação visíveis
4. Perfil Guardião → redireciona para /clinical-dashboard (gamificação pausada)
5. Perfil Médico → redireciona para /doctor-dashboard
```

### 4. **Offline-First with Secure Storage**
- Dados críticos armazenados em **FlutterSecureStorage** (Keychain/Android Keystore)
- Cache local em RAM/SQLite para gamificação
- Sync flag para reconciliação pós-reconexão
- Zero cloud storage (Pipeline volátil)

### 5. **Internacionalização Nativa**
- JSON files (sem dependência de pagas)
- Suporte a 3 idiomas: PT, EN, ES
- Placeholder substitution: `{{username}}` → dinâmico

---

## 🔄 Fluxo de Autenticação & Perfil

```
1. Anonymous Sign-in (Supabase)
   ↓
2. CEP Validation (região/estado)
   ↓
3. Profile Selection (Atleta/Guardião/Médico)
   ↓
4. Armazenar em anonymous_users.profile_data (JSONB)
   {
     "perfil_uso": "Atleta/Gamificação",
     "display_name": "João Silva",
     "cep": "01310-100",
     "is_paused": false
   }
   ↓
5. Middleware valida perfil_uso → redireciona UI
```

---

## 🎮 Modelo de Gamificação

### **Estrutura de Dados**

```dart
// League (Ligas competitivas)
League {
  type: bronze → silver → gold → platinum → diamond
  currentPoints: int
  pointsToNextLeague: int
}

// Streak (🔥 chama - sequência)
Streak {
  currentDays: 7
  longestDays: 30
  lastActivityDate: DateTime
  bonusPoints: earned every 7 days
}

// Ranking (Posição no ranking)
Ranking {
  position: 42
  totalPlayers: 1000
  points: 5230
  currentLeague: gold
}

// Challenge (Desafios diários)
Challenge {
  id: "challenge_001"
  title: "Treinar 5km"
  targetValue: 5000 (meters)
  currentValue: 3200
  rewardPoints: 50
  isCompleted: false
}
```

### **Caching Offline**

Todos os dados são armazenados localmente em Secure Storage com sync pendente:

```dart
// gamification_repository.dart
- getCachedLeague() → Recover from SecureStorage
- cachLeague(league) → Persist offline
- isSyncPending() → Check sync flag
- clearCache() → Manual purge
```

---

## 📱 Profiles (Preparado para Futuros)

### **Perfil 1: Atleta/Gamificação** ✅ (ONDA 2)
- Dashboard com stats
- Ligas (Bronze → Diamond)
- Streak (🔥) com bonus
- Rankings competitivos
- Desafios diários
- **Rotas:**
  - `/athlete-dashboard`
  - `/gamification`
  - `/leagues`
  - `/rankings`

### **Perfil 2: Guardião Clínico** 📋 (Prep)
- **Rotas escondidas:** gamification, leagues, rankings
- **Redirecionar para:** `/clinical-dashboard`
- **UI:** Pasta Digital de Exames
- **Gamificação:** Pausada (sem punição)
- **Model:** ClinicalGuardian + ExamFolder

### **Perfil 3: Médico Especialista** 🏥 (Prep)
- **Rotas escondidas:** gamification, clinical
- **Redirecionar para:** `/doctor-dashboard`
- **UI:** Analytics médicos + Prescrições
- **Model:** DoctorSpecialist + PatientManagement

---

## 🔧 Como Rodá-lo

### **Pré-requisitos**
```bash
flutter --version   # 3.13.0+
dart --version      # 3.0.0+
```

### **Setup Inicial**
```bash
# 1. Dependências
flutter pub get

# 2. Copiar .env
cp .env.example .env

# 3. Configurar Supabase URL/Key em .env
# (Obter de supabase/config.toml ou dashboard Supabase)

# 4. Code generation (json_serializable, freezed)
flutter pub run build_runner build

# 5. Rodar
flutter run
```

### **Build Production**
```bash
# iOS
flutter build ios --release

# Android
flutter build apk --release
flutter build appbundle --release
```

---

## 📊 Dependências Principais

```yaml
# Supabase
supabase_flutter: ^2.0.0
supabase: ^2.0.0

# Secure Storage
flutter_secure_storage: ^9.0.0

# Routing
go_router: ^12.0.0

# State Management
riverpod_flutter: ^2.0.0
riverpod: ^2.0.0

# Localization (nativa, sem Firebase/Crowdin)
intl: ^0.19.0

# JSON & Code Gen
json_annotation: ^4.8.0
json_serializable: ^6.7.0
freezed: ^2.4.0
build_runner: ^2.4.0

# Utilities
uuid: ^4.0.0
equatable: ^2.0.5
```

---

## 🛡️ Segurança & Best Practices

### **Implementado:**
- ✅ Null-safety 100%
- ✅ Secure Storage para tokens
- ✅ Anonymous auth (sem emails expostos)
- ✅ Profile-aware routing (sem acesso cruzado)
- ✅ Offline-first com sync reconciliation
- ✅ JSONB na Supabase (dados estruturados)

### **Próximos Passos (Validação):**
- [ ] Test coverage (unit + widget tests)
- [ ] Error handling robusto (exceções customizadas)
- [ ] Analytics de gamificação
- [ ] Rate limiting para APIs

---

## 🎨 Temas

**Inspiration:** Duolingo + Strava

- **Primária:** Gold (`#FFB700`) - Competitive
- **Secundária:** Blue (`#457B9D`) - Trust
- **Accent:** Green (`#06D6A0`) - Success

**Modo Escuro + Claro** implementado em `app_theme.dart`

---

## 📝 Notas

1. **i18n:** Usando JSON nativo (zero deps externas)
2. **Offline:** Tudo em RAM/SecureStorage (zero cloud)
3. **Middleware:** GoRouter redirect automático por perfil
4. **Modelos:** Imutáveis com Equatable (igualdade por valor)
5. **Sync:** Flag `requiresSync` marca dados não sincronizados

---

## 🚀 Próximas Ondas

- **ONDA 3:** Implementar Perfil 2 (Guardião Clínico) + Pasta Digital
- **ONDA 4:** Implementar Perfil 3 (Médico Especialista) + Analytics
- **ONDA 5:** Wearables integration + Real-time sync
