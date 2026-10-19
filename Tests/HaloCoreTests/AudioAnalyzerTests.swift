import XCTest
@testable import HaloCore

final class AudioAnalyzerTests: XCTestCase {
    func testSilence() {
        XCTAssertEqual(AudioAnalyzer().analyze(samples: []), .silence)
        XCTAssertEqual(AudioAnalyzer().analyze(samples: Array(repeating: 0, count: 128)).rms, 0, accuracy: 0.0001)
    }

    func testConstantSignal() {
        let features = AudioAnalyzer().analyze(samples: Array(repeating: 0.5, count: 128))
        XCTAssertEqual(features.rms, 0.5, accuracy: 0.001)
        XCTAssertEqual(features.peak, 0.5, accuracy: 0.001)
    }

    func testSyntheticTransient() {
        let samples = Array(repeating: Float(0.8), count: 128)
        XCTAssertTrue(AudioAnalyzer(transientThreshold: 0.1).analyze(samples: samples, previousRMS: 0.1).transient)
    }

    func testBassEnergyDistinguishesEqualLoudnessLowAndHighTones() {
        let bass = (0..<4096).map { Float(sin(Double($0) * 2 * .pi * 80 / 48000)) * 0.5 }
        let treble = (0..<4096).map { Float(sin(Double($0) * 2 * .pi * 6000 / 48000)) * 0.5 }
        let low = AudioAnalyzer().analyze(samples: bass)
        let high = AudioAnalyzer().analyze(samples: treble)
        XCTAssertEqual(low.rms, high.rms, accuracy: 0.015)
        XCTAssertGreaterThan(low.lowFrequencyEnergy, high.lowFrequencyEnergy * 5)
    }

    func testDropBurstsThenDecaysAndResetsOnPause() {
        var detector = MusicImpactDetector()
        let quiet = AudioFeatures(rms: 0.02, peak: 0.04, lowFrequencyEnergy: 0.01, transient: false)
        for _ in 0..<60 { _ = detector.update(features: quiet, deltaTime: 1.0 / 60, playing: true) }
        let drop = AudioFeatures(rms: 0.3, peak: 0.8, lowFrequencyEnergy: 0.2, transient: true)
        let attack = detector.update(features: drop, deltaTime: 1.0 / 60, playing: true)
        XCTAssertGreaterThan(attack, 0.8)
        let nextBeat = detector.update(features: drop, deltaTime: 0.05, playing: true)
        XCTAssertLessThan(nextBeat, attack)
        for _ in 0..<120 { _ = detector.update(features: quiet, deltaTime: 1.0 / 60, playing: true) }
        XCTAssertLessThan(detector.envelope, 0.02)
        XCTAssertEqual(detector.update(features: drop, deltaTime: 0.016, playing: false), 0)
    }
}
