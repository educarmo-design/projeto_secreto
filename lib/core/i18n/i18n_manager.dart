import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class I18nManager {
  static final I18nManager _instance = I18nManager._internal();

  factory I18nManager() {
    return _instance;
  }

  I18nManager._internal();

  late Map<String, dynamic> _translations = {};
  String _currentLanguage = 'pt';

  /// Supported languages
  static const List<String> supportedLanguages = ['pt', 'en', 'es'];

  /// Initialize translations for a specific language
  Future<void> initialize(String language) async {
    _currentLanguage = language;
    await _loadTranslations(language);
  }

  /// Load translation file from assets
  Future<void> _loadTranslations(String language) async {
    try {
      final jsonString = await rootBundle.loadString('assets/i18n/$language.json');
      _translations = json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error loading translations for $language: $e');
      // Fallback to Portuguese
      if (language != 'pt') {
        await _loadTranslations('pt');
      }
    }
  }

  /// Switch language at runtime
  Future<void> switchLanguage(String language) async {
    if (supportedLanguages.contains(language)) {
      await initialize(language);
    }
  }

  /// Get translation value by key (supports nested keys like "dashboard.title")
  String translate(String key, {Map<String, String>? params}) {
    List<String> keys = key.split('.');
    dynamic value = _translations;

    for (String k in keys) {
      if (value is Map) {
        value = value[k];
      } else {
        return key; // Return key if not found
      }
    }

    if (value is String) {
      // Replace placeholders with provided params
      if (params != null) {
        params.forEach((paramKey, paramValue) {
          value = value.replaceAll('{{$paramKey}}', paramValue);
        });
      }
      return value;
    }

    return key; // Return key if value is not a string
  }

  /// Shorthand: tr() for translate()
  String tr(String key, {Map<String, String>? params}) {
    return translate(key, params: params);
  }

  /// Get current language
  String get currentLanguage => _currentLanguage;

  /// Get all translations (for debugging)
  Map<String, dynamic> getAllTranslations() => _translations;
}

// Singleton instance
final i18n = I18nManager();
