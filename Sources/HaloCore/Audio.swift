import Accelerate
import Foundation

public struct AudioFeatures: Sendable, Equatable {
    public let rms: Float
    public let peak: Float
    public let lowFrequencyEnergy: Float
    public let transient: Bool

    public init(rms: Float, peak: Float, lowFrequencyEnergy: Float, transient: Bool) {
        self.rms = rms
        self.peak = peak
        self.lowFrequencyEnergy = lowFrequencyEnergy
        self.transient = transient
    }

    public static let silence = AudioFeatures(rms: 0, peak: 0, lowFrequencyEnergy: 0, transient: false)
}

public struct AudioAnalyzer: Sendable {
    private let transientThreshold: Float

    public init(transientThreshold: Float = 0.18) {
        self.transientThreshold = transientThreshold
    }

    public func analyze(samples: [Float], previousRMS: Float = 0) -> AudioFeatures {
        guard !samples.isEmpty else { return .silence }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))

        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))

        // A one-pole low-pass is sufficient for the lighting envelope and is
        // considerably cheaper than running an FFT for every render buffer.
        var lowPass: Float = 0
        var lowEnergy: Float = 0
        let alpha: Float = 0.035
        for sample in samples {
            lowPass += alpha * (sample - lowPass)
            lowEnergy += lowPass * lowPass
        }
        let lowRMS = sqrt(lowEnergy / Float(samples.count))

        return AudioFeatures(
            rms: rms,
            peak: peak,
            lowFrequencyEnergy: lowRMS,
            transient: rms - previousRMS > transientThreshold
        )
    }
}

public struct AmbientLightingModel: Sendable, Equatable {
    public let brightness: Double
    public let expansion: Double
    public let saturation: Double

    public init(features: AudioFeatures, sensitivity: Double = 1) {
        let loudness = min(1, Double(features.rms) * 5.5 * sensitivity)
        let bass = min(1, Double(features.lowFrequencyEnergy) * 8 * sensitivity)
        brightness = 0.16 + loudness * 0.84
        expansion = features.transient ? 1 : 0.18 + bass * 0.72
        saturation = 0.82 + min(0.28, Double(features.peak) * 0.5)
    }
}

public struct MusicImpactDetector: Sendable {
    private var baseline = 0.0
    private var cooldown = 0.0
    public private(set) var envelope = 0.0

    public init() {}

    public mutating func update(features: AudioFeatures, deltaTime: Double, playing: Bool) -> Double {
        let dt = min(0.1, max(0, deltaTime))
        guard playing else {
            baseline = 0
            cooldown = 0
            envelope = 0
            return 0
        }
        let loudness = Double(features.rms)
        let bass = Double(features.lowFrequencyEnergy)
        cooldown = max(0, cooldown - dt)
        envelope *= exp(-dt / 0.42)
        // Compare the attack with the recent musical floor, not a fixed BPM.
        let surge = loudness > max(0.025, baseline * 1.35) && bass > 0.012
        if cooldown == 0 && surge && (features.transient || loudness - baseline > 0.03) {
            envelope = min(1, 0.55 + (loudness - baseline) * 5)
            cooldown = 0.75
        }
        baseline += (loudness - baseline) * (1 - exp(-dt / 0.65))
        return envelope
    }
}
