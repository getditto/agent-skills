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

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

/// The recommended UIKit shape at the skill's iOS 15 minimum.
///
/// A diffable data source computes the diff itself from a snapshot, so the entire class
/// of "index sets disagree with the data source" crashes cannot occur. Reach for
/// `DittoDiffer` only when something other than a diffable data source needs the index
/// sets — see `DifferCarTableViewController` below.
@available(iOS 15, macCatalyst 15, *)
public final class CarTableViewController: UITableViewController {
    private let ditto: Ditto
    private var observer: DittoStoreObserver?
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
        // One bounded stream, one consumer: unstructured per-delivery Tasks have no
        // ordering guarantee between them.
        let (updates, continuation) = AsyncStream<[Car]>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        do {
            let observer = try ditto.store.registerObserver(
                query: "SELECT * FROM cars ORDER BY mileage"
            ) { result in
                continuation.yield(result.items.cars())
            }
            self.observer = observer
            continuation.onTermination = { _ in observer.cancel() }
        } catch {
            continuation.finish()
            print("Failed to observe cars: \(error)")
            return
        }

        consumer = Task { @MainActor [weak self] in
            for await cars in updates {
                guard let self else { return }
                self.carsByID = Dictionary(uniqueKeysWithValues: cars.map { ($0.id, $0) })
                var snapshot = NSDiffableDataSourceSnapshot<Int, Car.ID>()
                snapshot.appendSections([0])
                snapshot.appendItems(cars.map(\.id))
                snapshot.reconfigureItems(cars.map(\.id))
                await self.dataSource.apply(snapshot, animatingDifferences: true)
            }
        }
    }

    deinit {
        // Cancel at the owning scope's boundary. The controller going away does not
        // stop the observer; only `cancel()` does.
        consumer?.cancel()
        observer?.cancel()
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
        differ = DittoDiffer()
        do {
            observer = try ditto.store.registerObserver(
                query: "SELECT * FROM cars ORDER BY mileage"
            ) { [weak self] result, signalNext in
                // Hop to the main actor before touching the table view or the differ.
                // `deliverOn:` is ignored on 5.0.x, so this hop is what makes the same
                // code correct on all three supported lines.
                Task { @MainActor [weak self] in
                    // First statement in the body: a throw or early return below can
                    // never skip it. An observer whose handler returns without calling
                    // signalNext() stops delivering forever, silently.
                    defer { signalNext() }
                    self?.apply(items: result.items)
                }
            }
        } catch {
            print("Failed to observe cars: \(error)")
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
