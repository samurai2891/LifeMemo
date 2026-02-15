import Foundation
import os.log

/// Monitors system memory pressure during long recording sessions.
///
/// When memory pressure is elevated, triggers cleanup actions like
/// flushing Core Data caches and releasing non-essential resources.
@MainActor
final class MemoryPressureMonitor: ObservableObject {

    enum PressureLevel: String {
        case normal
        case warning
        case critical
    }

    @Published private(set) var currentLevel: PressureLevel = .normal
    @Published private(set) var peakMemoryMB: Double = 0

    private let logger = Logger(subsystem: "com.lifememo.app", category: "Memory")

    /// Callback for when memory cleanup should be performed
    var onShouldCleanup: (() -> Void)?

    private var source: DispatchSourceMemoryPressure?
    private var periodicTimer: Timer?

    init() {
        setupMemoryPressureSource()
        startPeriodicCheck()
    }

    // MARK: - Setup

    private func setupMemoryPressureSource() {
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )

        src.setEventHandler { [weak self] in
            let event = src.data
            Task { @MainActor in
                if event.contains(.critical) {
                    self?.handlePressure(.critical)
                } else if event.contains(.warning) {
                    self?.handlePressure(.warning)
                }
            }
        }

        src.resume()
        source = src
    }

    private func startPeriodicCheck() {
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryStats()
            }
        }
    }

    // MARK: - Handlers

    private func handlePressure(_ level: PressureLevel) {
        currentLevel = level
        logger.warning("Memory pressure: \(level.rawValue)")

        switch level {
        case .normal:
            break
        case .warning:
            performLightCleanup()
        case .critical:
            performAggressiveCleanup()
        }
    }

    private func performLightCleanup() {
        logger.info("Performing light memory cleanup")
        onShouldCleanup?()
        URLCache.shared.removeAllCachedResponses()
    }

    private func performAggressiveCleanup() {
        logger.warning("Performing aggressive memory cleanup")
        onShouldCleanup?()
        URLCache.shared.removeAllCachedResponses()
        // Signal to UI to release cached images, etc.
    }

    private func updateMemoryStats() {
        let memoryMB = currentMemoryUsageMB()
        if memoryMB > peakMemoryMB {
            peakMemoryMB = memoryMB
        }

        if memoryMB > 500 {
            handlePressure(.warning)
        }
    }

    private func currentMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / (1024 * 1024)
    }

    func stop() {
        source?.cancel()
        source = nil
        periodicTimer?.invalidate()
        periodicTimer = nil
    }
}
