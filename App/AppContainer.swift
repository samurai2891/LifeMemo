import SwiftUI
import CoreData

@MainActor
final class AppContainer: ObservableObject {
    let coreData: CoreDataStack
    let repository: SessionRepository
    let fileStore: FileStore

    let speechPermission: SpeechPermissionService
    let transcriber: OnDeviceTranscriber
    let transcriptionQueue: TranscriptionQueueActor

    let audioSession: AudioSessionConfigurator
    let chunkRecorder: ChunkedAudioRecorder
    let recordingCoordinator: RecordingCoordinator

    let summarizer: SimpleSummarizer
    let search: SimpleSearchService
    let qna: SimpleQnAService
    let exportService: ExportService

    init() {
        let coreData = CoreDataStack(modelName: "LifeMemo")
        let fileStore = FileStore()
        let repository = SessionRepository(context: coreData.viewContext, fileStore: fileStore)

        self.coreData = coreData
        self.fileStore = fileStore
        self.repository = repository

        let speechPermission = SpeechPermissionService()
        self.speechPermission = speechPermission

        let transcriber = OnDeviceTranscriber()
        self.transcriber = transcriber

        let transcriptionQueue = TranscriptionQueueActor(
            repository: repository,
            transcriber: transcriber
        )
        self.transcriptionQueue = transcriptionQueue

        let audioSession = AudioSessionConfigurator()
        self.audioSession = audioSession

        let chunkRecorder = ChunkedAudioRecorder(
            repository: repository,
            fileStore: fileStore,
            transcriptionQueue: transcriptionQueue
        )
        self.chunkRecorder = chunkRecorder

        self.recordingCoordinator = RecordingCoordinator(
            repository: repository,
            audioSession: audioSession,
            chunkRecorder: chunkRecorder
        )

        self.summarizer = SimpleSummarizer(repository: repository)
        self.search = SimpleSearchService(repository: repository)
        self.qna = SimpleQnAService(repository: repository)
        self.exportService = ExportService(
            repository: repository,
            fileStore: fileStore
        )
    }
}
