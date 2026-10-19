import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import HaloCore
import os

private final class AudioFeatureMailbox: @unchecked Sendable {
    private struct State {
        var features: AudioFeatures = .silence
        var previousRMS: Float = 0
        var smoothedRMS: Float = 0
        var lowPass: Float = 0
        var refractoryBuffers = 0
        var pendingTransient = false
        var receivedAt = 0.0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func process(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        // The callback never waits on the UI reader. Dropping a visual buffer
        // under contention is harmless; delaying the audio thread is not.
        state.withLockIfAvailableUnchecked { state in
            var squared: Float = 0
            var lowSquared: Float = 0
            var peak: Float = 0
            var sampleCount = 0
            let alpha: Float = 0.035

            for buffer in buffers {
                guard let rawData = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                guard count > 0 else { continue }
                let samples = rawData.assumingMemoryBound(to: Float.self)
                sampleCount += count
                for index in 0..<count {
                    let sample = samples[index]
                    squared += sample * sample
                    peak = max(peak, abs(sample))
                    state.lowPass += alpha * (sample - state.lowPass)
                    lowSquared += state.lowPass * state.lowPass
                }
            }
            guard sampleCount > 0 else { return }

            let rms = sqrt(squared / Float(sampleCount))
            let lowRMS = sqrt(lowSquared / Float(sampleCount))
            state.smoothedRMS += (rms - state.smoothedRMS) * (rms > state.smoothedRMS ? 0.5 : 0.12)

            if state.refractoryBuffers > 0 {
                state.refractoryBuffers -= 1
            }
            let transient = state.refractoryBuffers == 0
                && rms > max(0.035, state.previousRMS * 1.42)
                && lowRMS > 0.018
            if transient { state.refractoryBuffers = 8 }
            state.pendingTransient = state.pendingTransient || transient
            state.receivedAt = ProcessInfo.processInfo.systemUptime

            state.previousRMS = max(rms, state.previousRMS * 0.86)
            state.features = AudioFeatures(
                rms: state.smoothedRMS,
                peak: peak,
                lowFrequencyEnergy: lowRMS,
                transient: transient
            )
        }
    }

    func latest() -> AudioFeatures {
        state.withLock {
            guard ProcessInfo.processInfo.systemUptime - $0.receivedAt < 0.4 else { return .silence }
            let result = AudioFeatures(rms: $0.features.rms, peak: $0.features.peak,
                                       lowFrequencyEnergy: $0.features.lowFrequencyEnergy,
                                       transient: $0.pendingTransient)
            $0.pendingTransient = false
            return result
        }
    }

    func reset() {
        state.withLock { $0 = State() }
    }

    var hasRecentSamples: Bool {
        state.withLock { ProcessInfo.processInfo.systemUptime - $0.receivedAt < 0.4 }
    }
}

private let haloAudioIOProc: AudioDeviceIOProc = {
    _, _, inputData, _, _, _, context in
    guard let context else { return noErr }
    let engine = Unmanaged<SpotifyAudioCaptureEngine>.fromOpaque(context).takeUnretainedValue()
    engine.consume(inputData)
    return noErr
}

final class SpotifyAudioCaptureEngine: @unchecked Sendable {
    private struct ControlState {
        var running = false
        var status = "Audio reactive mode is ready."
    }

    private let mailbox = AudioFeatureMailbox()
    private let control = OSAllocatedUnfairLock(initialState: ControlState())
    private let queue = DispatchQueue(label: "com.local.Halo.audio-capture", qos: .userInitiated)
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    var status: String { control.withLock { $0.status } }
    var isRunning: Bool { control.withLock { $0.running } }
    var hasRecentSamples: Bool { mailbox.hasRecentSamples }

    deinit {
        stopSynchronously()
    }

    func start() {
        queue.async { [weak self] in
            self?.startSynchronously()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopSynchronously()
        }
    }

    func latestFeatures() -> AudioFeatures {
        mailbox.latest()
    }

    fileprivate func consume(_ inputData: UnsafePointer<AudioBufferList>) {
        mailbox.process(inputData)
    }

    private func startSynchronously() {
        guard !isRunning else { return }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.spotify.client" }) else {
            setStatus("Spotify is not running; waiting to start audio capture.")
            return
        }
        guard let processObject = Self.audioProcessObject(for: app.processIdentifier) else {
            setStatus("Spotify audio process is not available yet.")
            return
        }

        let description = CATapDescription(monoMixdownOfProcesses: [processObject])
        if #available(macOS 26.0, *) {
            description.bundleIDs = ["com.spotify.client"]
            description.isProcessRestoreEnabled = true
        }
        description.name = "Halo Spotify audio analysis"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var statusCode = AudioHardwareCreateProcessTap(description, &tapID)
        guard statusCode == noErr else {
            setStatus("Audio capture permission/setup failed (\(statusCode)).")
            cleanup()
            return
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Halo Audio Analysis",
            kAudioAggregateDeviceUIDKey: "com.local.Halo.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]]
        ]
        statusCode = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard statusCode == noErr else {
            setStatus("Audio analysis device could not be created (\(statusCode)).")
            cleanup()
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        statusCode = AudioDeviceCreateIOProcID(aggregateDeviceID, haloAudioIOProc, context, &ioProcID)
        guard statusCode == noErr, let ioProcID else {
            setStatus("Audio analysis callback could not be created (\(statusCode)).")
            cleanup()
            return
        }

        statusCode = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard statusCode == noErr else {
            setStatus("Audio analysis could not start (\(statusCode)).")
            cleanup()
            return
        }

        control.withLock {
            $0.running = true
            $0.status = "Listening to Spotify audio."
        }
    }

    private func stopSynchronously() {
        cleanup()
        mailbox.reset()
        setStatus("Audio capture stopped.")
    }

    private func cleanup() {
        if let ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
        control.withLock { $0.running = false }
    }

    private func setStatus(_ status: String) {
        control.withLock { $0.status = status }
    }

    private static func audioProcessObject(for pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutablePID = pid
        var objectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &mutablePID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                qualifier,
                &size,
                &objectID
            )
        }
        return status == noErr && objectID != kAudioObjectUnknown ? objectID : nil
    }
}
