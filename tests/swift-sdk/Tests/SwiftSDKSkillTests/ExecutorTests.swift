//
// Where `Ditto.open` actually runs.
//
// This exists because the skill got it wrong in both directions. An early revision said
// `openSync` blocks and `open` is the fix; a review argued `open` "wraps the synchronous
// initializer in a continuation it resumes inline", concluded that awaiting it from
// `@MainActor` opens the store on the main thread, and the skill was changed to wrap it
// in `Task.detached`. The continuation reading is correct and the conclusion does not
// follow: `Ditto.open` is declared NONISOLATED, and a nonisolated `async` function does
// not inherit the caller's executor (SE-0338), so it hops to the cooperative pool before
// the closure ever runs. Every shipped DittoSwift is built with a Swift 6 compiler, so
// the rule applies on all three lines.
//
// Two assertions, neither of which depends on a timing margin:
//
//   * SE-0338 holds in THIS build configuration — the mechanism the claim rests on.
//   * `openSync` on the main actor blocks the main queue for the whole open. This one is
//     structural: the main queue cannot run a timer while the main thread is blocked, so
//     the measured stall is the call duration by construction, not a race against load.
//
// The complementary number — how long `await Ditto.open` stalls the main queue — is
// printed rather than asserted. Measured at 6ms against opens of 59-203ms, a margin of
// 10-30x, but an upper bound in the low milliseconds measures machine load, and this
// suite has twice shipped assertions that did exactly that.
//

import Foundation
import Testing

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

@testable import SkillSupport

/// Records how long the main queue goes without running its timer.
final class MainQueueStall: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date()
    private var worst: TimeInterval = 0

    func tick() {
        lock.lock()
        let now = Date()
        worst = max(worst, now.timeIntervalSince(last))
        last = now
        lock.unlock()
    }

    func reset() { lock.lock(); last = Date(); worst = 0; lock.unlock() }

    /// Includes the stall still in progress. Reading `worst` alone right after a blocking
    /// call misses it, because the tick that would record it has not run yet — that error
    /// made the first version of this probe report 0.0ms for a fully blocked main thread.
    var value: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return max(worst, Date().timeIntervalSince(last))
    }
}

@Suite("Executors")
struct ExecutorTests {

    /// The mechanism the `open` guidance rests on, asserted directly and without a clock.
    @Test("a nonisolated async function does not run on the caller's actor (SE-0338)")
    @MainActor
    func nonisolatedAsyncLeavesTheCallersActor() async {
        #expect(Self.onMainThread(), "precondition: this test body is on the main actor")
        let ranOnMain = await Self.nonisolatedProbe()
        let message: Comment = "a nonisolated async function ran on the caller's actor; SE-0338 does not hold here, and the skill's `await Ditto.open` guidance depends on it"
        #expect(ranOnMain == false, message)
    }

    /// `Thread.isMainThread` is unavailable from an async context — which is precisely the
    /// question being asked — so ask it from a synchronous one.
    private nonisolated static func onMainThread() -> Bool { Thread.isMainThread }

    private nonisolated static func nonisolatedProbe() async -> Bool {
        onMainThread()
    }

    /// `openSync` blocks the calling thread; on the main actor that is the launch-watchdog
    /// hazard the skill warns about. Structural, not a timing race: the main queue cannot
    /// service its timer while the main thread is blocked.
    @Test("openSync blocks the main thread for the whole open; await open does not")
    @MainActor
    func openSyncBlocksTheMainThreadAndOpenDoesNot() async throws {
        let stall = MainQueueStall()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(5))
        timer.setEventHandler { stall.tick() }
        timer.resume()
        defer { timer.cancel() }

        try await Task.sleep(nanoseconds: 200_000_000)   // let the timer settle

        stall.reset()
        let asyncStarted = Date()
        let opened = try await Ditto.open(config: Self.makeConfig())
        let asyncDuration = Date().timeIntervalSince(asyncStarted)
        let asyncStall = stall.value

        stall.reset()
        let syncStarted = Date()
        let openedSync = try Ditto.openSync(config: Self.makeConfig())
        let syncDuration = Date().timeIntervalSince(syncStarted)
        let syncStall = stall.value

        print(String(
            format: "  await open : %6.1fms open, %6.1fms main-queue stall",
            asyncDuration * 1000, asyncStall * 1000
        ))
        print(String(
            format: "  openSync   : %6.1fms open, %6.1fms main-queue stall",
            syncDuration * 1000, syncStall * 1000
        ))

        let blocked: Comment = "openSync should have blocked the main queue for its whole duration (\(syncStall)s stall for a \(syncDuration)s open)"
        #expect(syncStall >= syncDuration * 0.5, blocked)
        let quieter: Comment = "await open stalled the main queue more than openSync did"
        #expect(asyncStall < syncStall, quieter)

        // Release both before the temporary directories go away.
        _ = opened
        _ = openedSync
    }

    private static func makeConfig() -> DittoConfig {
        DittoConfig(
            databaseID: SkillTestEnvironment.databaseID,
            connect: .smallPeersOnly(),
            persistenceDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("executor-\(UUID().uuidString)", isDirectory: true)
        )
    }
}
