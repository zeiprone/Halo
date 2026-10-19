import XCTest
@testable import HaloCore

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
    func testInterpolatesOnlyWhilePlaying() {
        let track = Track(title: "Song", artist: "Artist", duration: 120)
        let base = ContinuousClock.now
        let coordinator = PlaybackCoordinator(provider: MockMusicProvider(observations: []))

        coordinator.apply(PlaybackObservation(track: track, state: .playing, position: 10, observedAt: base))
        XCTAssertEqual(coordinator.interpolatedPosition(at: base.advanced(by: .seconds(4))), 14, accuracy: 0.01)

        coordinator.apply(PlaybackObservation(track: track, state: .paused, position: 20, observedAt: base))
        XCTAssertEqual(coordinator.interpolatedPosition(at: base.advanced(by: .seconds(4))), 20, accuracy: 0.01)
    }

    func testTrackChangeReplacesAuthoritativeState() {
        let first = Track(title: "One", artist: "A", duration: 90)
        let second = Track(title: "Two", artist: "A", duration: 100)
        let coordinator = PlaybackCoordinator(provider: MockMusicProvider(observations: []))
        coordinator.apply(PlaybackObservation(track: first, state: .playing, position: 40))
        coordinator.apply(PlaybackObservation(track: second, state: .playing, position: 3))
        XCTAssertEqual(coordinator.currentTrack, second)
        XCTAssertLessThan(coordinator.interpolatedPosition, 4)
    }
}
