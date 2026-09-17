//
// The AppKit half. Same rules as UIKit, plus the multi-window hazard: a window
// controller owns window-scoped observers, never the app-wide `Ditto` instance.
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

@available(macOS 12, *)
public final class CarTableController: NSViewController {
    /// Held weakly on purpose: the app delegate owns the instance for the whole app
    /// lifetime. Closing this window must not deallocate it.
    private unowned let ditto: Ditto

    private let differ = DittoDiffer()
    private let tableView = NSTableView()
    private var observer: DittoStoreObserver?
    private var cars: [Car] = []

    public init(ditto: Ditto) {
        self.ditto = ditto
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        view = scrollView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        startObserving()
    }

    private func startObserving() {
        do {
            observer = try ditto.store.registerObserver(
                query: "SELECT * FROM cars ORDER BY mileage"
            ) { [weak self] result, signalNext in
                Task { @MainActor [weak self] in
                    guard let self else {
                        signalNext()
                        return
                    }
                    self.apply(items: result.items)
                    signalNext()
                }
            }
        } catch {
            print("Failed to observe cars: \(error)")
        }
    }

    @MainActor
    private func apply(items: [DittoQueryResultItem]) {
        let diff = differ.diff(items)
        cars = items.compactMap { item -> Car? in
            defer { item.dematerialize() }
            return Car(item.value)
        }

        tableView.beginUpdates()
        tableView.removeRows(at: diff.deletions, withAnimation: .effectFade)
        tableView.insertRows(at: diff.insertions, withAnimation: .effectFade)
        tableView.reloadData(forRowIndexes: diff.updates, columnIndexes: IndexSet(integer: 0))
        for move in diff.moves {
            tableView.moveRow(at: move.from, to: move.to)
        }
        tableView.endUpdates()
    }

    /// Cancel when the window closes, not when the app quits.
    public override func viewDidDisappear() {
        super.viewDidDisappear()
        observer?.cancel()
        observer = nil
    }

    deinit {
        observer?.cancel()
    }
}
#endif
