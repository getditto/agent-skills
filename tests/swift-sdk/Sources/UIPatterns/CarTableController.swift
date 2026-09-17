//
// The AppKit half. Same rules as UIKit, plus the multi-window hazard: a window
// controller owns window-scoped observers, never the app-wide `Ditto` instance.
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
public final class CarTableController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    /// A plain strong reference. `Ditto` holds nothing back to this controller, so
    /// there is no cycle to break, and keeping an app-lived object alive slightly
    /// longer is harmless. `unowned` would instead trap on any teardown order that
    /// released the app-wide instance first.
    private let ditto: Ditto

    /// Stateful, one per observer, replaced whenever the observer is re-registered.
    private var differ = DittoDiffer()

    private let tableView = NSTableView()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("car"))
    private var observer: DittoStoreObserver?
    private var cars: [Car] = []

    public init(ditto: Ditto) {
        self.ditto = ditto
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func loadView() {
        column.title = "Car"
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        view = scrollView
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        // `viewDidDisappear` fires on tab switches and window closes, so re-register
        // here or the screen is dead after the first disappearance.
        startObserving()
    }

    public override func viewDidDisappear() {
        super.viewDidDisappear()
        observer?.cancel()
        observer = nil
    }

    private func startObserving() {
        guard observer == nil else { return }
        // Reset the differ with the observer: its baseline is the last array it saw,
        // and the table is about to be repopulated from empty.
        differ = DittoDiffer()
        cars = []
        tableView.reloadData()

        do {
            observer = try ditto.store.registerObserver(
                query: "SELECT * FROM cars ORDER BY mileage"
            ) { [weak self] result, signalNext in
                Task { @MainActor [weak self] in
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
        // Diff first; `cars()` dematerializes, and it maps rather than filters so the
        // row count always matches the index sets.
        let diff = differ.diff(items)
        cars = items.cars()

        tableView.beginUpdates()
        tableView.removeRows(at: diff.deletions, withAnimation: .effectFade)
        tableView.insertRows(at: diff.insertions, withAnimation: .effectFade)
        for move in diff.moves {
            tableView.moveRow(at: move.from, to: move.to)
        }
        tableView.endUpdates()

        // Reloads are not batch operations and use post-update indices, so they run
        // after `endUpdates()`, never inside the batch.
        if !diff.updates.isEmpty {
            tableView.reloadData(
                forRowIndexes: diff.updates,
                columnIndexes: IndexSet(integer: 0)
            )
        }
    }

    // MARK: - NSTableViewDataSource / NSTableViewDelegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        cars.count
    }

    public func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("CarCell")
        let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? {
                let field = NSTextField(labelWithString: "")
                field.identifier = identifier
                return field
            }()
        let car = cars[row]
        textField.stringValue = "\(car.make) — \(car.mileage) mi"
        return textField
    }

    deinit {
        observer?.cancel()
    }
}
#endif
