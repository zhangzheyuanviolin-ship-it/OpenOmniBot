import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ui/services/data_sync_service.dart';

class DataSyncStatusCenter {
  DataSyncStatusCenter._();

  static final DataSyncStatusCenter instance = DataSyncStatusCenter._();

  final ValueNotifier<DataSyncStatus> _notifier = ValueNotifier(
    const DataSyncStatus(),
  );

  Timer? _pollTimer;
  Duration? _pollInterval;
  bool _started = false;
  bool _refreshing = false;
  bool _manualSyncFeedbackActive = false;

  ValueListenable<DataSyncStatus> get listenable => _notifier;

  DataSyncStatus get currentStatus => _notifier.value;

  bool get hasPendingManualSyncFeedback => _manualSyncFeedbackActive;

  void armManualSyncFeedback() {
    _manualSyncFeedbackActive = true;
  }

  void clearManualSyncFeedback() {
    _manualSyncFeedbackActive = false;
  }

  void start() {
    if (_started) {
      unawaited(refresh());
      return;
    }
    _started = true;
    _reconfigurePolling(currentStatus);
    unawaited(refresh());
  }

  Future<DataSyncStatus> refresh() async {
    if (_refreshing) {
      return currentStatus;
    }
    _refreshing = true;
    try {
      final status = await DataSyncService.getStatus();
      _apply(status);
      return status;
    } catch (_) {
      return currentStatus;
    } finally {
      _refreshing = false;
    }
  }

  void observeStatus(DataSyncStatus status) {
    _apply(status);
  }

  void stop({bool clearState = false}) {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pollInterval = null;
    _started = false;
    _refreshing = false;
    if (clearState) {
      _manualSyncFeedbackActive = false;
      _notifier.value = const DataSyncStatus();
    }
  }

  @visibleForTesting
  void reset() {
    stop(clearState: true);
  }

  void _apply(DataSyncStatus status) {
    _notifier.value = status;
    _reconfigurePolling(status);
  }

  void _reconfigurePolling(DataSyncStatus status) {
    final nextInterval = _pollIntervalFor(status);
    if (_pollInterval == nextInterval && _pollTimer != null) {
      return;
    }
    _pollTimer?.cancel();
    _pollInterval = nextInterval;
    _pollTimer = Timer.periodic(nextInterval, (_) {
      unawaited(refresh());
    });
  }

  Duration _pollIntervalFor(DataSyncStatus status) {
    if (status.isSyncing) {
      return const Duration(seconds: 2);
    }
    if (status.enabled) {
      return const Duration(seconds: 15);
    }
    return const Duration(seconds: 30);
  }
}
