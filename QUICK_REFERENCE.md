# 🚀 Quick Reference - ONDA 2

## 📋 Checklist Rápido

| Tarefa | Status | Arquivo |
|--------|--------|---------|
| Estrutura Clean Architecture | ✅ | `lib/core/` + `lib/features/` |
| i18n (PT, EN, ES) | ✅ | `assets/i18n/*.json` |
| Middleware de Perfil | ✅ | `lib/core/router/app_router.dart` |
| Modelos de Gamificação | ✅ | `lib/features/gamification/models/` |
| Supabase + SecureStorage | ✅ | `lib/core/supabase/supabase_client.dart` |
| Tema Duolingo/Strava | ✅ | `lib/core/theme/app_theme.dart` |
| Documentação | ✅ | `ARCHITECTURE.md` + `SETUP_GUIDE.md` |

---

## 🎯 Estrutura de Pastas (Resumida)

```
lib/
├── core/              → Compartilhado
│   ├── config/        → AppConfig
│   ├── i18n/          → I18nManager
│   ├── router/        → AppRouter + Middleware
│   ├── supabase/      → SupabaseClientManager
│   └── theme/         → AppTheme
├── features/          → Módulos isolados
│   ├── auth/          → Autenticação
│   ├── dashboard/     → Dashboard
│   └── gamification/  → Gamificação
├── constants/         → DemoData
└── main.dart         → Entry point

assets/
└── i18n/             → Tradições (JSON)
```

---

## 🔑 Imports Essenciais

```dart
// i18n (Tradução)
import 'package:atleta_gamificacao/core/i18n/i18n_manager.dart';
final text = i18n.tr('dashboard.welcome');

// Router
import 'package:atleta_gamificacao/core/router/app_router.dart';
context.go('/athlete-dashboard');

// Gamification Models
import 'package:atleta_gamificacao/features/gamification/models/gamification_models.dart';
final league = League(type: LeagueType.gold, ...);

// Auth Models
import 'package:atleta_gamificacao/features/auth/models/auth_models.dart';
final profile = UserProfile(...);

// Supabase
import 'package:atleta_gamificacao/core/supabase/supabase_client.dart';
await supabaseManager.signInAnonymously();

// Theme
import 'package:atleta_gamificacao/core/theme/app_theme.dart';
theme: getLightTheme(),

// Demo Data
import 'package:atleta_gamificacao/constants/demo_data.dart';
final state = DemoData.sampleGamificationState;
```

---

## 🎮 Usando Gamificação

### Criar Liga
```dart
final league = League(
  type: LeagueType.gold,
  currentPoints: 7850,
  pointsToNextLeague: 2150,
  joinedAt: DateTime.now().millisecondsSinceEpoch,
);
```

### Criar Streak
```dart
final streak = Streak(
  currentDays: 23,
  longestDays: 45,
  lastActivityDate: DateTime.now(),
);
print(streak.isMaintained()); // true se atividade < 24h
```

### Criar Desafio
```dart
final challenge = Challenge(
  id: 'run_5km',
  title: 'Treinar 5km',
  targetValue: 5000,
  currentValue: 3200,
  rewardPoints: 50,
  createdAt: DateTime.now(),
);
print(challenge.getProgress()); // 0.64 (64%)
```

### Cache Offline
```dart
import 'package:atleta_gamificacao/features/gamification/repositories/gamification_repository.dart';

// Salvar
await gamificationRepository.cacheLeague(league);

// Recuperar
final cachedLeague = await gamificationRepository.getCachedLeague();

// Verificar sync
final needsSync = await gamificationRepository.isSyncPending();
```

---

## 🌍 Usando i18n

### Tradução Simples
```dart
final welcome = i18n.tr('dashboard.welcome');
// "Bem-vindo, João"
```

### Com Parâmetros
```dart
final message = i18n.tr(
  'dashboard.welcome',
  params: {'username': 'João'},
);
// "Bem-vindo, João"

final text = i18n.tr(
  'gamification.streak_days',
  params: {'days': '23'},
);
// "23 dias de sequência"
```

### Trocar Idioma
```dart
await i18n.switchLanguage('en'); // English
await i18n.switchLanguage('pt'); // Português
await i18n.switchLanguage('es'); // Español
```

---

## 🔐 Usando Supabase + SecureStorage

### Autenticar Anonimamente
```dart
await supabaseManager.signInAnonymously();
```

### Armazenar Dados Seguros
```dart
await supabaseManager.storeSecurely('auth_token', token);
```

### Recuperar Dados Seguros
```dart
final token = await supabaseManager.retrieveSecurely('auth_token');
```

### Perfil do Usuário
```dart
final profile = await supabaseManager.getUserProfile(userId);
// {
//   "perfil_uso": "Atleta/Gamificação",
//   "display_name": "João",
//   "cep": "01310-100",
//   "is_paused": false
// }
```

---

## 🎨 Usando Temas

### Light Theme
```dart
MaterialApp(
  theme: getLightTheme(),
  home: MyScreen(),
)
```

### Dark Theme
```dart
MaterialApp(
  darkTheme: getDarkTheme(),
  themeMode: ThemeMode.dark,
  home: MyScreen(),
)
```

### Cores
```dart
import 'package:atleta_gamificacao/core/theme/app_theme.dart';

Container(
  color: AppColors.primaryGold,
  child: Text('Competitive', style: TextStyle(color: AppColors.darkText)),
)
```

---

## 🛣️ Navegação com GoRouter

### Navegar
```dart
context.go('/athlete-dashboard');
context.push('/leagues'); // Com back
```

### Rotas Disponíveis
- `/login` - Tela de login
- `/cep-validation` - Validação de CEP
- `/profile-selection` - Seleção de perfil
- `/athlete-dashboard` - Dashboard do atleta
- `/gamification` - Gamificação
- `/leagues` - Ligas
- `/rankings` - Rankings
- `/profile` - Perfil

### Middleware Automático
O router redireciona automaticamente baseado em `perfil_uso`:
- Atleta → rotas gamification permissão
- Guardião → `/clinical-dashboard`
- Médico → `/doctor-dashboard`

---

## 🧪 Usando Demo Data

```dart
import 'package:atleta_gamificacao/constants/demo_data.dart';

// User Profile
print(DemoData.sampleUserProfile.displayName); // João Silva

// Gamification State
final state = DemoData.sampleGamificationState;
print(state.currentStreak.currentDays); // 23

// Challenges
DemoData.sampleChallenges.forEach((challenge) {
  print('${challenge.title}: ${challenge.getProgress()}');
});

// Rankings
DemoData.sampleRankings.forEach((ranking) {
  print('${ranking.position}. ${ranking.displayName}');
});
```

---

## 📄 Configuração de Ambiente

### .env
```
SUPABASE_URL=https://seu-projeto.supabase.co
SUPABASE_ANON_KEY=sua-anon-key-aqui
DEBUG_MODE=false
```

### Variáveis de Compile Time
```bash
flutter run --dart-define=SUPABASE_URL=https://... --dart-define=SUPABASE_ANON_KEY=...
```

---

## 🚀 Comandos Úteis

```bash
# Instalar dependências
flutter pub get

# Code generation
flutter pub run build_runner build

# Rodar app
flutter run

# Rodar com release mode
flutter run --release

# Build APK
flutter build apk --release

# Build iOS
flutter build ios --release

# Limpar build
flutter clean

# Analisar código
flutter analyze
```

---

## 📊 Perfis Suportados

### Perfil 1: Atleta/Gamificação ✅ (ONDA 2)
- Rotas: `/athlete-dashboard`, `/gamification`, `/leagues`, `/rankings`
- Modelos: League, Streak, Ranking, Challenge

### Perfil 2: Guardião Clínico 🔜 (ONDA 3)
- Rotas: `/clinical-dashboard`, `/exam-folder`
- Bloqueados: gamification, leagues, rankings

### Perfil 3: Médico Especialista 🔜 (ONDA 4)
- Rotas: `/doctor-dashboard`
- Bloqueados: gamification, clinical

---

## 🔍 Debug

### Ver Todas as Traduções
```dart
final allTranslations = i18n.getAllTranslations();
print(jsonEncode(allTranslations));
```

### Ver Usuário Atual
```dart
final user = supabaseManager.currentUser;
print(user?.id);
print(user?.email);
```

### Ver Perfil Usuário
```dart
final profile = await supabaseManager.getUserProfile(userId);
print(profile?['perfil_uso']);
```

### Ver Idioma Atual
```dart
print('Idioma: ${i18n.currentLanguage}');
```

---

## 📚 Referências

- **ARCHITECTURE.md** - Documentação técnica completa
- **SETUP_GUIDE.md** - Instruções de setup
- **pubspec.yaml** - Todas as dependências comentadas
- **app_config.dart** - Constantes e feature flags

---

## ✨ Próximas Ondas

- **ONDA 3:** Implementar Perfil 2 (Guardião Clínico)
- **ONDA 4:** Implementar Perfil 3 (Médico Especialista)
- **ONDA 5:** Wearables + Real-time sync

---

**Versão:** 2.0.0 (ONDA 2)
**Atualizado:** 2026-07-06
**Autor:** Claude (Haiku 4.5)
