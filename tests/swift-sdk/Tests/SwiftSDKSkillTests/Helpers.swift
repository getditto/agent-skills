import Foundation
import Testing
#if DITTO_V4
// 4.14.x predates the `Sendable` conformances v5 added: in Swift 6 language mode
// `Ditto` and `DittoStore` cannot cross an isolation boundary without this, and the
// build fails with "sending 'ditto' risks causing data races".
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif
@testable import SkillSupport

/// Awaits the first element of a stream that satisfies `predicate`, failing rather than
/// hanging if it never arrives. Tests use deterministic events, never sleeps.
func firstElement<Element: Sendable>(
    of stream: AsyncStream<Element>,
    timeout: Duration = .seconds(10),
    where predicate: @escaping @Sendable (Element) -> Bool = { _ in true }
) async throws -> Element {
    try await withThrowingTaskGroup(of: Element?.self) { group in
        group.addTask {
            for await element in stream where predicate(element) {
                return element
            }
            return nil
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            return nil
        }
        defer { group.cancelAll() }
        guard let result = try await group.next(), let element = result else {
            throw StreamTimeout()
        }
        return element
    }
}

struct StreamTimeout: Error {}

/// True when the fixture is built against the 4.14.x line.
var isV4: Bool {
    #if DITTO_V4
    return true
    #else
    return false
    #endif
}

/// True when the fixture is built against 5.0.x, where `deliverOn:` is ignored
/// (#SDKS-3856, fixed in 5.1.0).
var isV50: Bool {
    Ditto.version.hasPrefix("5.0.")
}

extension DittoError {
    var storeReason: DittoError.StoreErrorReason? {
        if case .storeError(let reason) = self { return reason }
        return nil
    }
}
