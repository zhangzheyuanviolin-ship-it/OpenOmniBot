import AVFoundation
@preconcurrency import Flutter
import Foundation
import Speech

@MainActor
final class SpeechRecognitionCoordinator: NSObject {
    static let shared = SpeechRecognitionCoordinator()

    private let methodChannelName = "cn.com.omnimind.bot/SpeechRecognition"
    private let eventChannelName = "cn.com.omnimind.bot/SpeechRecognitionEvents"

    private var eventSink: FlutterEventSink?
    private var pendingEvents: [Any] = []
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var lastTranscript = ""
    private var isGracefullyStopping = false

    private override init() {
        super.init()
    }

    func register(on engine: FlutterEngine) {
        let messenger = engine.binaryMessenger
        methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: messenger
        )
        methodChannel?.setMethodCallHandler(handleMethodCall)

        eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: messenger
        )
        eventChannel?.setStreamHandler(self)
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            Task {
                result(await initialize())
            }
        case "startRecording":
            Task {
                result(await startRecording())
            }
        case "stopSendingOnly":
            stopSendingOnly()
            result(nil)
        case "stopRecording":
            stopRecording()
            result(nil)
        case "release":
            releaseResources()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func initialize() async -> Bool {
        let speechAuthorized = await requestSpeechAuthorization()
        let microphoneGranted = await requestMicrophonePermission()
        if speechAuthorized == false || microphoneGranted == false {
            return false
        }
        speechRecognizer =
            SFSpeechRecognizer(locale: Locale(identifier: Locale.preferredLanguages.first ?? "zh-CN"))
            ?? SFSpeechRecognizer(locale: Locale.current)
        return speechRecognizer != nil
    }

    func startRecording() async -> Bool {
        guard await initialize() else { return false }

        cleanupRecognition(keepEventStream: true)
        isGracefullyStopping = false
        lastTranscript = ""

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            emitError(
                FlutterError(
                    code: "AUDIO_SESSION",
                    message: error.localizedDescription,
                    details: nil
                )
            )
            return false
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let recognizer = speechRecognizer ?? SFSpeechRecognizer(locale: Locale.current)
        speechRecognizer = recognizer
        guard let recognizer else {
            emitError(
                FlutterError(
                    code: "SPEECH_UNAVAILABLE",
                    message: "Speech recognizer is unavailable.",
                    details: nil
                )
            )
            return false
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            emitError(
                FlutterError(
                    code: "AUDIO_START_FAILED",
                    message: error.localizedDescription,
                    details: nil
                )
            )
            return false
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] recognitionResult, recognitionError in
            Task { @MainActor in
                guard let self else { return }

                if let recognitionResult {
                    let transcript = recognitionResult.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if transcript.isEmpty == false && transcript != self.lastTranscript {
                        self.lastTranscript = transcript
                        self.emitEvent(transcript)
                    }
                    if recognitionResult.isFinal {
                        self.finishGracefully()
                    }
                }

                if let recognitionError {
                    if self.isGracefullyStopping {
                        self.finishGracefully()
                    } else {
                        self.emitError(
                            FlutterError(
                                code: "ASR_ERROR",
                                message: recognitionError.localizedDescription,
                                details: nil
                            )
                        )
                        self.cleanupRecognition(keepEventStream: true)
                    }
                }
            }
        }

        return true
    }

    func stopSendingOnly() {
        guard audioEngine.isRunning || recognitionRequest != nil else { return }
        isGracefullyStopping = true
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    func stopRecording() {
        isGracefullyStopping = false
        cleanupRecognition(keepEventStream: true)
        emitEndOfStream()
    }

    func releaseResources() {
        stopRecording()
        pendingEvents.removeAll()
    }

    private func finishGracefully() {
        cleanupRecognition(keepEventStream: true)
        emitEndOfStream()
    }

    private func cleanupRecognition(keepEventStream: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if keepEventStream == false {
            eventSink = nil
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized {
            return true
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                continuation.resume(returning: newStatus == .authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func emitEvent(_ event: Any) {
        if let eventSink {
            eventSink(event)
            return
        }
        pendingEvents.append(event)
    }

    private func emitError(_ error: FlutterError) {
        if let eventSink {
            eventSink(error)
            return
        }
        pendingEvents.append(error)
    }

    private func emitEndOfStream() {
        if let eventSink {
            eventSink(FlutterEndOfEventStream)
        } else {
            pendingEvents.append(FlutterEndOfEventStream)
        }
    }
}

extension SpeechRecognitionCoordinator: @preconcurrency FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        if pendingEvents.isEmpty == false {
            let queuedEvents = pendingEvents
            pendingEvents.removeAll()
            for event in queuedEvents {
                events(event)
            }
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
