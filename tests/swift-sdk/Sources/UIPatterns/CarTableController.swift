//
// The AppKit half. Uses `NSTableViewDiffableDataSource`, deliberately.
//
// `DittoDiffer`'s move list MUST NOT be replayed into `NSTableView` — see the note at
// the bottom of this file. The multi-window rule still applies: a window controller owns
// window-scoped observers, never the app-wide `Ditto` instance.
//

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
import Foundation

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

@available(macOS 12, *)
public final class CarTableController: NSViewController {
    /// A plain strong reference. `Ditto` holds nothing back to this controller, so there
    /// is no cycle to break, and keeping an app-lived object alive slightly longer is
    /// harmless. `unowned` would instead trap on any teardown order that released the
    /// app-wide instance first.
    private let ditto: Ditto

    private let tableView = NSTableView()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("car"))
    private var bridge: ObserverBridge?
    private var consumer: Task<Void, Never>?
    private var carsByID: [Car.ID: Car] = [:]

    private lazy var dataSource = NSTableViewDiffableDataSource<Int, Car.ID>(
        tableView: tableView
    ) { [weak self] tableView, _, row, id in
        let identifier = NSUserInterfaceItemIdentifier("CarCell")
        let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? {
                let field = NSTextField(labelWithString: "")
                field.identifier = identifier
                return field
            }()
        if let car = self?.carsByID[id] {
            textField.stringValue = "\(car.make) — \(car.mileage) mi"
        }
        return textField
    }

    public init(ditto: Ditto) {
        self.ditto = ditto
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        column.title = "Car"
        tableView.addTableColumn(column)
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        view = scrollView
        _ = dataSource
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        // `viewDidDisappear` fires on tab switches and window closes, so re-register
        // here or the screen is dead after the first disappearance.
        startObserving()
    }

    public override func viewDidDisappear() {
        super.viewDidDisappear()
        stopObserving()
    }

    private func startObserving() {
        guard bridge == nil else { return }
        do {
            let bridge = try ObserverBridge(ditto: ditto, query: "SELECT * FROM cars ORDER BY mileage")
            self.bridge = bridge
            // One consumer task, replaced wholesale on every re-registration. Because
            // the previous consumer is cancelled and a *new* stream is created, a
            // delivery still in flight from the old observer cannot reach the new data
            // source — the race a hand-rolled `Task`-per-delivery hop would have.
            consumer = Task { @MainActor [weak self] in
                for await cars in bridge.stream {
                    guard let self else { return }
                    let previous = self.carsByID
                    // `uniquingKeysWith:`, not `uniqueKeysWithValues:` — the latter
                    // traps on a duplicate id, and ids come from remote data.
                    self.carsByID = Dictionary(cars.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })

                    var snapshot = NSDiffableDataSourceSnapshot<Int, Car.ID>()
                    snapshot.appendSections([0])
                    // De-duplicate: `appendItems` fatals on repeated identifiers.
                    var seen = Set<Car.ID>()
                    snapshot.appendItems(cars.map(\.id).filter { seen.insert($0).inserted })

                    // Identity is `Car.ID`, so a content-only edit produces an empty
                    // diff. Ask explicitly for those rows to be re-rendered rather than
                    // relying on the data source to re-request views for an unchanged
                    // snapshot, which Apple does not promise.
                    //
                    // `reloadItems`, not `reconfigureItems`: AppKit's snapshot has no
                    // `reconfigureItems` at this deployment target, unlike UIKit's.
                    var seenChanged = Set<Car.ID>()
                    let changed = cars
                        .filter { previous[$0.id] != nil && previous[$0.id] != $0 }
                        .map(\.id)
                        .filter { seenChanged.insert($0).inserted }
                    if !changed.isEmpty { snapshot.reloadItems(changed) }

                    self.dataSource.apply(snapshot, animatingDifferences: true)
                }
            }
        } catch {
            uiPatternsLogger.error("Failed to observe cars: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopObserving() {
        consumer?.cancel()
        consumer = nil
        bridge?.cancel()
        bridge = nil
    }

    deinit {
        consumer?.cancel()
        bridge?.cancel()
    }
}

// MARK: - Why DittoDiffer is not used here
//
// `DittoDiffer.moves` is a **full permutation**, not a minimal edit script: moving one
// row to the front of a three-row list emits `(2→0), (0→1), (1→2)`. `UITableView`
// interprets a batch update's `at:` indices in the pre-update space and `to:` in the
// post-update space, so replaying that permutation inside `performBatchUpdates` is
// correct.
//
// `NSTableView.moveRow(at:to:)` has the opposite contract: each call applies immediately
// and sequentially, so the same three moves walk
// `[a,b,c] → [c,a,b] → [a,c,b] → [a,b,c]` and land back where they started while the
// model says `[c,a,b]`. The result is permanently stale rows, with no crash and no log.
//
// Replaying the differ into `NSTableView` therefore requires converting the permutation
// into sequential moves first. A diffable data source does that for you, which is why
// this sample uses one. See references/observers.md.
#endif
