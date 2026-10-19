import Foundation

public enum LockScreenSupportState: Sendable, Equatable {
    case disabled
    case unsupported(reason: String)
    case experimentalAvailable
}

public protocol LockScreenAdapter: Sendable {
    var supportState: LockScreenSupportState { get }
}

public struct SafeLockScreenAdapter: LockScreenAdapter {
    public init() {}

    public var supportState: LockScreenSupportState {
        .unsupported(reason: "macOS lock-screen rendering is intentionally disabled until a public or explicitly enabled experimental adapter is verified on this Mac.")
    }
}
