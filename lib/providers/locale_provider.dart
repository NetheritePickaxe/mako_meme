import 'package:flutter/material.dart';
import '../l10n/l10n.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('zh');
  L10n? _l10n;

  Locale get locale => _locale;
  L10n get l10n => _l10n ?? const L10n(languageCode: 'unknown', messages: {});

  Future<void> init() async {
    _l10n = await L10n.load('zh_cn');
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    final code = locale.countryCode != null ? '${locale.languageCode}_${locale.countryCode}' : locale.languageCode;
    _l10n = await L10n.load(code);
    notifyListeners();
  }
}
