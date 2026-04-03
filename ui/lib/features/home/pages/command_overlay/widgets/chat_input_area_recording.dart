part of 'chat_input_area.dart';

mixin _ChatInputAreaRecordingMixin on _ChatInputAreaStateBase {
  // ==================== 录音相关方法 ====================

  String _mergeTranscriptText(String current, String incoming) {
    final left = current.trimRight();
    final right = incoming.trimLeft();
    if (left.isEmpty) {
      return right;
    }
    if (right.isEmpty) {
      return left;
    }
    if (left == right) {
      return left;
    }
    if (right.startsWith(left)) {
      return right;
    }
    if (left.startsWith(right)) {
      return left;
    }

    final overlap = _longestTranscriptOverlap(left, right);
    final separator = overlap > 0 ? '' : _transcriptSeparator(left, right);
    return '$left$separator${right.substring(overlap)}';
  }

  int _longestTranscriptOverlap(String left, String right) {
    final maxLength = math.min(left.length, right.length);
    for (var size = maxLength; size > 0; size--) {
      if (left.substring(left.length - size) == right.substring(0, size)) {
        return size;
      }
    }
    return 0;
  }

  String _transcriptSeparator(String left, String right) {
    if (left.isEmpty || right.isEmpty) {
      return '';
    }
    final leftLast = left[left.length - 1];
    final rightFirst = right[0];
    if (RegExp(r'\s').hasMatch(leftLast) ||
        RegExp(r'\s').hasMatch(rightFirst)) {
      return '';
    }
    if (_isAsciiWordChar(leftLast) && _isAsciiWordChar(rightFirst)) {
      return ' ';
    }
    if (_isCjkChar(leftLast) || _isCjkChar(rightFirst)) {
      return '';
    }
    return ' ';
  }

  bool _isAsciiWordChar(String value) {
    return RegExp(r'[A-Za-z0-9]').hasMatch(value);
  }

  bool _isCjkChar(String value) {
    if (value.isEmpty) {
      return false;
    }
    final codePoint = value.runes.first;
    return (codePoint >= 0x3400 && codePoint <= 0x4DBF) ||
        (codePoint >= 0x4E00 && codePoint <= 0x9FFF) ||
        (codePoint >= 0xF900 && codePoint <= 0xFAFF);
  }

  String _composeRecognizedText(String transcript) {
    if (_textBeforeRecording.isEmpty) {
      return transcript;
    }
    if (transcript.isEmpty) {
      return _textBeforeRecording;
    }
    final needsSpace =
        !RegExp(r'\s$').hasMatch(_textBeforeRecording) &&
        !RegExp(r'^\s').hasMatch(transcript) &&
        !_isCjkChar(_textBeforeRecording[_textBeforeRecording.length - 1]) &&
        !_isCjkChar(transcript[0]);
    return needsSpace
        ? '$_textBeforeRecording $transcript'
        : '$_textBeforeRecording$transcript';
  }

  /// 切换录音状态（开始/停止）
  Future<void> toggleRecording() async {
    final shouldStop = _recordingState != RecordingState.idle;

    // Flutter 侧互斥：同一时刻只允许一个 start/stop 逻辑在跑
    if (_toggleInProgress) {
      if (shouldStop && _recordingState == RecordingState.starting) {
        _setRecordingState(RecordingState.stopping);
        return;
      }
      if (!shouldStop) {
        _showFastTapToast();
      }
      return;
    }

    if (!shouldStop) {
      // Flutter 侧时间窗口限流：频繁点击不下发到原生
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastToggleAcceptedAtMs < _toggleMinIntervalMs) {
        _showFastTapToast();
        return;
      }
      _lastToggleAcceptedAtMs = now;
    }

    _toggleInProgress = true;
    try {
      widget.focusNode.unfocus();

      if (shouldStop) {
        await _stopRecording();
        return;
      }

      await _startRecording();
    } finally {
      _toggleInProgress = false;
    }
  }

  void _showFastTapToast() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastFastTapToastAtMs < _fastTapToastMinIntervalMs) return;
    _lastFastTapToastAtMs = now;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('请不要点击太快'),
        duration: Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 开始录音
  Future<void> _startRecording() async {
    _setRecordingState(RecordingState.starting);

    try {
      var status = await Permission.microphone.status;

      if (!status.isGranted) {
        await requestPermission(['android.permission.RECORD_AUDIO']);
        _setRecordingState(RecordingState.idle);
        return;
      }

      // 开始录音
      final bool started = await AsrSpeechRecognitionService.startRecording()
          .timeout(_startTimeout, onTimeout: () => false);
      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('暂未实现，请耐心等待')));
        }
        _setRecordingState(RecordingState.idle);
        return;
      }

      await _transcriptionSubscription?.cancel();
      _streamDoneCompleter = Completer<void>();

      // 保存录音开始前的文本，用于追加模式
      _textBeforeRecording = widget.controller.text;
      _currentTranscript = '';

      _transcriptionSubscription = speechRecognitionEvents
          .receiveBroadcastStream()
          .listen(
            (transcript) {
              final transcriptText = transcript.toString().trim();
              debugPrint(
                "[SpeechRecognition] Received transcript: $transcriptText",
              );
              if (mounted &&
                  transcriptText.isNotEmpty &&
                  (_recordingState == RecordingState.recording ||
                      _recordingState == RecordingState.stopping ||
                      _recordingState == RecordingState.waitingServerStop)) {
                // 本地 ASR 回调的是每一段 endpoint 的最终文本；这里做跨段聚合，
                // 同时兼容后续可能返回累计文本的 provider。
                _currentTranscript = _mergeTranscriptText(
                  _currentTranscript,
                  transcriptText,
                );
                widget.controller.text = _composeRecognizedText(
                  _currentTranscript,
                );
                // 移动光标到末尾
                widget.controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: widget.controller.text.length),
                );
                // 滚动到末尾
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_textFieldScrollController.hasClients) {
                    _textFieldScrollController.jumpTo(
                      _textFieldScrollController.position.maxScrollExtent,
                    );
                  }
                });
              }
            },
            onError: (error) {
              debugPrint(
                "[SpeechRecognition] Transcription stream error: $error",
              );
              final isServerInitiatedStop =
                  error is PlatformException && error.code == 'ASR_FINAL';
              _completeStreamDone();
              _handleTranscriptionEnded(
                error: error,
                isServerInitiatedStop: isServerInitiatedStop,
              );
            },
            onDone: () {
              debugPrint("[SpeechRecognition] Transcription stream done");
              _completeStreamDone();
              _handleTranscriptionEnded();
            },
          );

      if (_recordingState != RecordingState.starting) {
        await AsrSpeechRecognitionService.stopSendingOnly().timeout(
          _stopTimeout,
          onTimeout: () => null,
        );
        return;
      }

      _setRecordingState(RecordingState.recording);
    } on PlatformException catch (e) {
      debugPrint("Failed to start recording: '${e.message}'.");
      _setRecordingState(RecordingState.idle);
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('启动录音超时')));
      }
      _setRecordingState(RecordingState.idle);
    }
  }

  /// 停止录音
  Future<void> _stopRecording() async {
    if (_recordingState != RecordingState.recording &&
        _recordingState != RecordingState.starting &&
        _recordingState != RecordingState.waitingServerStop) {
      return;
    }

    if (_recordingState != RecordingState.waitingServerStop) {
      // 先渲染“停止中”UI，再执行 stop 逻辑，避免体感卡顿
      _setRecordingState(RecordingState.stopping);
      await Future<void>.delayed(Duration.zero);

      try {
        await AsrSpeechRecognitionService.stopSendingOnly().timeout(
          _stopTimeout,
          onTimeout: () => null,
        );
        if (_recordingState != RecordingState.idle) {
          _setRecordingState(RecordingState.waitingServerStop);
        }
      } catch (e) {
        debugPrint("Failed to stop recording: $e");
      }
    }

    if (_recordingState == RecordingState.idle) {
      return;
    }
    await _waitForServerStop();
    await _handleTranscriptionEnded();
  }

  Future<void> _waitForServerStop() async {
    final streamDoneCompleter = _streamDoneCompleter;
    if (streamDoneCompleter == null) return;

    final streamDone = streamDoneCompleter.future;
    final timeoutCompleter = Completer<void>();
    var timedOut = false;
    _waitingServerStopTimer?.cancel();
    _waitingServerStopTimer = Timer(_waitingServerStopTimeout, () {
      if (!timeoutCompleter.isCompleted) {
        timedOut = true;
        timeoutCompleter.complete();
      }
    });
    await Future.any<void>([streamDone, timeoutCompleter.future]);
    _waitingServerStopTimer?.cancel();
    _waitingServerStopTimer = null;

    if (timedOut &&
        !streamDoneCompleter.isCompleted &&
        _recordingState == RecordingState.waitingServerStop) {
      debugPrint(
        '[SpeechRecognition] waitingServerStop timed out, forcing stop',
      );
      await AsrSpeechRecognitionService.stopRecording().timeout(
        _stopTimeout,
        onTimeout: () => null,
      );
      _completeStreamDone();
    }
  }

  void _completeStreamDone() {
    if (!(_streamDoneCompleter?.isCompleted ?? true)) {
      _streamDoneCompleter?.complete();
    }
  }

  Future<void> _handleTranscriptionEnded({
    Object? error,
    bool isServerInitiatedStop = false,
  }) async {
    if (_isFinalizingTranscription) return;
    _isFinalizingTranscription = true;

    _completeStreamDone();
    _waitingServerStopTimer?.cancel();
    _waitingServerStopTimer = null;

    try {
      // 检查是否是 token 过期错误，如果是则重新初始化
      if (error != null && error.toString().contains('TOKEN_EXPIRED')) {
        debugPrint(
          "[SpeechRecognition] Token expired, will reinitialize on next recording",
        );
        AsrSpeechRecognitionService.resetInitState();
      }
      if (isServerInitiatedStop) {
        debugPrint('[SpeechRecognition] ASR_FINAL received, stopping session');
      }

      await _transcriptionSubscription?.cancel();
      _transcriptionSubscription = null;
      _streamDoneCompleter = null;

      if (!mounted) {
        _recordingState = RecordingState.idle;
        _currentTranscript = '';
        return;
      }
      setState(() {
        _recordingState = RecordingState.idle;
        _currentTranscript = '';
      });
      widget.onRecordingStateChanged?.call(RecordingState.idle);
    } finally {
      _isFinalizingTranscription = false;
    }
  }

  /// 点击语音识别文字时，切换到输入模式
  void _onTranscriptTap() {
    if (isRecording) {
      // 停止录音，不再自动聚焦输入框，避免自动弹出软键盘
      _stopRecording();
    }
  }
}
