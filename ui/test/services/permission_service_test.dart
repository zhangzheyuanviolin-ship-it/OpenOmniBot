import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/features/home/pages/authorize/authorize_page_args.dart';
import 'package:ui/l10n/legacy_text_localizer.dart';
import 'package:ui/services/permission_service.dart';

void main() {
  tearDown(LegacyTextLocalizer.clearResolvedLocale);

  test('rebuilds special permission labels from current locale', () {
    LegacyTextLocalizer.setResolvedLocale(const Locale('zh'));
    final zhPermission = PermissionService.buildDisplayPermissionsForIds(const [
      kWorkspaceStoragePermissionId,
    ]).single;
    expect(zhPermission.name, '内置 workspace');

    LegacyTextLocalizer.setResolvedLocale(const Locale('en'));
    final enPermission = PermissionService.buildDisplayPermissionsForIds(const [
      kWorkspaceStoragePermissionId,
    ]).single;
    expect(enPermission.name, 'Built-in workspace');
  });
}
