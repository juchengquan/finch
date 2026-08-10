import SwiftUI
import FinchCore

/// The reconcile MODE's header — hosted by `AccountDetailVC` in an unselectable
/// cell while the mode is active (2026-08-10 design; the sheet survives only as
/// the macOS surface). Everything money-facing here is NATIVE currency, already
/// formatted by the caller through the store's privacy-aware helpers: this is
/// the one screen whose whole point is digit-matching a bank statement, so no
/// display-currency conversion may touch it (Aug 3 doc, carried forward).
///
/// Interactive SwiftUI in a hosted cell: Buttons/Toggles only — a bare gesture
/// here would eat the collection view's touches (see the picker post-mortem in
/// SearchablePickerRow).
/// The mode's live state, owned by `AccountDetailVC` and OBSERVED by the hosted
/// header — which is what lets the difference update on every keystroke without
/// reconfiguring the cell (a reconfigure would tear focus out of the statement
/// field mid-typing). Input fields notify the owner via closures; derived
/// fields are written back by the owner and re-render through @Published.
final class ReconcileSession: ObservableObject {
    @Published var statementBalanceText: String = "" { didSet { if oldValue != statementBalanceText { onInputChange?() } } }
    @Published var statementDate: Date = Date() { didSet { if oldValue != statementDate { onStructureChange?() } } }
    @Published var showReconciled: Bool = false { didSet { if oldValue != showReconciled { onStructureChange?() } } }
    // Derived — set by the owner, never by the view.
    @Published var currentBalanceText: String = ""
    @Published var differenceText: String = ""
    @Published var isBalanced: Bool = false
    @Published var diagnosisText: String?
    @Published var matchActionLabel: String?
    @Published var addMissingLabel: String?
    /// Balance text changed: derived figures need recomputing (no section change).
    var onInputChange: (() -> Void)?
    /// Date/toggle changed: the WINDOW changes — recompute and re-apply sections.
    var onStructureChange: (() -> Void)?
}

struct ReconcileHeaderView: View {
    @ObservedObject var session: ReconcileSession
    let accountName: String
    let currency: String
    var onJumpToMatch: () -> Void = {}
    var onAddMissing: () -> Void = {}
    var onFinish: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Reconciling", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                Text(accountName).font(.subheadline).foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Current balance").foregroundStyle(.secondary)
                    Text(session.currentBalanceText).gridColumnAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                GridRow {
                    Text("Statement balance").foregroundStyle(.secondary)
                    TextField("0.00", text: $session.statementBalanceText)
                        .moneyInput($session.statementBalanceText, currency: currency)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("reconcile.statementBalance")
                }
                GridRow {
                    Text("Statement date").foregroundStyle(.secondary)
                    DatePicker("", selection: $session.statementDate, displayedComponents: [.date])
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                GridRow {
                    Text("Difference").foregroundStyle(.secondary)
                    Text(session.differenceText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(session.isBalanced ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityIdentifier("reconcile.difference")
                }
            }
            .font(.callout)

            if let diagnosisText = session.diagnosisText {
                VStack(alignment: .leading, spacing: 6) {
                    Text(diagnosisText).font(.footnote).foregroundStyle(.secondary)
                    if let matchActionLabel = session.matchActionLabel {
                        Button(matchActionLabel) { onJumpToMatch() }
                            .font(.footnote.weight(.medium)).buttonStyle(.borderless)
                    } else if let addMissingLabel = session.addMissingLabel {
                        Button(addMissingLabel) { onAddMissing() }
                            .font(.footnote.weight(.medium)).buttonStyle(.borderless)
                            .accessibilityIdentifier("reconcile.addMissing")
                    }
                }
            }

            Toggle("Show reconciled", isOn: $session.showReconciled)
                .font(.callout)
                .accessibilityIdentifier("reconcile.showReconciled")

            // The seal MATERIALIZES only when balanced — the zero-difference
            // guard IS the gate; there is no other commit affordance anywhere.
            if session.isBalanced {
                Button { onFinish() } label: {
                    Text("Finish reconciliation")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reconcile.finish")
            }
        }
        .padding(.vertical, 6)
    }
}
