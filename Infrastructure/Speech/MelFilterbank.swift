import Accelerate
import AVFoundation
import Foundation

/// MFCC extraction pipeline using Accelerate framework.
///
/// Extracts 13 Mel-frequency cepstral coefficients per frame with delta and
/// delta-delta features, plus per-frame RMS energy. The complete pipeline:
///
/// 1. Pre-emphasis (0.97)
/// 2. Hamming window
/// 3. Zero-padded FFT (512-point)
/// 4. Power spectrum
/// 5. Mel filterbank (26 filters)
/// 6. Log compression
/// 7. DCT-II → 13 MFCCs
/// 8. Delta & delta-delta computation
enum MelFilterbank {

    /// Result of MFCC extraction for an audio signal.
    struct MFCCResult {
        let mfccs: [[Float]]          // [numFrames][13]
        let deltas: [[Float]]         // [numFrames][13]
        let deltaDeltas: [[Float]]    // [numFrames][13]
        let rmsEnergies: [Float]      // [numFrames]
        let frameTimestamps: [Float]  // [numFrames] in seconds
    }

    // MARK: - Configuration

    static let frameLength = 400      // 25ms @ 16kHz
    static let frameHop = 160         // 10ms hop
    static let fftSize = 512
    static let numMelFilters = 26
    static let numMFCCs = 13
    static let preEmphasis: Float = 0.97
    static let deltaWidth = 2

    // MARK: - Public API

    /// Extracts MFCCs, deltas, delta-deltas, and RMS energies from raw audio samples.
    ///
    /// - Parameters:
    ///   - samples: Mono audio samples (Float, [-1, 1] range).
    ///   - sampleRate: Sample rate in Hz (typically 16000).
    /// - Returns: `MFCCResult` with per-frame features.
    static func extractMFCCs(samples: [Float], sampleRate: Float) -> MFCCResult {
        guard samples.count >= frameLength else {
            return MFCCResult(mfccs: [], deltas: [], deltaDeltas: [], rmsEnergies: [], frameTimestamps: [])
        }

        // Pre-compute reusable resources
        let window = hammingWindow(length: frameLength)
        let filterbank = createFilterbank(sampleRate: sampleRate)
        let numFrames = max(0, (samples.count - frameLength) / frameHop + 1)

        // Pre-emphasis
        let emphasized = applyPreEmphasis(samples: samples)

        // FFT setup
        let log2n = vDSP_Length(log2f(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return MFCCResult(mfccs: [], deltas: [], deltaDeltas: [], rmsEnergies: [], frameTimestamps: [])
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // DCT setup
        guard let dctSetup = vDSP_DCT_CreateSetup(nil, vDSP_Length(numMelFilters), .II) else {
            return MFCCResult(mfccs: [], deltas: [], deltaDeltas: [], rmsEnergies: [], frameTimestamps: [])
        }

        var allMFCCs: [[Float]] = []
        var allEnergies: [Float] = []
        var allTimestamps: [Float] = []

        allMFCCs.reserveCapacity(numFrames)
        allEnergies.reserveCapacity(numFrames)
        allTimestamps.reserveCapacity(numFrames)

        let halfFFT = fftSize / 2 + 1

        for frameIdx in 0..<numFrames {
            let start = frameIdx * frameHop
            let end = start + frameLength

            // Extract and window the frame
            var frame = Array(emphasized[start..<end])
            vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(frameLength))

            // RMS energy of windowed frame
            var rms: Float = 0
            vDSP_rmsqv(frame, 1, &rms, vDSP_Length(frameLength))
            allEnergies.append(rms)

            // Power spectrum
            let power = computePowerSpectrum(frame: frame, fftSetup: fftSetup)

            // Mel filterbank
            let melEnergies = applyFilterbank(power: power, bank: filterbank, halfFFT: halfFFT)

            // Log compression
            var logMel = melEnergies
            var floor: Float = 1e-10
            vDSP_vthr(logMel, 1, &floor, &logMel, 1, vDSP_Length(numMelFilters))
            var count = Int32(numMelFilters)
            vvlogf(&logMel, logMel, &count)

            // DCT-II → MFCCs
            var dctOutput = [Float](repeating: 0, count: numMelFilters)
            vDSP_DCT_Execute(dctSetup, logMel, &dctOutput)
            let mfcc = Array(dctOutput.prefix(numMFCCs))

            allMFCCs.append(mfcc)
            allTimestamps.append(Float(start) / sampleRate)
        }

        // Delta and delta-delta
        let deltas = computeDeltas(features: allMFCCs, width: deltaWidth)
        let deltaDeltas = computeDeltas(features: deltas, width: deltaWidth)

        return MFCCResult(
            mfccs: allMFCCs,
            deltas: deltas,
            deltaDeltas: deltaDeltas,
            rmsEnergies: allEnergies,
            frameTimestamps: allTimestamps
        )
    }

    /// Reads mono 16kHz audio samples from a file URL.
    ///
    /// - Parameter url: Path to the audio file.
    /// - Returns: Tuple of (samples, sampleRate), or `nil` on failure.
    static func readSamples(url: URL) -> (samples: [Float], sampleRate: Float)? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }

        let sampleRate = Float(audioFile.fileFormat.sampleRate)
        let frameCount = AVAudioFrameCount(audioFile.length)
        guard frameCount > 0 else { return nil }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            return nil
        }

        guard let channelData = buffer.floatChannelData else { return nil }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength)))

        return (samples: samples, sampleRate: sampleRate)
    }

    // MARK: - Mel Conversion

    static func hzToMel(_ hz: Float) -> Float {
        2595.0 * log10f(1.0 + hz / 700.0)
    }

    static func melToHz(_ mel: Float) -> Float {
        700.0 * (powf(10.0, mel / 2595.0) - 1.0)
    }

    // MARK: - Filterbank Construction

    /// Creates a Mel filterbank matrix [numMelFilters][fftSize/2+1].
    static func createFilterbank(sampleRate: Float) -> [[Float]] {
        let halfFFT = fftSize / 2 + 1
        let lowMel = hzToMel(0)
        let highMel = hzToMel(sampleRate / 2)

        // numMelFilters + 2 equally spaced points in Mel scale
        let numPoints = numMelFilters + 2
        var melPoints = [Float](repeating: 0, count: numPoints)
        let melStep = (highMel - lowMel) / Float(numPoints - 1)
        for i in 0..<numPoints {
            melPoints[i] = lowMel + Float(i) * melStep
        }

        // Convert back to Hz then to FFT bin indices
        let hzPoints = melPoints.map { melToHz($0) }
        let binPoints = hzPoints.map { hz -> Int in
            Int(floorf(hz * Float(fftSize) / sampleRate))
        }

        // Build triangular filters
        var filterbank = [[Float]](repeating: [Float](repeating: 0, count: halfFFT), count: numMelFilters)

        for m in 0..<numMelFilters {
            let left = binPoints[m]
            let center = binPoints[m + 1]
            let right = binPoints[m + 2]

            // Rising slope
            if center > left {
                for k in left...center {
                    guard k >= 0, k < halfFFT else { continue }
                    filterbank[m][k] = Float(k - left) / Float(center - left)
                }
            }

            // Falling slope
            if right > center {
                for k in center...right {
                    guard k >= 0, k < halfFFT else { continue }
                    filterbank[m][k] = Float(right - k) / Float(right - center)
                }
            }
        }

        return filterbank
    }

    // MARK: - Power Spectrum

    static func computePowerSpectrum(
        frame: [Float],
        fftSetup: FFTSetup
    ) -> [Float] {
        let halfFFT = fftSize / 2
        let log2n = vDSP_Length(log2f(Float(fftSize)))

        // Zero-pad to fftSize
        var paddedFrame = [Float](repeating: 0, count: fftSize)
        let copyCount = min(frame.count, fftSize)
        paddedFrame.replaceSubrange(0..<copyCount, with: frame.prefix(copyCount))

        // Convert to split complex for in-place FFT
        var realParts = [Float](repeating: 0, count: halfFFT)
        var imagParts = [Float](repeating: 0, count: halfFFT)

        realParts.withUnsafeMutableBufferPointer { realBuf in
            imagParts.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )

                // Pack real signal into split complex format
                paddedFrame.withUnsafeBufferPointer { inputBuf in
                    let inputPtr = UnsafeRawPointer(inputBuf.baseAddress!)
                        .assumingMemoryBound(to: DSPComplex.self)
                    vDSP_ctoz(inputPtr, 2, &splitComplex, 1, vDSP_Length(halfFFT))
                }

                // In-place FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // Scale (vDSP FFT produces 2x scaled output)
                var scale: Float = 0.5
                vDSP_vsmul(splitComplex.realp, 1, &scale, splitComplex.realp, 1, vDSP_Length(halfFFT))
                vDSP_vsmul(splitComplex.imagp, 1, &scale, splitComplex.imagp, 1, vDSP_Length(halfFFT))
            }
        }

        // Compute power spectrum: |X[k]|² = real² + imag²
        var power = [Float](repeating: 0, count: halfFFT + 1)
        // DC component
        power[0] = realParts[0] * realParts[0]
        // Nyquist component (packed in imagParts[0] by vDSP convention)
        power[halfFFT] = imagParts[0] * imagParts[0]

        for k in 1..<halfFFT {
            power[k] = realParts[k] * realParts[k] + imagParts[k] * imagParts[k]
        }

        return power
    }

    // MARK: - Filterbank Application

    static func applyFilterbank(power: [Float], bank: [[Float]], halfFFT: Int) -> [Float] {
        var melEnergies = [Float](repeating: 0, count: numMelFilters)

        for m in 0..<numMelFilters {
            var energy: Float = 0
            vDSP_dotpr(power, 1, bank[m], 1, &energy, vDSP_Length(min(power.count, bank[m].count)))
            melEnergies[m] = energy
        }

        return melEnergies
    }

    // MARK: - DCT (standalone for testing)

    static func computeDCT(logMel: [Float], dctSetup: OpaquePointer) -> [Float] {
        var dctOutput = [Float](repeating: 0, count: logMel.count)
        vDSP_DCT_Execute(dctSetup, logMel, &dctOutput)
        return Array(dctOutput.prefix(numMFCCs))
    }

    // MARK: - Delta Computation

    /// Computes delta features using the regression formula:
    /// `delta[t] = sum(n * (c[t+n] - c[t-n])) / (2 * sum(n²))` for n = 1..width
    static func computeDeltas(features: [[Float]], width: Int) -> [[Float]] {
        guard !features.isEmpty else { return [] }
        let numFrames = features.count
        let dim = features[0].count

        let denominator: Float = 2 * (1..<(width + 1)).reduce(Float(0)) { $0 + Float($1 * $1) }
        guard denominator > 0 else { return features.map { _ in [Float](repeating: 0, count: dim) } }

        var deltas = [[Float]](repeating: [Float](repeating: 0, count: dim), count: numFrames)

        for t in 0..<numFrames {
            for n in 1...width {
                let tPlusN = min(t + n, numFrames - 1)
                let tMinusN = max(t - n, 0)
                let weight = Float(n)
                for d in 0..<dim {
                    deltas[t][d] += weight * (features[tPlusN][d] - features[tMinusN][d])
                }
            }
            for d in 0..<dim {
                deltas[t][d] /= denominator
            }
        }

        return deltas
    }

    // MARK: - Pre-emphasis

    static func applyPreEmphasis(samples: [Float]) -> [Float] {
        guard samples.count > 1 else { return samples }
        var result = [Float](repeating: 0, count: samples.count)
        result[0] = samples[0]
        for i in 1..<samples.count {
            result[i] = samples[i] - preEmphasis * samples[i - 1]
        }
        return result
    }

    // MARK: - Hamming Window

    static func hammingWindow(length: Int) -> [Float] {
        var window = [Float](repeating: 0, count: length)
        vDSP_hamm_window(&window, vDSP_Length(length), 0)
        return window
    }
}
