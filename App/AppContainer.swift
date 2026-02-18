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

    // MARK: - Phase 2D: Storage

    let storageManager: StorageManager

    // MARK: - Phase 2E: Enhanced Export

    let enhancedExportService: EnhancedExportService

    // MARK: - v1.0: Audio Metering

    let audioMeterCollector: AudioMeterCollector

    // MARK: - v1.0: STT

    let transcriptionCapabilityChecker: TranscriptionCapabilityChecker
    let liveTranscriber: LiveTranscriber

    // MARK: - v1.0: Security

    let appLockManager: AppLockManager
    let exposureGuard: ExposureGuard

    // MARK: - v1.0: Backup

    let backupService: BackupService

    // MARK: - v1.0: Storage Limit

    let storageLimitManager: StorageLimitManager

    // MARK: - v1.0: Summarization

    let nlSummarizer: NLExtractiveSummarizer
    let textRankSummarizer: TextRankSummarizer
    let leadSummarizer: LeadSummarizer
    let topicExtractor: TopicExtractor
    let summarizationBenchmark: SummarizationBenchmark

    // MARK: - v1.0: Logging

    let logExporter: AppLogExporter

    // MARK: - v1.0: Location

    let locationService: LocationService

    // MARK: - Init

    init() {
        // Run storage migration BEFORE CoreData init
        StorageMigrator.migrateIfNeeded()

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

        let audioMeterCollector = AudioMeterCollector()
        self.audioMeterCollector = audioMeterCollector

        let chunkRecorder = ChunkedAudioRecorder(
            repository: repository,
            fileStore: fileStore,
            transcriptionQueue: transcriptionQueue
        )
        chunkRecorder.meterCollector = audioMeterCollector
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

        // v1.0: Summarization
        let nlSummarizer = NLExtractiveSummarizer()
        self.nlSummarizer = nlSummarizer
        let textRankSummarizer = TextRankSummarizer()
        self.textRankSummarizer = textRankSummarizer
        let leadSummarizer = LeadSummarizer()
        self.leadSummarizer = leadSummarizer
        let topicExtractor = TopicExtractor()
        self.topicExtractor = topicExtractor
        self.summarizationBenchmark = SummarizationBenchmark()

        self.summarizer = SimpleSummarizer(
            repository: repository,
            extractiveSummarizer: nlSummarizer,
            textRankSummarizer: textRankSummarizer,
            leadSummarizer: leadSummarizer,
            topicExtractor: topicExtractor
        )
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

        // Storage
        self.storageManager = StorageManager(
            fileStore: fileStore,
            repository: repository
        )

        // Phase 2E: Enhanced Export
        self.enhancedExportService = EnhancedExportService(
            repository: repository,
            fileStore: fileStore
        )

        // v1.0: STT
        self.transcriptionCapabilityChecker = TranscriptionCapabilityChecker()
        self.liveTranscriber = LiveTranscriber()

        // v1.0: Security
        self.appLockManager = AppLockManager()
        let exposureGuard = ExposureGuard()
        self.exposureGuard = exposureGuard

        // v1.0: Backup
        self.backupService = BackupService(
            repository: repository,
            fileStore: fileStore
        )

        // v1.0: Storage Limit
        let storageLimitManager = StorageLimitManager(
            fileStore: fileStore,
            repository: repository
        )
        self.storageLimitManager = storageLimitManager

        // v1.0: Logging
        self.logExporter = AppLogExporter()

        // v1.0: Location
        self.locationService = LocationService()

        // Wire memory pressure cleanup to Core Data
        memoryPressureMonitor.onShouldCleanup = { [weak coreData] in
            coreData?.viewContext.refreshAllObjects()
        }

        // Check storage limits on launch
        storageLimitManager.checkAndEnforce()

        // P1-02: Enforce zero external exposure on every launch
        exposureGuard.enforceOnLaunch()
    }
}
