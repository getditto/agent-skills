//
// The UIKit half: this is what `DittoDiffer` exists for.
//
// One differ per observer, `handlerWithSignalNext` for back-pressure, batch updates
// from the returned index sets, and `signalNext()` on every path out of the handler.
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

#if DITTO_V4
@preconcurrency import DittoSwift
#else
import DittoSwift
#endif

@available(iOS 15, macCatalyst 15, *)
public final class CarTableViewController: UITableViewController {
    private let ditto: Ditto

    /// A `DittoDiffer` is stateful: it compares against the last array handed to *this*
    /// differ. One differ belongs to exactly one observer and is never shared or reused
    /// across queries.
    private let differ = DittoDiffer()

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
        do {
            observer = try ditto.store.registerObserver(
                query: "SELECT * FROM cars ORDER BY mileage"
            ) { [weak self] result, signalNext in
                // Hop to the main actor before touching the table view or the differ.
                // `deliverOn:` is ignored on 5.0.x, so this hop is what makes the same
                // code correct on all three supported lines.
                Task { @MainActor [weak self] in
                    guard let self else {
                        // Still signal: an observer whose handler returns without
                        // calling signalNext() stops delivering forever, silently.
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
        // Diff FIRST — `diff(_:)` needs the items materialized. Extracting values and
        // calling `dematerialize()` before the diff throws away what the differ reads.
        let diff = differ.diff(items)
        let updated = items.compactMap { item -> Car? in
            defer { item.dematerialize() }
            return Car(item.value)
        }
        cars = updated

        // The first diff reports every row as an insertion, because the differ starts
        // empty — that is an initial population, not an animated insert of N rows.
        tableView.performBatchUpdates {
            tableView.deleteRows(at: diff.deletions.map { IndexPath(row: $0, section: 0) }, with: .automatic)
            tableView.insertRows(at: diff.insertions.map { IndexPath(row: $0, section: 0) }, with: .automatic)
            tableView.reloadRows(at: diff.updates.map { IndexPath(row: $0, section: 0) }, with: .automatic)
            for move in diff.moves {
                tableView.moveRow(
                    at: IndexPath(row: move.from, section: 0),
                    to: IndexPath(row: move.to, section: 0)
                )
            }
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
        cell.textLabel?.text = "\(car.make) — \(car.mileage) mi"
        return cell
    }

    deinit {
        // Cancel at the owning scope's boundary. The controller going away does not
        // stop the observer; only `cancel()` does.
        observer?.cancel()
    }
}
#endif
