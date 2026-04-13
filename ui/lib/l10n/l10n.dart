import 'package:flutter/material.dart';
import 'package:ui/l10n/generated/app_localizations.dart';
import 'package:ui/l10n/legacy_text_localizer.dart';

extension AppL10nBuildContextX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;

  String trLegacy(String text) {
    return LegacyTextLocalizer.localize(text, locale: Localizations.localeOf(this));
  }
}
