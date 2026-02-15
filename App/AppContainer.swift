import SwiftUI
import CoreData

@MainActor
final class AppContainer: ObservableObject {

    // MARK: - Phase 1: Core

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

    // MARK: - Phase 2A: Audio Stability

    let audioInterruptionHandler: AudioInterruptionHandler
    let memoryPressureMonitor: MemoryPressureMonitor
    let recordingHealthMonitor: RecordingHealthMonitor

    // MARK: - Phase 2B: Advanced Search

    let fts5Manager: FTS5Manager
    let advancedSearch: AdvancedSearchService
    let paginatedLoader: PaginatedSessionLoader

    // MARK: - Phase 2D: iCloud + Storage

    let cloudSyncManager: CloudSyncManager
    let storageManager: StorageManager

    // MARK: - Phase 2E: Enhanced Export

    let enhancedExportService: EnhancedExportService

    // MARK: - Init

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

        let audioInterruptionHandler = AudioInterruptionHandler()
        self.audioInterruptionHandler = audioInterruptionHandler

        let memoryPressureMonitor = MemoryPressureMonitor()
        self.memoryPressureMonitor = memoryPressureMonitor

        let recordingHealthMonitor = RecordingHealthMonitor()
        self.recordingHealthMonitor = recordingHealthMonitor

        self.recordingCoordinator = RecordingCoordinator(
            repository: repository,
            audioSession: audioSession,
            chunkRecorder: chunkRecorder,
            interruptionHandler: audioInterruptionHandler,
            healthMonitor: recordingHealthMonitor
        )

        self.summarizer = SimpleSummarizer(repository: repository)
        self.search = SimpleSearchService(repository: repository)
        self.qna = SimpleQnAService(repository: repository)
        self.exportService = ExportService(
            repository: repository,
            fileStore: fileStore
        )

        // Phase 2B: Advanced Search
        let fts5Manager = FTS5Manager()
        self.fts5Manager = fts5Manager
        self.advancedSearch = AdvancedSearchService(
            fts5Manager: fts5Manager,
            context: coreData.viewContext
        )
        self.paginatedLoader = PaginatedSessionLoader(context: coreData.viewContext)

        // Phase 2D: iCloud + Storage
        self.cloudSyncManager = CloudSyncManager()
        self.storageManager = StorageManager(
            fileStore: fileStore,
            repository: repository
        )

        // Phase 2E: Enhanced Export
        self.enhancedExportService = EnhancedExportService(
            repository: repository,
            fileStore: fileStore
        )

        // Wire memory pressure cleanup to Core Data
        memoryPressureMonitor.onShouldCleanup = { [weak coreData] in
            coreData?.viewContext.refreshAllObjects()
        }
    }
}
