import AVFAudio
import Foundation

@MainActor
final class VoiceEnrollmentViewModel: ObservableObject {

    @Published private(set) var prompts: [VoiceEnrollmentPrompt] = VoiceEnrollmentPrompt.defaultPrompts
    @Published private(set) var acceptedPromptIds: Set<Int> = []
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var elapsedSec: TimeInterval = 0
    @Published private(set) var activeProfile: VoiceEnrollmentProfile?
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let enrollmentService: VoiceEnrollmentService
    private let permissionService: SpeechPermissionService
    private let audioSession: AudioSessionConfigurator
    private let fileStore: FileStore

    private var recorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var currentPromptId: Int?
    private var recordingStartedAt: Date?
    private var autoStopTask: Task<Void, Never>?
    private var elapsedTickerTask: Task<Void, Never>?

    private let maxTakeDurationSec: TimeInterval = 8.0

    init(
        enrollmentService: VoiceEnrollmentService,
        permissionService: SpeechPermissionService,
        audioSession: AudioSessionConfigurator,
        fileStore: FileStore
    ) {
        self.enrollmentService = enrollmentService
        self.permissionService = permissionService
        self.audioSession = audioSession
        self.fileStore = fileStore
    }

    var completedCount: Int { acceptedPromptIds.count }
    var totalCount: Int { prompts.count }
    var progressRatio: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
    var canFinalize: Bool { completedCount == totalCount && !isRecording }
    var currentPrompt: VoiceEnrollmentPrompt? {
        prompts.first { !acceptedPromptIds.contains($0.id) }
    }

    func refresh() async {
        activeProfile = await enrollmentService.activeProfile()
        acceptedPromptIds = await enrollmentService.pendingPromptIds()
    }

    func resetCurrentEnrollment() async {
        await enrollmentService.startEnrollmentSession()
        acceptedPromptIds = []
        statusMessage = "登録セッションをリセットしました。"
        errorMessage = nil
    }

    func clearEnrollmentProfile() async {
        await enrollmentService.clearEnrollment()
        activeProfile = nil
        acceptedPromptIds = []
        statusMessage = "登録済みの声プロフィールを削除しました。"
        errorMessage = nil
    }

    func toggleRecording() async {
        if isRecording {
            await finishRecording()
        } else {
            await startRecording()
        }
    }

    func finalizeEnrollment() async {
        guard canFinalize else {
            errorMessage = "すべての登録文の録音を完了してください。"
            return
        }
        isFinalizing = true
        defer { isFinalizing = false }
        do {
            let profile = try await enrollmentService.finalizeEnrollment(displayName: "Me")
            activeProfile = profile
            acceptedPromptIds = []
            statusMessage = "声登録が完了しました。以後は話者分離で Me を優先判定します。"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startRecording() async {
        errorMessage = nil
        statusMessage = nil

        guard let prompt = currentPrompt else {
            errorMessage = "登録対象の文がありません。完了ボタンを押してください。"
            return
        }

        if permissionService.mic == .unknown {
            await permissionService.requestMicrophone()
        }
        if permissionService.mic != .granted {
            errorMessage = "マイク権限が必要です。"
            return
        }

        do {
            try audioSession.activateRecordingSession()
            let relativePath = "Enrollment/Takes/\(UUID().uuidString).m4a"
            let recordingURL = try fileStore.ensureAudioFileURL(relativePath: relativePath)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            recorder.isMeteringEnabled = false
            guard recorder.record() else {
                audioSession.deactivate()
                try? FileManager.default.removeItem(at: recordingURL)
                errorMessage = "録音開始に失敗しました。マイク設定を確認して再試行してください。"
                return
            }

            self.recorder = recorder
            self.currentRecordingURL = recordingURL
            self.currentPromptId = prompt.id
            self.recordingStartedAt = Date()
            self.elapsedSec = 0
            self.isRecording = true

            startElapsedTimer()
            autoStopTask = Task { [weak self] in
                let seconds = self?.maxTakeDurationSec ?? 8.0
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard let self else { return }
                await self.autoStopIfNeeded()
            }
        } catch {
            audioSession.deactivate()
            errorMessage = "録音開始に失敗しました: \(error.localizedDescription)"
        }
    }

    private func autoStopIfNeeded() async {
        guard isRecording else { return }
        await finishRecording()
    }

    private func finishRecording() async {
        guard isRecording else { return }
        let recordedDurationSec = recorder?.currentTime ?? 0
        stopRecorderOnly()

        guard let promptId = currentPromptId, let recordingURL = currentRecordingURL else {
            errorMessage = "録音ファイルの参照に失敗しました。"
            cleanupRecordingState()
            return
        }

        defer {
            try? FileManager.default.removeItem(at: recordingURL)
            cleanupRecordingState()
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        guard recordedDurationSec > 0,
              let fileSize = Self.fileSizeBytes(at: recordingURL),
              fileSize > 0 else {
            errorMessage = VoiceEnrollmentError.emptyOrUnflushedFile.localizedDescription
            return
        }

        do {
            let quality = try await enrollmentService.registerTake(
                promptId: promptId,
                audioURL: recordingURL
            )
            acceptedPromptIds = await enrollmentService.pendingPromptIds()
            statusMessage = String(
                format: "録音を採用しました（SNR %.1f dB, 音声比 %.0f%%）",
                quality.snrDb,
                quality.speechRatio * 100
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecorderOnly() {
        autoStopTask?.cancel()
        autoStopTask = nil
        elapsedTickerTask?.cancel()
        elapsedTickerTask = nil
        recorder?.stop()
        recorder = nil
        audioSession.deactivate()
        isRecording = false
        elapsedSec = 0
    }

    private func cleanupRecordingState() {
        currentRecordingURL = nil
        currentPromptId = nil
        recordingStartedAt = nil
    }

    private func startElapsedTimer() {
        elapsedTickerTask?.cancel()
        elapsedTickerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let started = await MainActor.run(body: { self.recordingStartedAt }) {
                    await MainActor.run {
                        self.elapsedSec = Date().timeIntervalSince(started)
                    }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private static func fileSizeBytes(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return nil
        }
        return fileSize.int64Value
    }
}
