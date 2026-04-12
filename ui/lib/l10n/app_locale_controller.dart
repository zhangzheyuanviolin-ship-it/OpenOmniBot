import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/l10n/app_language_mode.dart';
import 'package:ui/l10n/system_locale_controller.dart';
import 'package:ui/services/app_state_service.dart';
import 'package:ui/services/storage_service.dart';

final appLanguageModeProvider =
    StateNotifierProvider<AppLocaleController, AppLanguageMode>(
      (ref) => AppLocaleController(),
    );

final appResolvedLocaleProvider = Provider<ResolvedAppLocale>((ref) {
  final mode = ref.watch(appLanguageModeProvider);
  final systemLocale = ref.watch(systemLocaleProvider);
  return resolveAppLocale(mode: mode, systemLocale: systemLocale);
});

class AppLocaleController extends StateNotifier<AppLanguageMode> {
  AppLocaleController() : super(StorageService.getLanguageMode());

  Future<void> setLanguageMode(AppLanguageMode mode) async {
    if (state == mode) {
      return;
    }
    state = mode;
    await StorageService.setLanguageMode(mode);
    await AppStateService.applyLanguagePreference();
  }
}
