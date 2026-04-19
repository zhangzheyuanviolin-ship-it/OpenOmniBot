import 'package:flutter/material.dart';
import 'package:ui/l10n/legacy_text_localizer.dart';
import 'package:ui/services/data_sync_service.dart';
import 'package:ui/services/data_sync_status_center.dart';
import 'package:ui/utils/ui.dart';

class DataSyncProgressToastListener extends StatefulWidget {
  const DataSyncProgressToastListener({super.key});

  @override
  State<DataSyncProgressToastListener> createState() =>
      _DataSyncProgressToastListenerState();
}

class _DataSyncProgressToastListenerState
    extends State<DataSyncProgressToastListener>
    with WidgetsBindingObserver {
  late final DataSyncStatusCenter _statusCenter;
  DataSyncStatus _lastHandledStatus = const DataSyncStatus();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusCenter = DataSyncStatusCenter.instance;
    _statusCenter.start();
    _statusCenter.listenable.addListener(_handleStatusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _applyStatus(_statusCenter.currentStatus);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusCenter.listenable.removeListener(_handleStatusChanged);
    _statusCenter.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _statusCenter.refresh();
    }
  }

  void _handleStatusChanged() {
    if (!mounted) {
      return;
    }
    final status = _statusCenter.currentStatus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _applyStatus(status);
    });
  }

  void _applyStatus(DataSyncStatus status) {
    final previousStatus = _lastHandledStatus;
    _lastHandledStatus = status;

    if (status.isSyncing) {
      hideProgressToast();
      if (!previousStatus.isSyncing) {
        showToast(_t('已开始同步', 'Sync started'), type: ToastType.info);
      }
      return;
    }

    hideProgressToast();
    if (!previousStatus.isSyncing) {
      return;
    }

    if (status.state == 'success') {
      showToast(_t('同步完成', 'Sync completed'), type: ToastType.success);
      return;
    }
    if (status.state == 'error') {
      showToast(
        status.lastError.isNotEmpty
            ? status.lastError
            : _t('同步失败', 'Sync failed'),
        type: ToastType.error,
      );
    }
  }

  String _t(String zh, String en) {
    return LegacyTextLocalizer.isEnglish ? en : zh;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
