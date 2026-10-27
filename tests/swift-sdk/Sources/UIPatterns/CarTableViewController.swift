//
// The UIKit half, in the two shapes that are actually correct.
//
//  * `CarTableViewController`       — the default. `UITableViewDiffableDataSource`
//                                     consumes `[Car]` directly; no DittoDiffer.
//  * `DifferCarTableViewController` — `DittoDiffer` + `performBatchUpdates`, for when
//                                     you need the raw index sets.
//

#if canImport(UIKit) && !os(watchOS)
import UIKit
import Foundation
import os

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

/// The SDK's signal may finish on another queue but is not annotated Sendable.
/// Transfer it through one synchronized owner and consume it at most once.
private final class DeliverySignal: @unchecked Sendable {
    private let lock = NSLock()
    private var signal: DittoSignalNext?

    init(_ signal: @escaping DittoSignalNext) { self.signal = signal }

    func call() {
        lock.lock()
        let next = signal
        signal = nil
        lock.unlock()
        next?()
    }
}

/// The recommended UIKit shape at the skill's iOS 15 minimum.
///
/// A diffable data source computes the diff itself from a snapshot, so the entire class
/// of "index sets disagree with the data source" crashes cannot occur. Reach for
/// `DittoDiffer` only when something other than a diffable data source needs the index
/// sets — see `DifferCarTableViewController` below.
@available(iOS 15, macCatalyst 15, *)
public final class CarTableViewController: UITableViewController {
    private let ditto: Ditto
    private var bridge: ObserverBridge?
    private var consumer: Task<Void, Never>?

    private lazy var dataSource = UITableViewDiffableDataSource<Int, Car.ID>(
        tableView: tableView
    ) { [weak self] tableView, indexPath, id in
        let cell = tableView.dequeueReusableCell(withIdentifier: "car", for: indexPath)
        if let car = self?.carsByID[id] {
            var content = cell.defaultContentConfiguration()
            content.text = car.make
            content.secondaryText = "\(car.mileage) mi"
            cell.contentConfiguration = content
        }
        return cell
    }

    private var carsByID: [Car.ID: Car] = [:]

    public init(ditto: Ditto) {
        self.ditto = ditto
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "car")
        tableView.dataSource = dataSource
        startObserving()
    }

    private func startObserving() {
        do {
            // One bounded stream, one consumer: unstructured per-delivery Tasks have no
            // ordering guarantee between them.
            let bridge = try ObserverBridge(ditto: ditto, query: "SELECT * FROM cars ORDER BY mileage")
            self.bridge = bridge

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

                    // Reconfigure only the rows whose CONTENT changed. Passing the whole
                    // list re-renders every visible cell on every delivery, which is the
                    // cost a diffable data source exists to avoid.
                    var seenChanged = Set<Car.ID>()
                    let changed = cars
                        .filter { previous[$0.id] != nil && previous[$0.id] != $0 }
                        .map(\.id)
                        .filter { seenChanged.insert($0).inserted }
                    if !changed.isEmpty { snapshot.reconfigureItems(changed) }

                    await self.dataSource.apply(snapshot, animatingDifferences: true)
                }
            }
        } catch {
            uiPatternsLogger.error("Failed to observe cars: \(error.localizedDescription, privacy: .public)")
        }
    }

    deinit {
        // Cancel at the owning scope's boundary. The controller going away does not
        // stop the observer; only `cancel()` does.
        consumer?.cancel()
        bridge?.cancel()
    }
}

/// The `DittoDiffer` shape, written so it cannot desynchronise.
///
/// Two rules make this safe, and both are easy to get wrong:
///
/// 1. **The array handed to the data source must be 1:1 with the array handed to the
///    differ.** `Array.cars()` maps rather than filters for exactly this reason. Drop a
///    row and `performBatchUpdates` raises *"invalid number of rows in section 0"*.
/// 2. **Reloads do not belong inside the batch.** `performBatchUpdates` treats deletes
///    and inserts as one atomic transition; a reload of a row that also moved is
///    undefined. Apply updates in the completion handler instead.
@available(iOS 15, macCatalyst 15, *)
public final class DifferCarTableViewController: UITableViewController {
    private let ditto: Ditto

    /// A `DittoDiffer` is stateful: it compares against the last array handed to *this*
    /// differ. One differ belongs to exactly one observer, is never shared, and must be
    /// replaced whenever the observer is re-registered — otherwise the first diff after
    /// re-registration is computed against a stale baseline.
    private var differ = DittoDiffer()

    private var observer: DittoStoreObserver?
    private var cars: [Car] = []

    /// Guards against a delivery hopped before the observer was cancelled arriving after
    /// a re-registration has reset the differ. Without it, that stale delivery diffs old
    /// items against a fresh baseline and the index sets stop describing any transition
    /// the table actually made.
    ///
    /// `startObserving()` is called once from `viewDidLoad` here, so the guard is not
    /// exercised — it is present because re-registering (a `viewDidAppear` /
    /// `viewDidDisappear` pair, as in the AppKit sample) is the obvious extension, and
    /// it is exactly the extension that introduces the race.
    private var generation = 0

    public init(ditto: Ditto) {
        self.ditto = ditto
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "car")
        startObserving()
    }

    private func startObserving() {
        // Cancel before reassigning. Dropping a `DittoStoreObserver` handle does NOT
        // stop it — it keeps firing and keeps its captures alive for the life of the
        // `Ditto` instance — so overwriting `observer` without this leaks one per call.
        observer?.cancel()
        // Reset the differ with the observer: its baseline is the last array it saw, and
        // the table is about to be repopulated from empty.
        differ = DittoDiffer()
        cars = []
        tableView.reloadData()
        generation &+= 1
        let myGeneration = generation
        do {
            observer = try ditto.store.registerObserver(
                query: "SELECT * FROM cars ORDER BY mileage"
            ) { @Sendable [weak self] result, signalNext in
                let completion = DeliverySignal(signalNext)
                // Hop to the main actor before touching the table view or the differ.
                // `deliverOn:` is ignored on 5.0.x, so this hop is what makes the same
                // code correct on all three supported lines.
                Task { @MainActor [weak self] in
                    // First statement in the body: a throw or early return below can
                    // never skip it. An observer whose handler returns without calling
                    // signalNext() stops delivering forever, silently.
                    defer { completion.call() }
                    guard let self, self.generation == myGeneration else { return }
                    self.apply(items: result.items)
                }
            }
        } catch {
            uiPatternsLogger.error("Failed to observe cars: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func apply(items: [DittoQueryResultItem]) {
        // Diff FIRST — `diff(_:)` needs the items materialized, and `cars()`
        // dematerializes them.
        let diff = differ.diff(items)
        cars = items.cars()

        // The first diff reports every item as an insertion, because the differ starts
        // empty — an initial population, not an animated insert of N rows.
        //
        // `diff.moves` is a full permutation, not a minimal edit script: one row moving
        // to the front of a three-row list emits (2->0), (0->1), (1->2). That is correct
        // for `performBatchUpdates`, whose `at:` indices are pre-update and `to:`
        // post-update — but it means a single reorder in a 500-row list issues ~500
        // moveRow calls per delivery.
        tableView.performBatchUpdates {
            tableView.deleteRows(at: diff.deletions.map { IndexPath(row: $0, section: 0) }, with: .automatic)
            tableView.insertRows(at: diff.insertions.map { IndexPath(row: $0, section: 0) }, with: .automatic)
            for move in diff.moves {
                tableView.moveRow(
                    at: IndexPath(row: move.from, section: 0),
                    to: IndexPath(row: move.to, section: 0)
                )
            }
        } completion: { [weak tableView] _ in
            // Reloads run after the batch, against post-update indices.
            tableView?.reloadRows(
                at: diff.updates.map { IndexPath(row: $0, section: 0) },
                with: .automatic
            )
        }
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cars.count
    }

    public override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "car", for: indexPath)
        let car = cars[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = car.make
        content.secondaryText = "\(car.mileage) mi"
        cell.contentConfiguration = content
        return cell
    }

    deinit {
        observer?.cancel()
    }
}
#endif
