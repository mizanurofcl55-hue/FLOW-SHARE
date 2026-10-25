import 'dart:convert';
import 'package:flutter/services.dart';

class AppStrings {
  static final Map<String, Map<String, String>> _all = {};
  static Future<void> load() async {
    for (final language in ['en', 'bn']) {
      _all[language] = Map<String, String>.from(
        jsonDecode(await rootBundle.loadString('assets/i18n/$language.json'))
            as Map,
      );
    }
  }

  static String text(String language, String key) =>
      _all[language]?[key] ?? _all['en']?[key] ?? key;
}
